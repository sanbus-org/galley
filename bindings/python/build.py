#!/usr/bin/env python3
"""Builds a Galley parser and its CPython extension module for a grammar.

Usage:

    python3 <galley>/bindings/python/build.py <language-dir>

The language dir must contain ll.grm and config.zig (generation options)
and may contain procedure hook implementations and custom message hooks,
mirroring the C, C++, Rust, and Go consumers:

* `procedures.py` — Python hooks (``def
  reduction_<Var>(args)`` / ``def hook_<name>(args)``), dispatched through
  a generated Python shim. Python hooks are registered at import time
  (``procedures`` on ``sys.path`` is tried) and can also be managed
  explicitly via ``galley.install_procedure``. This is the native-language
  path mirroring Rust's ``procedures.rs``.
* `procedures.c` / `procedures.cpp` — legacy C/C++ hooks compiled into the
  shared library, exactly like the C/C++ consumers. Python hooks take
  precedence when both exist (a warning is emitted).
* `ll_error_messages.zig` / `lr_error_messages.zig` — custom syntax-error
  message hooks.

The tool drives two commands from Galley's own checkout — generation and
the consumer shared-library build — then compiles the extension module in
bindings/python/_galley.c against the built library, leaving
galley<ext-suffix> next to your grammar ready to import.

Environment overrides: ZIG_EXECUTABLE (default zig), CC (default taken
from the running interpreter's build), GALLEY_CHECKOUT (existing Galley
working tree, wins over fetching), GALLEY_REPOSITORY, GALLEY_TAG (default
main). Galley checkout resolution follows docs/bindings.md.
"""

import os
import re
import shlex
import subprocess
import sys
import sysconfig
import tempfile
from pathlib import Path

LIBRARY_NAME = "galley-python"
DEFAULT_GALLEY_REPOSITORY = "https://github.com/sanbus-org/galley.git"
DEFAULT_GALLEY_TAG = "main"


def fatal(message):
    print(f"galley-bindings: {message}", file=sys.stderr)
    raise SystemExit(1)


def run(command, **kwargs):
    print("+", " ".join(shlex.quote(part) for part in map(str, command)))
    try:
        subprocess.run(list(map(str, command)), check=True, **kwargs)
    except FileNotFoundError:
        fatal(f"executable not found: {command[0]}")
    except subprocess.CalledProcessError:
        fatal(f"command failed: {' '.join(map(str, command))}")


def capture(command):
    try:
        return subprocess.run(
            list(map(str, command)), check=True, capture_output=True, text=True
        ).stdout
    except (FileNotFoundError, subprocess.CalledProcessError) as error:
        fatal(f"failed to probe {command[0]}: {error}")


def zig_executable():
    return os.environ.get("ZIG_EXECUTABLE", "zig")


def compiler_executable():
    configured = os.environ.get("CC")
    if configured:
        return shlex.split(configured)[0]
    return shlex.split(sysconfig.get_config_var("CC") or "cc")[0]


def cache_dir():
    if sys.platform == "darwin":
        root = os.environ.get("HOME", str(Path.home())) + "/Library/Caches"
    elif os.name == "nt":
        root = os.environ.get("LOCALAPPDATA", tempfile.gettempdir())
    else:
        root = os.environ.get(
            "XDG_CACHE_HOME", os.environ.get("HOME", str(Path.home())) + "/.cache"
        )
    directory = Path(root) / "galley-bindings" / "python"
    directory.mkdir(parents=True, exist_ok=True)
    return directory


# detect_parser reports which parser family generation produced (one
# library embeds one parser; both families present is ambiguous).
def detect_parser(language_dir):
    has_ll = (language_dir / "_ll-parser.zig").exists()
    has_lr = (language_dir / "_lr-parser.zig").exists()
    if has_ll and not has_lr:
        return "_ll-parser.zig", "ll"
    if has_lr and not has_ll:
        return "_lr-parser.zig", "lr"
    if has_ll and has_lr:
        fatal(
            f"both _ll-parser.zig and _lr-parser.zig exist in {language_dir}; "
            "one library embeds one parser — split the language dirs"
        )
    fatal(f"generation produced no parser in {language_dir}")


