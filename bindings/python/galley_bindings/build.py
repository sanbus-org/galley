"""Builds a Galley parser and its CPython extension module for a grammar.

Usage:

    python -m galley_bindings <language-dir>

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

The tool drives generation and the consumer shared-library build, then
compiles the extension module in the shipped `_galley.c` against the built
library, leaving galley<ext-suffix> next to your grammar ready to import.

No checkout is needed: the published package carries the generator CLI
for every platform and the compile inputs (`compile-kit/`). Contributors
running from a Galley checkout without an assembled kit fall back to
`GALLEY_CHECKOUT` pointing at the checkout.

The grammar library (libgalley-python.*) is built directly next to the
grammar.

Environment overrides: ZIG_EXECUTABLE (default zig), CC (default taken
from the running interpreter's build), GALLEY_CLI (explicit generator
binary), GALLEY_CHECKOUT (contributor fallback: existing Galley working
tree). To fetch a checkout for convenience, use
examples/scripts/fetch-galley.sh, which clones into the system cache —
that cache is an examples-only convenience, not part of the bindings.
"""

from __future__ import annotations

import json
import os
import platform
import shlex
import subprocess
import sys
import sysconfig
from collections.abc import Sequence
from pathlib import Path
from typing import Any, NoReturn

LIBRARY_NAME = "galley-python"

PACKAGE_DIRECTORY = Path(__file__).resolve().parent
COMPILE_KIT_DIRECTORY = PACKAGE_DIRECTORY / "compile-kit"
GENERATOR_DIRECTORY = PACKAGE_DIRECTORY / "generator"


def fatal(message: str) -> NoReturn:
    print(f"galley-bindings: {message}", file=sys.stderr)
    raise SystemExit(1)


def run(command: Sequence[str | Path], **kwargs: Any) -> None:
    print("+", " ".join(shlex.quote(part) for part in map(str, command)))
    try:
        subprocess.run(list(map(str, command)), check=True, **kwargs)
    except FileNotFoundError:
        fatal(f"executable not found: {command[0]}")
    except subprocess.CalledProcessError:
        fatal(f"command failed: {' '.join(map(str, command))}")


def capture(command: Sequence[str | Path]) -> str:
    try:
        return subprocess.run(
            list(map(str, command)), check=True, capture_output=True, text=True
        ).stdout
    except (FileNotFoundError, subprocess.CalledProcessError) as error:
        fatal(f"failed to probe {command[0]}: {error}")


def zig_executable() -> str:
    return os.environ.get("ZIG_EXECUTABLE", "zig")


def compiler_executable() -> str:
    configured = os.environ.get("CC")
    if configured:
        return shlex.split(configured)[0]
    return shlex.split(sysconfig.get_config_var("CC") or "cc")[0]


def library_file_name() -> str:
    if sys.platform == "darwin":
        return f"lib{LIBRARY_NAME}.dylib"
    if os.name == "nt":
        return f"{LIBRARY_NAME}.dll"
    return f"lib{LIBRARY_NAME}.so"


def resolve_galley() -> Path | None:
    # GALLEY_CHECKOUT is the contributor fallback: an existing Galley
    # working tree, or None when absent or invalid. Fetching a checkout
    # into the system cache is an examples-only convenience
    # (examples/scripts/fetch-galley.sh), not part of the bindings.
    checkout_env = os.environ.get("GALLEY_CHECKOUT")
    if not checkout_env:
        return None
    checkout = Path(checkout_env)
    if not (checkout / "build.zig").is_file():
        return None
    return checkout


