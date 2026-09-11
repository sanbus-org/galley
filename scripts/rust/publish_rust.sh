#!/bin/bash
# Publishes the Galley Rust crate to crates.io.
#
# Idempotent: a VERSION already on crates.io is skipped, so re-runs are
# green. The crate is published from a temp copy whose Cargo.toml version
# is pinned to the root VERSION file. Repo files are never touched.
#
# Auth is a crates.io API token (one-time setup: create one at
# https://crates.io/settings/tokens with the publish scope, store it as
# the CARGO_REGISTRY_TOKEN CI secret). The token is only required when a
# publish is actually needed; pure skip runs stay green without it.
#
# Run (CI publish-rust job does this after the test gate is green):
#   ./scripts/rust/publish_rust.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CRATE_DIR="$ROOT/bindings/rust"
VERSION="$(python3 "$ROOT/scripts/product_version.py")"

name="$(sed -n 's/^name = "\(.*\)"/\1/p' "$CRATE_DIR/Cargo.toml" | head -n 1)"
test "$name" = "galley" || {
	echo "publish_rust: unexpected crate name $name" >&2
	exit 1
}
if curl -fsSL -H "User-Agent: galley-publish (https://github.com/sanbus-org/galley)" "https://crates.io/api/v1/crates/$name/$VERSION" >/dev/null 2>&1; then
	echo "publish_rust: skip $name@$VERSION (already on the registry)"
	exit 0
fi
test -n "${CARGO_REGISTRY_TOKEN:-}" || {
	echo "publish_rust: $name@$VERSION is new but CARGO_REGISTRY_TOKEN is unset" >&2
	exit 1
}
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# Copy the crate without the build tree or the separate test-fixture
# package; snapshots must not leak in.
tar --exclude='./target' --exclude='./test-fixture' -cf - -C "$CRATE_DIR" . | tar -xf - -C "$work"
# Consumers generate and compile with no checkout: ship the compile kit
# (assembled fresh from this checkout; the repo never tracks it) and the
# generator CLI for every platform, laid out under generator/ by
# build_compiler_binaries.sh under $CLI_ARTIFACTS/<dir>/bin/. One crate
# carries all six binaries; the gate already selects by platform at
# build time, so splitting into platform crates later changes packaging
# only.
"$ROOT/scripts/js/assemble_compile_kit.sh" "$work/compile-kit"
: "${CLI_ARTIFACTS:?publish_rust: set CLI_ARTIFACTS at built compiler binaries (scripts/js/build_compiler_binaries.sh)}"
for cli_dir in cli-darwin-arm64 cli-darwin-x64 cli-linux-x64 cli-linux-arm64 cli-win32-x64 cli-win32-arm64; do
	mkdir -p "$work/generator/$cli_dir/bin"
	cp "$CLI_ARTIFACTS/$cli_dir"/bin/galley* "$work/generator/$cli_dir/bin/"
	chmod +x "$work"/generator/"$cli_dir"/bin/galley*
done
# The root VERSION file is the single source of truth for the version too,
# not just the skip check above.
python3 - "$work/Cargo.toml" "$VERSION" <<'EOF'
import re
import sys
manifest, version = sys.argv[1], sys.argv[2]
text = open(manifest).read()
updated, count = re.subn(r'^version = ".*"$', f'version = "{version}"', text, count=1, flags=re.MULTILINE)
assert count == 1
open(manifest, "w").write(updated)
EOF
grep -q "^version = \"$VERSION\"$" "$work/Cargo.toml" || {
	echo "publish_rust: version pin failed" >&2
	exit 1
}
echo "publish_rust: publishing $name@$VERSION"
cargo publish --manifest-path "$work/Cargo.toml"
trap - EXIT
rm -rf "$work"
echo "publish_rust: done"