def find_python_procedures_file(language_dir):
    candidate = language_dir / "procedures.py"
    if candidate.is_file():
        return candidate
    return None


def parse_procedures_zig_hooks(procedures_zig_path):
    try:
        text = procedures_zig_path.read_text(encoding="utf-8")
    except OSError:
        return []
    pattern = re.compile(r"pub\s+extern\s+fn\s+(\w+)\s*\(.*\)\s*\w+\s*;")
    hooks = []
    seen = set()
    for match in pattern.finditer(text):
        name = match.group(1)
        if name not in seen:
            seen.add(name)
            hooks.append(name)
    return hooks


def emit_python_procedure_shim(template_path, output_path):
    try:
        template = template_path.read_text(encoding="utf-8")
    except OSError as error:
        fatal(f"failed to read {template_path}: {error}")
    # Extract hook declarations and passthrough lines (Payload, imports).
    pattern = re.compile(r"pub\s+extern\s+fn\s+(\w+)\s*\((.*)\)\s*(\w+)\s*;")
    hooks = []
    passthrough = []
    for line in template.splitlines():
        match = pattern.match(line.strip())
        if match:
            hooks.append((match.group(1), match.group(2), match.group(3)))
            continue
        if (
            line.strip().startswith("pub extern")
            or line.strip().startswith("// Auto-generated")
            or line.strip().startswith("// Implement these functions")
        ):
            continue
        passthrough.append(line)

    builder = []
    builder.append("// Generated by galley-bindings; DO NOT EDIT.")
    builder.append("// Procedure hooks dispatch through a Python callback registered")
    builder.append("// by the host's extension module; unregistered slots are no-ops.")
    builder.append('const std = @import("std");')
    for line in passthrough:
        builder.append(line)
    if builder and builder[-1].strip() != "":
        builder.append("")
    builder.append(
        "var py_dispatch_target: ?*const fn ([*]const u8, usize, ?*anyopaque) callconv(.c) void = null;"
    )
    builder.append("")
    builder.append(
        "fn dispatch(comptime name: []const u8, args: *root.data_structures.ProcedureArguments) void {"
    )
    builder.append("    if (py_dispatch_target) |target| {")
    builder.append("        target(name.ptr, name.len, @ptrCast(args));")
    builder.append("    }")
    builder.append("}")
    builder.append("")
    for name, params, ret in hooks:
        # params is "*root.data_structures.ProcedureArguments"; give it the name `args`
        # so the body can reference it. The type string already includes the leading `*`.
        builder.append(f"pub fn {name}(args: {params}) {ret} {{")
        builder.append(f'    dispatch("{name}", args);')
        builder.append("}")
        builder.append("")
    builder.append(
        "export fn galley_install_python_dispatch(target: *const fn ([*]const u8, usize, ?*anyopaque) callconv(.c) void) void {"
    )
    builder.append("    py_dispatch_target = target;")
    builder.append("}")
    builder.append("")
    output_path.write_text("\n".join(builder) + "\n", encoding="utf-8")