def resolve_compile_inputs() -> tuple[Path, Path]:
    """Where the consumer build and its sources live.

    Returns (build_file, source_root). The published package carries
    compile-kit/ (no checkout needed); contributors running from a
    checkout without an assembled kit fall back to GALLEY_CHECKOUT
    holding build.zig. Anything else is a loud error. Both legs run the
    same consumer build with the same flags; only the inputs differ.
    """
    kit_build_file = COMPILE_KIT_DIRECTORY / "build.zig"
    if kit_build_file.is_file():
        return kit_build_file, COMPILE_KIT_DIRECTORY / "sources"
    checkout = resolve_galley()
    if checkout is not None:
        return checkout / "bindings" / "c" / "consumer" / "build.zig", checkout
    fatal(
        "need compile inputs: the installed galley-bindings has no compile-kit/ "
        "(reinstall it) or, when running from a Galley checkout, set GALLEY_CHECKOUT "
        "at the checkout (must contain build.zig) or assemble the kit with "
        "scripts/js/assemble_compile_kit.sh."
    )


# Prebuilt generator CLI per platform: directory under generator/ holding
# the binary. riscv64 is deliberately skipped (no portable static target);
# 32-bit and BSD platforms fail loudly through the error below.
GENERATOR_CLI_PLATFORMS = {
    ("darwin", "arm64"): "cli-darwin-arm64/bin/galley",
    ("darwin", "x64"): "cli-darwin-x64/bin/galley",
    ("linux", "x64"): "cli-linux-x64/bin/galley",
    ("linux", "arm64"): "cli-linux-arm64/bin/galley",
    ("win32", "x64"): "cli-win32-x64/bin/galley.exe",
    ("win32", "arm64"): "cli-win32-arm64/bin/galley.exe",
}


def platform_key() -> tuple[str, str]:
    machine = platform.machine().lower()
    arch = {"x86_64": "x64", "amd64": "x64", "aarch64": "arm64"}.get(machine, machine)
    return sys.platform, arch


def resolve_generator_cli() -> Path:
    """The generator CLI to run, without building anything.

    Explicit GALLEY_CLI wins; then the shipped platform binary (present
    exactly when the package was installed with its generator data);
    then a checkout bootstrap, which needs GALLEY_CHECKOUT and zig.
    Anything else is a loud error naming every leg.
    """
    explicit = os.environ.get("GALLEY_CLI")
    if explicit:
        if not Path(explicit).is_file():
            fatal(f"GALLEY_CLI={explicit} does not exist")
        return Path(explicit).resolve()
    key = platform_key()
    target = GENERATOR_CLI_PLATFORMS.get(key)
    if target is not None:
        shipped = GENERATOR_DIRECTORY / target
        if shipped.is_file():
            return shipped
    checkout_env = os.environ.get("GALLEY_CHECKOUT")
    if checkout_env and (Path(checkout_env) / "build.zig").is_file():
        checkout = Path(checkout_env).resolve()
        binary = "galley.exe" if sys.platform == "win32" else "galley"
        cli = checkout / "zig-out" / "bin" / binary
        if not cli.exists():
            run(
                [zig_executable(), "build", "-Doptimize=ReleaseFast", "install"],
                cwd=checkout,
            )
        return cli
    shipped_names = sorted(
        {name.split("/")[0] for name in GENERATOR_CLI_PLATFORMS.values()}
    )
    installed = (
        f"reinstall galley-bindings with its generator data ({target})"
        if target is not None
        else f"no prebuilt generator exists for {key[0]}:{key[1]} (shipped: {', '.join(shipped_names)})"
    )
    fatal(
        "no generator CLI found (tried GALLEY_CLI, then the shipped platform "
        f"binary, then a checkout bootstrap).\nTo generate with no toolchain: {installed}.\n"
        "To bootstrap from source: set GALLEY_CHECKOUT at a Galley checkout with zig installed."
    )


def find_python_procedures_file(language_dir: Path) -> Path | None:
    candidate = language_dir / "procedures.py"
    if candidate.is_file():
        return candidate
    return None


def read_procedure_hooks(language_dir: Path) -> list[str]:
    # Hook names come from metadata.json, written by the generator alongside
    # procedures.zig. The generator owns the hook list; this tool renders it.
    metadata_path = language_dir / "metadata.json"
    try:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    except OSError as error:
        fatal(f"failed to read {metadata_path}: {error}")
    except ValueError as error:
        fatal(f"failed to parse {metadata_path}: {error}")
    hooks = metadata.get("procedures") if isinstance(metadata, dict) else None
    if (
        not isinstance(hooks, list)
        or not hooks
        or not all(isinstance(hook, str) for hook in hooks)
    ):
        fatal(f"{metadata_path} has no procedure hook list; update the Galley checkout")
    return hooks


