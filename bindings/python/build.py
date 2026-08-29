#!/usr/bin/env python3
"""Builds a Galley parser and its CPython extension module for a grammar.

Usage:

    python3 <galley>/bindings/python/build.py <language-dir>

The language dir must contain ll.grm and galley.json (generation options)
and may contain procedures.c (procedure hook implementations) and an
ll_error_messages.zig / lr_error_messages.zig (custom syntax-error message
hooks), mirroring the C, C++, Rust, and Go consumers.

The tool drives two commands from Galley's own checkout — generation and
the consumer shared-library build — then compiles the extension module in
bindings/python/_galley.c against the built library, leaving
galley<ext-suffix> next to your grammar ready to import.

Environment overrides: ZIG_EXECUTABLE (default zig), CC (default taken
from the running interpreter's build).
"""

import os
import shlex
import subprocess
import sys
import sysconfig
import tempfile
from pathlib import Path

LIBRARY_NAME = "galley-python"


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


def resolve_galley():
    # This script lives at <checkout>/bindings/python/build.py, so the
    # checkout it belongs to is always the right tree to build against.
    checkout = Path(__file__).resolve().parents[2]
    if not (checkout / "build.zig").exists():
        fatal(f"{checkout} is not a Galley repository checkout (no build.zig)")
    return checkout


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
    run(arguments)


def main():
    if len(sys.argv) != 2:
        fatal("usage: build.py <language-dir>")
    if os.name == "nt":
        fatal("the python bindings target POSIX platforms")
    language_dir = Path(sys.argv[1]).resolve()
    if not (language_dir / "ll.grm").is_file():
        fatal(f"{language_dir} does not contain ll.grm")

    galley_source = resolve_galley()
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
    optional_files = [
        ("-Dprocedures-zig-source=", "procedures.zig"),
        ("-Dprocedures-c-source=", "procedures.c"),
        (
            "-Derror-messages-zig-source=",
            f"{parser_type}_error_messages.zig",
        ),
    ]
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
    for flag, relative_path in optional_files:
        candidate = language_dir / relative_path
        if candidate.is_file():
            consumer_arguments.insert(-1, flag + str(candidate))
    run(consumer_arguments, cwd=galley_source)

    output_path = language_dir / f"galley{sysconfig.get_config_var('EXT_SUFFIX')}"
    compile_extension(galley_source, parser_source, parser_type, prefix, output_path)
    print(f"galley-bindings: built {output_path}; import galley from {language_dir}")


if __name__ == "__main__":
    main()
