#!/bin/bash
# Publishes the Galley Go module. Go needs no tarball: the module proxy
# serves whatever git tags exist, but a nested module only resolves at
# prefixed tags, so this pushes bindings/go/v<VERSION> for the current
# commit when it is missing. Idempotent: an existing tag is a green skip.
#
# The pushed tag points at HEAD, which on a v* product-tag run is the
# tagged commit itself. Prerelease VERSIONs pass through unchanged; the Go
# toolchain reads them as semver.
#
# Run (CI publish-go job does this after the test gate is green):
#   ./scripts/go/publish_go.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="$(python3 "$ROOT/scripts/product_version.py")"

tag="bindings/go/v$VERSION"
if git -C "$ROOT" ls-remote --tags origin "$tag" | grep -q "$tag"; then
	echo "publish_go: skip $tag (already pushed)"
	exit 0
fi
echo "publish_go: pushing $tag"
git -C "$ROOT" tag "$tag"
git -C "$ROOT" push origin "$tag"
echo "publish_go: done"