def emit_python_procedure_shim(hooks: list[str], output_path: Path) -> None:
    builder: list[str] = []
    builder.append("// Generated by galley-bindings; DO NOT EDIT.")
    builder.append("// Procedure hooks dispatch through a Python callback registered")
    builder.append("// by the host's extension module; only enabled hooks cross.")
    builder.append('const std = @import("std");')
    builder.append('const root = @import("galley");')
    builder.append("pub const Payload = struct {};")
    builder.append("")
    builder.append(
        "var py_dispatch_target: ?*const fn ([*]const u8, usize, ?*anyopaque) callconv(.c) void = null;"
    )
    for name in hooks:
        builder.append(f"var py_enabled_{name}: bool = false;")
    builder.append("")
    builder.append(
        "fn dispatch(comptime name: []const u8, args: *root.data_structures.ProcedureArguments) void {"
    )
    builder.append("    if (py_dispatch_target) |target| {")
    builder.append("        target(name.ptr, name.len, @ptrCast(args));")
    builder.append("    }")
    builder.append("}")
    builder.append("")
    for name in hooks:
        builder.append(
            f"pub fn {name}(args: *root.data_structures.ProcedureArguments) void {{"
        )
        builder.append(f"    if (!py_enabled_{name}) return;")
        builder.append(f'    dispatch("{name}", args);')
        builder.append("}")
        builder.append("")
    builder.append(
        "const procedure_slots = [_]struct { name: []const u8, enabled: *bool }{"
    )
    for name in hooks:
        builder.append(f'    .{{ .name = "{name}", .enabled = &py_enabled_{name} }},')
    builder.append("};")
    builder.append("")
    builder.append(
        "export fn galley_install_python_dispatch(target: *const fn ([*]const u8, usize, ?*anyopaque) callconv(.c) void) void {"
    )
    builder.append("    py_dispatch_target = target;")
    builder.append("}")
    builder.append("")
    builder.append(
        "export fn galley_python_procedure_enable(name_ptr: [*]const u8, name_len: usize) c_int {"
    )
    builder.append("    const name = name_ptr[0..name_len];")
    builder.append("    inline for (&procedure_slots) |*slot| {")
    builder.append("        if (std.mem.eql(u8, slot.name, name)) {")
    builder.append("            slot.enabled.* = true;")
    builder.append("            return 1;")
    builder.append("        }")
    builder.append("    }")
    builder.append("    return 0;")
    builder.append("}")
    builder.append("")
    builder.append("export fn galley_python_procedure_clear() void {")
    builder.append("    inline for (&procedure_slots) |*slot| {")
    builder.append("        slot.enabled.* = false;")
    builder.append("    }")
    builder.append("}")
    builder.append("")
    output_path.write_text("\n".join(builder) + "\n", encoding="utf-8")


def compile_extension(
    source_root: Path,
    language_dir: Path,
    output_path: Path,
) -> None:
    include_dirs: list[str] = []
    for key in ("include", "platinclude"):
        candidate = sysconfig.get_paths()[key]
        if candidate not in include_dirs:
            include_dirs.append(candidate)

    arguments: list[str] = [compiler_executable(), "-O2", "-fPIC"]
    arguments += [f"-I{directory}" for directory in include_dirs]
    arguments += [
        "-I",
        str(source_root / "bindings" / "c"),
        str(source_root / "bindings" / "python" / "_galley.c"),
        "-o",
        str(output_path),
    ]
    if sys.platform == "darwin":
        arguments += ["-bundle", "-undefined", "dynamic_lookup"]
    else:
        arguments += ["-shared"]
    if sys.platform == "darwin":
        rpath = "@loader_path"
    elif sys.platform == "win32":
        rpath = None
    else:
        rpath = "$ORIGIN"
    arguments += [
        f"-L{language_dir}",
        "-l",
        LIBRARY_NAME,
    ]
    if rpath is not None:
        arguments += [f"-Wl,-rpath,{rpath}"]
    if sys.platform not in ("darwin", "win32"):
        # _galley.c uses dlsym(RTLD_DEFAULT) to find
        # galley_install_python_dispatch when the Python shim is in use.
        arguments += ["-ldl"]
    run(arguments)


