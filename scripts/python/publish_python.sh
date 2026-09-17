#!/bin/bash
# Publishes the Galley Python package to PyPI.
#
# Idempotent: a version already on PyPI is skipped, so re-runs are green.
# The package is built from a temp copy whose pyproject.toml version is
# pinned to the root VERSION file. Repo files are never touched.
#
# Registry versions follow PEP 440, which has no dashes: a `-beta.1`
# prerelease publishes as `0.2.0beta.1` (the same release, normalized),
# `-dev.3` as `0.2.0.dev3`. Anything else unparseable fails loud. The
# mapping lives in scripts/package_version.py (--flavor pep440), shared
# with the CI package job.
#
# Auth is a PyPI API token (one-time setup: create one at
# https://pypi.org/manage/account/token/scope with the galley-bindings
# project scope, store it as the PYPI_API_TOKEN CI secret). The token is
# only required when a publish is actually needed; pure skip runs stay
# green without it.
#
# Modes (the CI package/publish split):
#   default: assemble from this checkout, build, upload to PyPI.
#   ASSEMBLE_ONLY_DIR=<dir>: assemble and build exactly as for a publish,
#     copy sdist+wheel there, exit before touching the registry. Needs no
#     token. The CI package job uses this on every run.
#   PREBUILT_DIST=<dir>: skip assembly and build; check and upload the
#     distributions already in <dir> (produced by an ASSEMBLE_ONLY_DIR run
#     of this same script, so the bytes are identical).
#
# PACKAGE_VERSION overrides the root VERSION file (the CI package job sets
# it to the run version: dev versions on pushes, product version on tags).
# Local bootstrapping stays on the product version by default.
#
# Run (CI publish-python job does this after the test gate is green):
#   ./scripts/python/publish_python.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_DIR="$ROOT/bindings/python"
VERSION="${PACKAGE_VERSION:-"$(python3 "$ROOT/scripts/product_version.py")"}"

name="$(sed -n 's/^name = "\(.*\)"/\1/p' "$PACKAGE_DIR/pyproject.toml" | head -n 1)"
test "$name" = "galley-bindings" || {
	echo "publish_python: unexpected package name $name" >&2
	exit 1
}
# Normalize to PEP 440 without changing what the version denotes.
python_version="$(python3 "$ROOT/scripts/package_version.py" --flavor pep440 "$VERSION")"
if curl -fsSL "https://pypi.org/pypi/$name/$python_version/json" >/dev/null 2>&1; then
	echo "publish_python: skip $name@$python_version (already on the registry)"
	exit 0
fi
if [ -n "${PREBUILT_DIST:-}" ] && [ -n "${ASSEMBLE_ONLY_DIR:-}" ]; then
	echo "publish_python: PREBUILT_DIST and ASSEMBLE_ONLY_DIR are mutually exclusive" >&2
	exit 1
