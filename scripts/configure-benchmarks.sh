#!/usr/bin/env bash
#
# Reconfigure one row of the benchmark CI matrix.
#
# Usage:
#   scripts/configure-benchmarks.sh <grammar> [<galley-flag>...]
#
# <grammar> is a directory under languages/ (json or python). The script
# rewrites languages/<grammar>/config.zig in place by running the Galley
# CLI with the given flags (building the CLI first when it is missing),
# then repoints the compiled example benchmarks' ll.grm symlinks at
# languages/<grammar>/ll.grm and rewrites each of those benchmarks' configs
# the same way. languages/<grammar> and each example benchmark grammar get
# a host_procedures.zig so their parsers bind hooks to the session's host
# dispatch (disabled by default) instead of extern entry points nobody
# implements: the zig benchmark and every binding run the same hooks,
# whether or not the row builds the bindings. The python, js, java, and
# zig benchmark builds compile languages/<grammar> directly; c, cpp, rust,
# and go keep their own benchmark grammar directories.
#
# Every generation against languages/<grammar> pins --parser-type ll:
# one library embeds one parser, and languages/json also ships lr.grm.
set -euo pipefail

grammar="${1:?usage: configure-benchmarks.sh <grammar> [<galley-flag>...]}"
shift

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -f "${repo_root}/languages/${grammar}/ll.grm" ]]; then
	echo "unknown benchmark grammar '${grammar}': languages/${grammar}/ll.grm not found" >&2
	exit 1
fi

# The compiled examples below keep their own benchmark grammar
# directories; python, js, java, and zig compile languages/<grammar>
# directly. Every benchmark grammar directory lives exactly two levels
# below the repo root, so one relative target fits all of them.
dirs=(
	examples/c/benchmark
	examples/cpp/benchmark
	examples/rust/benchmark
	examples/go/benchmark
)

cli="${repo_root}/zig-out/bin/galley"
if [[ ! -x "$cli" ]]; then
	(cd "$repo_root" && zig build -Doptimize=ReleaseFast install)
fi

# One library embeds one parser: a generated LR parser left beside the LL
# parser this row builds makes the consumer build refuse the directory.
# Both parser files are generated, never tracked.
rm -f "${repo_root}/languages/${grammar}/_lr-parser.zig"
"$cli" --parser-type ll "$@" --emit-host-procedures "${repo_root}/languages/${grammar}"

for dir in "${dirs[@]}"; do
	ln -sfn "../../../languages/${grammar}/ll.grm" "${repo_root}/${dir}/ll.grm"
	"$cli" "$@" --emit-host-procedures "${repo_root}/${dir}"
done
echo "configured languages/${grammar} and ${#dirs[@]} example benchmark grammars"