def main() -> None:
    if len(sys.argv) != 2:
        fatal("usage: python -m galley_bindings <language-dir>")
    if os.name == "nt":
        fatal("the python bindings target POSIX platforms")
    language_dir = Path(sys.argv[1]).resolve()
    if not (language_dir / "ll.grm").is_file():
        fatal(f"{language_dir} does not contain ll.grm")

    # The gate owns all build semantics: generation resolves through
    # resolve_generator_cli, compiling through resolve_compile_inputs.
    # Both consumer-build legs run the same build with the same flags;
    # only the source root differs (kit for consumers, checkout for
    # contributors).
    cli = resolve_generator_cli()

    # Parser generation relies on flags introduced alongside the bindings
    # workflow; refuse with guidance when the resolved generator predates
    # them instead of failing deep inside generation.
    help_text = capture([cli, "--help"])
    if "--emit-metadata" not in help_text:
        fatal(
            f"the generator at {cli} is too old for the bindings "
            "workflow (no --emit-metadata support); update galley-bindings"
        )

    run([cli, "--emit-metadata", language_dir])

    # One library embeds one parser; the consumer build locates the file
    # generation produced from -Dlanguage-dir and infers the family from
    # the filename.
    procedure_hooks = read_procedure_hooks(language_dir)

    # Python-native procedures take precedence over C procedures: if a
    # procedures.py exists, generate a Python dispatch shim and use it
    # instead of the C extern stub. When neither Python nor C implementations
    # exist, still generate the Python shim as a no-op fallback so the library
    # links (hooks are simply no-ops until Python registers them via
    # galley.install_procedure).
    python_procedures_file = find_python_procedures_file(language_dir)
    procedures_zig_source: str | None = None
    procedures_c_source: str | None = None
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
        emit_python_procedure_shim(procedure_hooks, shim_path)
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
            emit_python_procedure_shim(procedure_hooks, shim_path)
            procedures_zig_source = str(shim_path)

    build_file, source_root = resolve_compile_inputs()
    consumer_arguments: list[str | Path] = [
        zig_executable(),
        "build",
        "--build-file",
        build_file,
        f"-Dlanguage-dir={language_dir}",
        f"-Dlib-name={LIBRARY_NAME}",
        f"-Doutput={library_file_name()}",
        "-Doptimize=ReleaseFast",
        "--prefix",
        language_dir,
        "install",
    ]
    if procedures_zig_source is not None:
        consumer_arguments.insert(
            -1, f"-Dprocedures-zig-source={procedures_zig_source}"
        )
    if procedures_c_source is not None:
        consumer_arguments.insert(-1, f"-Dprocedures-c-source={procedures_c_source}")
    # config.zig and {ll,lr}_error_messages.zig are inferred by the consumer
    # build from the parser location.
    run(consumer_arguments, cwd=language_dir)

    output_path = language_dir / f"galley{sysconfig.get_config_var('EXT_SUFFIX')}"
    compile_extension(source_root, language_dir, output_path)
    # Ship the PEP 484 stub alongside the extension so `ty`/`mypy`/`pyright`
    # resolve `import galley` (compiled extensions expose no Python source).
    stub_source = source_root / "bindings" / "python" / "galley.pyi"
    stub_target = language_dir / "galley.pyi"
    if stub_source.is_file():
        stub_target.write_bytes(stub_source.read_bytes())
    print(f"galley-bindings: built {output_path}; import galley from {language_dir}")


if __name__ == "__main__":
    main()
