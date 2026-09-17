#!/bin/bash
# Publishes staged JavaScript packages — tarballs or directories — to the
# npm registry.
#
#   NPM_REGISTRY (required): https://registry.npmjs.org.
#   NPM_TAG: `auto` derives the tag from the prerelease (`0.2.0-beta.1`
#     publishes under --tag beta, stable releases keep npm's default
#     latest tag); any other non-empty value is used verbatim; empty
#     omits --tag.
#   NPM_PROVENANCE=auto|0: `auto` adds --provenance under OIDC (npmjs
#     trusted publishing).
#   NPM_ACCESS: passed as --access when non-empty (`public` for npmjs
#     first publishes).
#
# Idempotent: any name@version already on the registry is skipped, so
# re-runs (retries, duplicate events) are green. Directories publish
# as-is (provenance-compatible); tarballs publish as files. Auth comes
# from the npm config in the environment (CI: setup-node, OIDC).
#
# Usage: ./scripts/js/publish_tgz.sh <tarball-or-dir>...
set -euo pipefail

test $# -ge 1 || {
	echo "publish_tgz: usage: publish_tgz.sh <tarball-or-dir>..." >&2
	exit 2
}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${NPM_REGISTRY:?publish_tgz: set NPM_REGISTRY}"
NPM_TAG="${NPM_TAG:-}"
NPM_PROVENANCE="${NPM_PROVENANCE:-0}"
NPM_ACCESS="${NPM_ACCESS:-}"

# Suffix publish order. Keep in sync with scripts/js/pack_js.sh.
ORDER="galley-core galley-node galley-bun galley-deno galley-wasm galley galley-cli-darwin-arm64 galley-cli-darwin-x64 galley-cli-linux-x64 galley-cli-linux-arm64 galley-cli-win32-x64 galley-cli-win32-arm64"

INDEX="$(mktemp)"
trap 'rm -f "$INDEX"' EXIT

manifest_of() {
	if [ -d "$1" ]; then
		node -p "const m = require(process.argv[1] + '/package.json'); m.name + ' ' + m.version" -- "$1"
	else
		tar -xzOf "$1" package/package.json | node -p "const m = JSON.parse(require('fs').readFileSync(0, 'utf8')); m.name + ' ' + m.version"
	fi
}

publish_one() {
	src="$1"
	name="$2"
	version="$3"
	if npm view "$name@$version" version --registry="$NPM_REGISTRY" >/dev/null 2>&1; then
		echo "publish_tgz: skip $name@$version (already on the registry)"
		return 0
	fi
	echo "publish_tgz: publishing $name@$version"
	# Intentionally word-split: flags never contain spaces.
	# shellcheck disable=SC2086
	publish_flags="--registry=$NPM_REGISTRY --ignore-scripts"
	case "$NPM_TAG" in
	"") ;;
	auto)
		# Prereleases must never become latest: 0.2.0-beta.1 publishes
		# under --tag beta (suffix up to the first dot), stable releases
		# keep npm's default latest tag.
		case "$version" in
		*-*)
			prerelease="${version#*-}"
			publish_flags="$publish_flags --tag ${prerelease%%.*}"
			;;
		esac
		;;
	*) publish_flags="$publish_flags --tag $NPM_TAG" ;;
	esac
	if [ "$NPM_PROVENANCE" = auto ] && [ -n "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]; then
		publish_flags="$publish_flags --provenance"
	fi
	if [ -n "$NPM_ACCESS" ]; then
		publish_flags="$publish_flags --access $NPM_ACCESS"
	fi
	# shellcheck disable=SC2086
	npm publish "$src" $publish_flags
}

# The headline package URL for the job's environment link: the universal
# package (suffix `galley`). Emitted as a step output after the loop.
# Publishing never depends on it.
resolve_url() {
	printf '%s\n' "https://www.npmjs.com/package/$1/v/$2"
}

for src in "$@"; do
	manifest="$(manifest_of "$src")"
	read name version <<<"$manifest"
	suffix="${name##*/}"
	printf '%s\t%s\t%s\t%s\n' "$suffix" "$name" "$version" "$src" >>"$INDEX"
done

# Publish in dependency order (core first, universal last, CLI packages
# after everything that could resolve them): a run that dies halfway
# leaves published dependents pointing at published dependencies, and
# the idempotent skip makes the retry a no-op for what landed. Keep in
# sync with scripts/js/pack_js.sh. Inputs outside the known set still
# publish, in argument order, so a new package can never silently skip.
while IFS="$(printf '\t')" read -r suffix name version src; do
	publish_one "$src" "$name" "$version"
	if [ "$suffix" = "galley" ]; then
		HEADLINE_URL="$(resolve_url "$name" "$version")"
	fi
done < <(
	for key in $ORDER; do
		awk -F'\t' -v key="$key" '$1 == key' "$INDEX"
	done
	awk -F'\t' -v order=" $ORDER " 'index(order, " " $1 " ") == 0' "$INDEX"
)
if [ -n "${GITHUB_OUTPUT:-}" ] && [ -n "${HEADLINE_URL:-}" ]; then
	printf 'headline_url=%s\n' "$HEADLINE_URL" >>"$GITHUB_OUTPUT"
fi
trap - EXIT
rm -f "$INDEX"
echo "publish_tgz: done"
