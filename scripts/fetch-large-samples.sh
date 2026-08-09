#!/usr/bin/env bash
#
# Fetch large language sample fixtures that are too big to live in git.
#
# The fixtures are hosted as GitHub Release assets instead of git-lfs, which
# exceeded the repository's LFS budget and broke every CI checkout. Each file
# is verified against a pinned sha256 before it is installed.
#
# Usage:
#   scripts/fetch-large-samples.sh                 # fetch every fixture
#   scripts/fetch-large-samples.sh json           # fetch only json fixtures
#   scripts/fetch-large-samples.sh json-augmented
#
# Set GALLEY_SAMPLES_BASE_URL to override the download origin (useful for
# testing or mirrors).
set -euo pipefail

REPO="sanbus-org/galley"
RELEASE_TAG="large-samples-v1"
DEFAULT_BASE_URL="https://github.com/${REPO}/releases/download/${RELEASE_TAG}"
BASE_URL="${GALLEY_SAMPLES_BASE_URL:-${DEFAULT_BASE_URL}}"

if command -v sha256sum >/dev/null 2>&1; then
	sha256() { sha256sum "$@"; }
else
	sha256() { shasum -a 256 "$@"; }
fi

# language|target_path|asset_name|sha256
FIXTURES="$(
	cat <<'EOF'
json|languages/json/samples/code-02.json|code-02.json|d63d0f62110ec5d534d586a910afee58160d4b8058a3996598364026bf1df9a4
json-recovery|languages/json/samples/code-02.json|code-02.json|d63d0f62110ec5d534d586a910afee58160d4b8058a3996598364026bf1df9a4
json-structured-ast|languages/json/samples/code-02.json|code-02.json|d63d0f62110ec5d534d586a910afee58160d4b8058a3996598364026bf1df9a4
json-augmented|languages/json/samples/code-02.json|code-02.json|d63d0f62110ec5d534d586a910afee58160d4b8058a3996598364026bf1df9a4
json-augmented|languages/json-augmented/samples/code-02-recursive-stress.json|code-02-recursive-stress.json|d21579bf21d98e5d0be100425acd389b6425446a4fc6e2a1bdff318d0e8c10e6
EOF
)"

language="${1:-}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fetched=0
checked=0

while IFS='|' read -r entry_lang target asset sha; do
	if [[ -n "$language" && "$entry_lang" != "$language" ]]; then
		continue
	fi
	checked=$((checked + 1))
	path="${repo_root}/${target}"
	if [[ -f "$path" ]] && printf '%s  %s\n' "$sha" "$path" | sha256 -c - >/dev/null 2>&1; then
		echo "sample present: ${target}"
		continue
	fi
	tmp="$(mktemp "${path}.XXXXXX")"
	trap 'rm -f "$tmp"' EXIT
	echo "fetching ${asset} -> ${target}"
	curl -fL --retry 3 "${BASE_URL}/${asset}" -o "$tmp"
	printf '%s  %s\n' "$sha" "$tmp" | sha256 -c - >/dev/null
	mkdir -p "$(dirname "$path")"
	mv "$tmp" "$path"
	tmp=""
	fetched=$((fetched + 1))
done <<<"${FIXTURES}"

if [[ "$checked" -eq 0 ]]; then
	echo "no large sample fixtures for language '${language}'"
fi
echo "fetched ${fetched}, verified ${checked} sample fixture(s)"
