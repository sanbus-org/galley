#!/bin/bash
# Upserts the floating `dev-latest` GitHub release with stable-named
# assets (the no-registry channel: C/C++ kits, the Zig source tarball).
# Each main push retargets the tag to the pushed commit and replaces the
# assets in place, so the release holds exactly one dev snapshot and
# `zig fetch` / kit download URLs never change.
#
# Assets must already carry their stable names (e.g. galley-c-linux-x64
# .tar.gz, not versioned names): the caller renames, so this script never
# guesses naming conventions. Traceability comes from the release notes
# (commit SHA) and the VERSION file inside each kit.
#
# One creator per release: this script owns dev-latest; release-assets
# owns versioned releases. `gh release upload --clobber` is safe against
# concurrent writers, but only this script may create or retarget the tag.
#
# Requires GH_TOKEN (CI: secrets.GITHUB_TOKEN with `contents: write`)
# and a checkout with HEAD at the pushed commit.
#
# Usage: ./scripts/c/publish_dev_release.sh <assets-dir>
set -euo pipefail

test $# = 1 || {
	echo "publish_dev_release: usage: publish_dev_release.sh <assets-dir>" >&2
	exit 2
}
ASSETS="$1"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test -d "$ASSETS" || {
	echo "publish_dev_release: no such dir: $ASSETS" >&2
	exit 1
}
test -n "$(ls -A "$ASSETS")" || {
	echo "publish_dev_release: no assets in $ASSETS" >&2
	exit 1
}
command -v gh >/dev/null || {
	echo "publish_dev_release: gh is not installed" >&2
	exit 1
}
test -n "${GH_TOKEN:-}" || {
	echo "publish_dev_release: GH_TOKEN is unset" >&2
	exit 1
}

sha="$(git -C "$ROOT" rev-parse HEAD)"
notes="Development snapshot at $sha. Ephemeral: replaced on every main push. For anything durable use a versioned release."
if gh release view dev-latest >/dev/null 2>&1; then
	echo "publish_dev_release: retargeting dev-latest to $sha"
	git -C "$ROOT" push origin "HEAD:refs/tags/dev-latest" --force
	# The release follows its tag; only the notes need refreshing.
	gh release edit dev-latest --notes "$notes"
else
	echo "publish_dev_release: creating dev-latest at $sha"
	gh release create dev-latest --prerelease --target "$sha" \
		--title "dev-latest" --notes "$notes"
fi
# shellcheck disable=SC2086
gh release upload dev-latest $ASSETS/* --clobber
echo "publish_dev_release: done"
