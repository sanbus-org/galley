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
# PACKAGE_VERSION overrides the root VERSION file (the CI package job sets
# it to the run version: dev versions on pushes, product version on tags).
# Local bootstrapping stays on the product version by default.
#
# ASSEMBLE_ONLY_DIR=<dir>: stage, pin, and `cargo package` exactly as for
# a publish, copy the .crate there, exit before touching the registry.
# Needs no token. The CI package job uses this on every run.
#
# PREBUILT_CRATE=<file>: skip staging; unpack the .crate produced by an
# ASSEMBLE_ONLY_DIR run of this same script and publish its exact files
# from there (cargo publish re-packages, so contents are identical even
# though tarball bytes may differ), so tag releases upload what the
# package job built instead of rebuilding.
#
# Run (CI publish-rust job does this after the test gate is green):
#   ./scripts/rust/publish_rust.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CRATE_DIR="$ROOT/bindings/rust"
VERSION="${PACKAGE_VERSION:-"$(python3 "$ROOT/scripts/product_version.py")"}"

name="$(sed -n 's/^name = "\(.*\)"/\1/p' "$CRATE_DIR/Cargo.toml" | head -n 1)"
test "$name" = "galley" || {
	echo "publish_rust: unexpected crate name $name" >&2
	exit 1
}
if curl -fsSL -H "User-Agent: galley-publish (https://github.com/sanbus-org/galley)" "https://crates.io/api/v1/crates/$name/$VERSION" >/dev/null 2>&1; then
	echo "publish_rust: skip $name@$VERSION (already on the registry)"
	exit 0
fi
# The token is only required for a real publish; assemble-only runs (the
# CI package job) stay green without it, as do pure skip runs above.
if [ -z "${ASSEMBLE_ONLY_DIR:-}" ]; then
	test -n "${CARGO_REGISTRY_TOKEN:-}" || {
		echo "publish_rust: $name@$VERSION is new but CARGO_REGISTRY_TOKEN is unset" >&2
		exit 1
	}
fi
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
if [ -n "${ASSEMBLE_ONLY_DIR:-}" ] && [ -n "${PREBUILT_CRATE:-}" ]; then
	echo "publish_rust: ASSEMBLE_ONLY_DIR and PREBUILT_CRATE are mutually exclusive" >&2
	exit 1
fi
CRATE_MANIFEST="$work/Cargo.toml"
if [ -n "${PREBUILT_CRATE:-}" ]; then
	# The caller may pass an unexpanded glob (env values arrive quoted);
	# resolve it here so the match is exact-or-loud either way.
	# shellcheck disable=SC2086
	resolved="$(printf '%s\n' $PREBUILT_CRATE)"
	test "$(printf '%s\n' "$resolved" | wc -l)" -eq 1 || {
		echo "publish_rust: expected exactly one .crate in $PREBUILT_CRATE" >&2
		exit 1
	}
	PREBUILT_CRATE="$resolved"
	case "$PREBUILT_CRATE" in
	*.crate) ;;
	*)
		echo "publish_rust: not a .crate file: $PREBUILT_CRATE" >&2
		exit 1
		;;
	esac
	tar -xzf "$PREBUILT_CRATE" -C "$work"
	matches="$(printf '%s\n' "$work"/galley-*/Cargo.toml)"
	test "$(printf '%s\n' "$matches" | wc -l)" -eq 1 || {
		echo "publish_rust: expected one crate dir in $PREBUILT_CRATE" >&2
		exit 1
	}
	# Cargo.toml.orig travels inside .crate archives as the pre-normalized
	# manifest, but cargo publish rejects it as a reserved filename when
	# publishing from a directory. The normalized Cargo.toml stays.
	rm -f "$(dirname "$matches")/Cargo.toml.orig"
	CRATE_MANIFEST="$matches"
	staged_version="$(sed -n 's/^version = "\(.*\)"/\1/p' "$CRATE_MANIFEST" | head -n 1)"
	test "$staged_version" = "$VERSION" || {
		echo "publish_rust: $PREBUILT_CRATE carries $staged_version, expected $VERSION" >&2
		exit 1
	}
else
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
grep -qxF "version = \"$VERSION\"" "$work/Cargo.toml" || {
	echo "publish_rust: version pin failed" >&2
	exit 1
}
fi
if [ -n "${ASSEMBLE_ONLY_DIR:-}" ]; then
	echo "publish_rust: packaging $name@$VERSION"
	(cd "$work" && cargo package) >/dev/null
	mkdir -p "$ASSEMBLE_ONLY_DIR"
	cp "$work"/target/package/*.crate "$ASSEMBLE_ONLY_DIR/"
else
	echo "publish_rust: publishing $name@$VERSION"
	cargo publish --manifest-path "$CRATE_MANIFEST"
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		printf 'headline_url=%s\n' "https://crates.io/crates/$name/$VERSION" >>"$GITHUB_OUTPUT"
	fi
fi
trap - EXIT
rm -rf "$work"
echo "publish_rust: done"