def resolve_galley(cache_dir_path=None):
    # Resolves the Galley checkout to build against, following docs/bindings.md:
    # GALLEY_CHECKOUT wins; otherwise if this script lives inside a Galley
    # checkout (local dev), use that checkout; otherwise fetch
    # GALLEY_REPOSITORY at GALLEY_TAG into <cache>/galley-src, mirroring
    # bindings/go/cmd/galley and bindings/rust/src/build_helper.rs.
    checkout_env = os.environ.get("GALLEY_CHECKOUT")
    if checkout_env:
        checkout = Path(checkout_env)
        if not (checkout / "build.zig").exists():
            fatal(
                f"GALLEY_CHECKOUT={checkout} is not a Galley repository checkout (no build.zig)"
            )
        return checkout
    # Local dev: script lives at <galley>/bindings/python/build.py
    candidate = Path(__file__).resolve().parents[2]
    if (candidate / "build.zig").exists():
        return candidate
    # Fall back to fetching, using the same cache dir as the capi prefix.
    if cache_dir_path is None:
        cache_dir_path = cache_dir()
    else:
        cache_dir_path = Path(cache_dir_path)
    tag = os.environ.get("GALLEY_TAG", DEFAULT_GALLEY_TAG)
    repository = os.environ.get("GALLEY_REPOSITORY", DEFAULT_GALLEY_REPOSITORY)
    source_dir = cache_dir_path / "galley-src"
    stamp = cache_dir_path / "galley-tag"
    try:
        previous = stamp.read_text(encoding="utf-8").strip() if stamp.is_file() else ""
    except OSError:
        previous = ""
    if source_dir.exists() and previous == tag:
        return source_dir
    # Fresh clone
    import shutil

    if source_dir.exists():
        shutil.rmtree(source_dir, ignore_errors=True)
    run(
        [
            "git",
            "clone",
            "--depth",
            "1",
            "--branch",
            tag,
            "--single-branch",
            "--recurse-submodules=false",
            repository,
            str(source_dir),
        ]
    )
    try:
        stamp.write_text(tag, encoding="utf-8")
    except OSError as error:
        fatal(f"failed to write tag stamp: {error}")
    return source_dir


def compile_extension(galley_source, parser_source, parser_type, prefix, output_path):
    include_dirs = []
    for key in ("include", "platinclude"):
        candidate = sysconfig.get_paths()[key]
        if candidate not in include_dirs:
            include_dirs.append(candidate)

    library_dir = prefix / "lib"
    arguments = [compiler_executable(), "-O2", "-fPIC"]
    arguments += [f"-I{directory}" for directory in include_dirs]
    arguments += [
        "-I",
        str(prefix / "include"),
        str(galley_source / "bindings" / "python" / "_galley.c"),
        "-o",
        str(output_path),
    ]
    if sys.platform == "darwin":
        arguments += ["-bundle", "-undefined", "dynamic_lookup"]
    else:
        arguments += ["-shared"]
    arguments += [
        f"-L{library_dir}",
        f"-Wl,-rpath,{library_dir}",
        "-l",
        LIBRARY_NAME,
    ]
    if sys.platform not in ("darwin", "win32"):
        # _galley.c uses dlsym(RTLD_DEFAULT) to find
        # galley_install_python_dispatch when the Python shim is in use.
        arguments += ["-ldl"]
    run(arguments)


