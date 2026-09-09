#!/bin/bash
# Publishes the Galley Python package to PyPI.
#
# Idempotent: a version already on PyPI is skipped, so re-runs are green.
# The package is built from a temp copy whose pyproject.toml version is
# pinned to the root VERSION file. Repo files are never touched.
#
# Registry versions follow PEP 440, which has no dashes: a `-beta.1`
# prerelease publishes as `0.2.0beta.1` (the same release, normalized),
# `-dev.3` as `0.2.0.dev3`. Anything else unparseable fails loud.
#
# Auth is a PyPI API token (one-time setup: create one at
# https://pypi.org/manage/account/token/scope with the galley-bindings
# project scope, store it as the PYPI_API_TOKEN CI secret). The token is
# only required when a publish is actually needed; pure skip runs stay
# green without it.
#
# Run (CI publish-python job does this after the test gate is green):
#   ./scripts/python/publish_python.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_DIR="$ROOT/bindings/python"
VERSION="$(python3 "$ROOT/scripts/product_version.py")"

name="$(sed -n 's/^name = "\(.*\)"/\1/p' "$PACKAGE_DIR/pyproject.toml" | head -n 1)"
test "$name" = "galley-bindings" || {
	echo "publish_python: unexpected package name $name" >&2
	exit 1
}
# Normalize to PEP 440 without changing what the version denotes.
python_version="$VERSION"
case "$VERSION" in
*-alpha.*) python_version="${VERSION%-alpha.*}a${VERSION#*-alpha.}" ;;
*-beta.*) python_version="${VERSION%-beta.*}b${VERSION#*-beta.}" ;;
*-rc.*) python_version="${VERSION%-rc.*}rc${VERSION#*-rc.}" ;;
*-dev.*) python_version="${VERSION%-dev.*}.dev${VERSION#*-dev.}" ;;
*-*)
	echo "publish_python: prerelease $VERSION has no PEP 440 mapping" >&2
	exit 1
	;;
esac
if curl -fsSL "https://pypi.org/pypi/$name/$python_version/json" >/dev/null 2>&1; then
	echo "publish_python: skip $name@$python_version (already on the registry)"
	exit 0
fi
test -n "${PYPI_API_TOKEN:-}" || {
	echo "publish_python: $name@$python_version is new but PYPI_API_TOKEN is unset" >&2
	exit 1
}
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# Copy the package without build leftovers or the binding suite; snapshots
# must not leak into the distributions.
tar --exclude='./build' --exclude='./*.egg-info' --exclude='./__pycache__' --exclude='./tests' --exclude='./test-fixture' -cf - -C "$PACKAGE_DIR" . | tar -xf - -C "$work"
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
grep -q "^version = \"$python_version\"$" "$work/pyproject.toml" || {
	echo "publish_python: version pin failed" >&2
	exit 1
}
echo "publish_python: publishing $name@$python_version"
python3 -m build --outdir "$work/dist" "$work" >/dev/null
twine check "$work"/dist/* >/dev/null
TWINE_USERNAME=__token__ TWINE_PASSWORD="$PYPI_API_TOKEN" twine upload --non-interactive "$work"/dist/*
trap - EXIT
rm -rf "$work"
echo "publish_python: done"