fi
if [ -n "${PREBUILT_DIST:-}" ]; then
	test -n "${PYPI_API_TOKEN:-}" || {
		echo "publish_python: $name@$python_version is new but PYPI_API_TOKEN is unset" >&2
		exit 1
	}
	echo "publish_python: publishing prebuilt $name@$python_version"
	test -d "$PREBUILT_DIST" || {
		echo "publish_python: no such dir: $PREBUILT_DIST" >&2
		exit 1
	}
	# Exactly the sdist plus one wheel this script builds: anything else
	# (empty dir, stale files, a neighbor version) fails here instead of
	# uploading the wrong bytes.
	base="${name//-/_}-$python_version"
	count=0
	for dist in "$PREBUILT_DIST"/*; do
		test -e "$dist" || {
			echo "publish_python: no distributions in $PREBUILT_DIST" >&2
			exit 1
		}
		count=$((count + 1))
	done
	test "$count" -eq 2 || {
		echo "publish_python: expected sdist+wheel in $PREBUILT_DIST, found $count files" >&2
		exit 1
	}
	test -f "$PREBUILT_DIST/$base.tar.gz" || {
		echo "publish_python: missing $base.tar.gz in $PREBUILT_DIST" >&2
		exit 1
	}
	wheel="$(printf '%s\n' "$PREBUILT_DIST"/"$base"-*.whl)"
	test "$(printf '%s\n' "$wheel" | wc -l)" -eq 1 && test -f "$wheel" || {
		echo "publish_python: expected exactly one $base-*.whl in $PREBUILT_DIST" >&2
		exit 1
	}
	twine check "$PREBUILT_DIST"/* >/dev/null
	TWINE_USERNAME=__token__ TWINE_PASSWORD="$PYPI_API_TOKEN" twine upload --non-interactive "$PREBUILT_DIST"/*
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		printf 'headline_url=%s\n' "https://pypi.org/project/$name/$python_version/" >>"$GITHUB_OUTPUT"
	fi
	echo "publish_python: done"
	exit 0
fi
# The token is only required for a real publish; assemble-only runs (the
# CI package job) stay green without it, as do pure skip runs above.
if [ -z "${ASSEMBLE_ONLY_DIR:-}" ]; then
	test -n "${PYPI_API_TOKEN:-}" || {
		echo "publish_python: $name@$python_version is new but PYPI_API_TOKEN is unset" >&2
		exit 1
	}
fi
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# Copy the package without build leftovers or the binding suite; snapshots
# must not leak into the distributions.
tar --exclude='./build' --exclude='./*.egg-info' --exclude='./__pycache__' --exclude='./tests' --exclude='./test-fixture' -cf - -C "$PACKAGE_DIR" . | tar -xf - -C "$work"
# Consumers generate and compile with no checkout: ship the compile kit
# (assembled fresh from this checkout; the repo never tracks it) and the
# generator CLI for every platform, laid out under generator/ by
# build_compiler_binaries.sh under $CLI_ARTIFACTS/<dir>/bin/. One wheel
# carries all six binaries (~25MB uncompressed); pip cannot select
# per-platform data the way npm's optionalDependencies do, and platform
# wheels would only move the split without changing the gate, which
# already selects by platform at runtime.
"$ROOT/scripts/js/assemble_compile_kit.sh" "$work/galley_bindings/compile-kit"
: "${CLI_ARTIFACTS:?publish_python: set CLI_ARTIFACTS at built compiler binaries (scripts/js/build_compiler_binaries.sh)}"
for cli_dir in cli-darwin-arm64 cli-darwin-x64 cli-linux-x64 cli-linux-arm64 cli-win32-x64 cli-win32-arm64; do
	mkdir -p "$work/galley_bindings/generator/$cli_dir/bin"
	cp "$CLI_ARTIFACTS/$cli_dir"/bin/galley* "$work/galley_bindings/generator/$cli_dir/bin/"
	chmod +x "$work"/galley_bindings/generator/"$cli_dir"/bin/galley*
done
# The root VERSION file is the single source of truth for the version too,
# not just the skip check above.
python3 - "$work/pyproject.toml" "$python_version" <<'EOF'
import re
import sys
manifest, version = sys.argv[1], sys.argv[2]
text = open(manifest).read()
updated, count = re.subn(r'^version = ".*"$', f'version = "{version}"', text, count=1, flags=re.MULTILINE)
assert count == 1
open(manifest, "w").write(updated)
EOF
grep -qxF "version = \"$python_version\"" "$work/pyproject.toml" || {
	echo "publish_python: version pin failed" >&2
	exit 1
}
echo "publish_python: publishing $name@$python_version"
python3 -m build --outdir "$work/dist" "$work" >/dev/null
twine check "$work"/dist/* >/dev/null
if [ -n "${ASSEMBLE_ONLY_DIR:-}" ]; then
	mkdir -p "$ASSEMBLE_ONLY_DIR"
	cp "$work"/dist/* "$ASSEMBLE_ONLY_DIR/"
	trap - EXIT
	rm -rf "$work"
	echo "publish_python: assembled $name@$python_version in $ASSEMBLE_ONLY_DIR"
	exit 0
fi
TWINE_USERNAME=__token__ TWINE_PASSWORD="$PYPI_API_TOKEN" twine upload --non-interactive "$work"/dist/*
if [ -n "${GITHUB_OUTPUT:-}" ]; then
	printf 'headline_url=%s\n' "https://pypi.org/project/$name/$python_version/" >>"$GITHUB_OUTPUT"
fi
trap - EXIT
rm -rf "$work"
echo "publish_python: done"