def main():
    if len(sys.argv) != 2:
        fatal("usage: build.py <language-dir>")
    if os.name == "nt":
        fatal("the python bindings target POSIX platforms")
    language_dir = Path(sys.argv[1]).resolve()
    if not (language_dir / "ll.grm").is_file():
        fatal(f"{language_dir} does not contain ll.grm")

    # Resolve cache dir first so resolve_galley can use it for fetching.
    cache_for_galley = cache_dir()
    galley_source = resolve_galley(cache_for_galley)
    cli = galley_source / "zig-out" / "bin" / "galley"
    if not cli.exists():
        run(
            [zig_executable(), "build", "-Doptimize=ReleaseFast", "install"],
            cwd=galley_source,
        )

    # Parser generation relies on flags introduced alongside the bindings
    # workflow; refuse with guidance when the resolved Galley predates them
    # instead of failing deep inside generation.
    help_text = capture([cli, "--help"])
    if "--emit-metadata" not in help_text:
        fatal(
            f"the Galley at {galley_source} is too old for the bindings "
            "workflow (no --emit-metadata support); update the checkout"
        )

    run([cli, "--emit-metadata", language_dir])

    parser_source, parser_type = detect_parser(language_dir)

    prefix = cache_dir() / "capi"
    # Python-native procedures take precedence over C procedures: if a
    # procedures.py exists, generate a Python dispatch shim and use it
    # instead of the C extern stub. When neither Python nor C implementations
    # exist, still generate the Python shim as a no-op fallback so the library
    # links (hooks are simply no-ops until Python registers them via
    # galley.install_procedure).
    python_procedures_file = find_python_procedures_file(language_dir)
    procedures_zig_source = None
    procedures_c_source = None
    has_c_procedures = (language_dir / "procedures.c").is_file() or (
        language_dir / "procedures.cpp"
    ).is_file()
    if python_procedures_file is not None:
        if has_c_procedures:
            print(
                f"galley-bindings: both Python ({python_procedures_file}) and C procedures found — using Python",
                file=sys.stderr,
            )
        print(f"galley-bindings: using Python procedures from {python_procedures_file}")
        shim_path = language_dir / "procedures_python.zig"
        template_path = language_dir / "procedures.zig"
        emit_python_procedure_shim(template_path, shim_path)
        procedures_zig_source = str(shim_path)
    elif has_c_procedures:
        # Legacy C workflow: procedures.zig extern stub + procedures.c
        # implementation, exactly like the C/C++ consumers.
        if (language_dir / "procedures.zig").is_file():
            procedures_zig_source = str(language_dir / "procedures.zig")
        if (language_dir / "procedures.c").is_file():
            procedures_c_source = str(language_dir / "procedures.c")
        elif (language_dir / "procedures.cpp").is_file():
            procedures_c_source = str(language_dir / "procedures.cpp")
    else:
        # No Python or C implementation: generate a Python dispatch shim
        # that is initially a no-op. This lets the library link and allows
        # hooks to be registered later via galley.install_procedure without
        # requiring a rebuild, mirroring Go's always-shim model.
        if (language_dir / "procedures.zig").is_file():
            shim_path = language_dir / "procedures_python.zig"
            template_path = language_dir / "procedures.zig"
            emit_python_procedure_shim(template_path, shim_path)
            procedures_zig_source = str(shim_path)

    consumer_arguments = [
        zig_executable(),
        "build",
        "--build-file",
        galley_source / "bindings" / "c" / "consumer" / "build.zig",
        f"-Dparser-source={language_dir / parser_source}",
        f"-Dparser-type={parser_type}",
        f"-Dlib-name={LIBRARY_NAME}",
        "-Doptimize=ReleaseFast",
        "--prefix",
        prefix,
        "install",
    ]
    if procedures_zig_source is not None:
        consumer_arguments.insert(
            -1, f"-Dprocedures-zig-source={procedures_zig_source}"
        )
    if procedures_c_source is not None:
        consumer_arguments.insert(-1, f"-Dprocedures-c-source={procedures_c_source}")
    # config.zig and {ll,lr}_error_messages.zig are inferred by the consumer
    # build when omitted; only pass an explicit error-messages source when it
    # exists.
    error_messages_candidate = language_dir / f"{parser_type}_error_messages.zig"
    if error_messages_candidate.is_file():
        consumer_arguments.insert(
            -1, f"-Derror-messages-zig-source={error_messages_candidate}"
        )
    run(consumer_arguments, cwd=galley_source)

    output_path = language_dir / f"galley{sysconfig.get_config_var('EXT_SUFFIX')}"
    compile_extension(galley_source, parser_source, parser_type, prefix, output_path)
    # Ship the PEP 484 stub alongside the extension so `ty`/`mypy`/`pyright`
    # resolve `import galley` (compiled extensions expose no Python source).
    stub_source = galley_source / "bindings" / "python" / "galley.pyi"
    stub_target = language_dir / "galley.pyi"
    if stub_source.is_file():
        stub_target.write_bytes(stub_source.read_bytes())
    print(f"galley-bindings: built {output_path}; import galley from {language_dir}")


if __name__ == "__main__":
    main()
