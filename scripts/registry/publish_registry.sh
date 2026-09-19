#!/bin/bash
# Publishes dev tarballs plus merged packuments to the R2-hosted static
# npm registry. One immutable push, same shape every run:
#
#   1. read every tarball in <tgz-dir> (the package job built them all
#      from one run version; mixed versions fail loud),
#   2. fetch each packument's current form from the registry (absent is
#      fine) and its stable versions from npmjs (absent is fine for new
#      packages; any other fetch failure is fatal, so a blind run can
#      never reset history or mistag `latest`),
#   3. merge, tag, and prune in scripts/registry/build_registry.py,
#   4. upload new tarballs, then changed packuments, then delete pruned
#      tarballs — in that order, so readers never see dangling references.
#
# Versions already listed keep their entries untouched (tarballs are never
# re-uploaded: served bytes stay bit-identical forever), and unchanged
# packuments are not re-uploaded, so retries and no-op pushes are quiet.
# Pruning keeps the newest KEEP_DEV_VERSIONS dev versions per package and
# drops hosted dev versions older than DEV_TTL_HOURS, so the packument
# stops advertising versions the bucket lifecycle already deleted.
# One-time bucket setup (needs a Workers R2 Storage Write token, not the
# CI object-scoped keys — managing lifecycles is a bucket-level action):
#   npx wrangler r2 bucket lifecycle add "$R2_PACKAGES_BUCKET_NAME" \
#     expire-dev-tarballs tarballs/ --expire-days 2
#
# Auth is S3 API keys (CI secrets); the endpoint derives from the
# account id. Reads are anonymous: consumers install with a plain .npmrc
# scope mapping.
#
# DRY_RUN=1/true/yes/y (any case, surrounding whitespace ignored):
# fetch and merge only, no uploads or deletes.
#
# Usage: ./scripts/registry/publish_registry.sh <tgz-dir>
set -euo pipefail

test $# = 1 || {
	echo "publish_registry: usage: publish_registry.sh <tgz-dir>" >&2
	exit 2
}
TGZ_DIR="$1"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NPMJS_REGISTRY="${NPMJS_REGISTRY:-https://registry.npmjs.org}"
KEEP_DEV_VERSIONS="${KEEP_DEV_VERSIONS:-20}"
DEV_TTL_HOURS="${DEV_TTL_HOURS:-48}"
DRY_RUN="${DRY_RUN:-0}"

for secret in R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_PACKAGES_BUCKET_NAME R2_PACKAGES_HOSTNAME; do
	test -n "${!secret:-}" || {
		echo "publish_registry: $secret is unset" >&2
		exit 1
	}
done
for tool in aws python3 curl tar; do
	command -v "$tool" >/dev/null || {
		echo "publish_registry: $tool is not installed" >&2
		exit 1
	}
done
test -d "$TGZ_DIR" || {
	echo "publish_registry: no such dir: $TGZ_DIR" >&2
	exit 1
}
test -n "$(ls -A "$TGZ_DIR")" || {
	echo "publish_registry: no tarballs in $TGZ_DIR" >&2
	exit 1
}

ENDPOINT="https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com"
# Host and registry may carry an explicit scheme (plain http only ever
# happens in local tests against a loopback fixture server).
with_scheme() {
	case "$1" in
	http://* | https://*) printf '%s' "$1" ;;
	*) printf 'https://%s' "$1" ;;
	esac
}
HOST="$(with_scheme "$R2_PACKAGES_HOSTNAME")"
HOST="${HOST%/}"
NPMJS_REGISTRY="$(with_scheme "$NPMJS_REGISTRY")"
# Origin only, no path prefix: tarball URLs append /tarballs/..., and the
# delete guard only ever allows keys under tarballs/.
TARBALL_BASE_URL="$HOST"
NOW="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"

# Fetch a registry document: 200 stores it, 404 means absent (fine),
# anything else fails loud — a blind merge must never reset history.
fetch() {
	url="$1"
	dest="$2"
	code="$(curl -s --max-time 60 -o "$dest" -w '%{http_code}' "$url")" || {
		echo "publish_registry: fetch failed: $url" >&2
		return 1
	}
	case "$code" in
	200) return 0 ;;
	404)
		rm -f "$dest"
		return 2
		;;
	*)
		rm -f "$dest"
		echo "publish_registry: unexpected HTTP $code for $url" >&2
		return 1
		;;
	esac
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/base" "$work/npmjs" "$work/out"
specs="$work/packages.json"
printf '[' >"$specs"
first=1
index=0
for tgz in "$TGZ_DIR"/*.tgz; do
	test -f "$tgz" || {
		echo "publish_registry: no tarballs in $TGZ_DIR" >&2
		exit 1
	}
	name="$(tar -xzOf "$tgz" package/package.json | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])')"
	# The packument key forms live here with the fetch logic, next to
	# the dual upload in build_registry.py: the literal slash form npm
	# also requests, plus the encoded form, so either S3 %2F behavior
	# resolves. Reading the encoded form suffices because every publish
	# writes both forms identically.
	encoded="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$name")"
	base_file="$work/base/$index.json"
	status=0
	fetch "$TARBALL_BASE_URL/$encoded" "$base_file" || status=$?
	case "$status" in
	0) base_json="\"$base_file\"" ;;
	2) base_json=null ;;
	*)
		exit 1
		;;
	esac
	npmjs_file="$work/npmjs/$index.json"
	status=0
	fetch "$NPMJS_REGISTRY/$encoded" "$npmjs_file" || status=$?
	case "$status" in
	0) npmjs_json="\"$npmjs_file\"" ;;
	2) npmjs_json=null ;;
	*)
		exit 1
		;;
	esac
	if [ "$first" = 1 ]; then first=0; else printf ',' >>"$specs"; fi
	printf '{"name":%s,"tgz":%s,"base":%s,"npmjs":%s}' \
		"$(printf '%s' "$name" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
		"$(printf '%s' "$tgz" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
		"$base_json" "$npmjs_json" >>"$specs"
	index=$((index + 1))
done
printf ']' >>"$specs"

python3 "$ROOT/scripts/registry/build_registry.py" \
	--tgz-dir "$TGZ_DIR" --packages "$specs" --out-dir "$work/out" \
	--tarball-base-url "$TARBALL_BASE_URL" --now "$NOW" --keep "$KEEP_DEV_VERSIONS" \
	--max-age-hours "$DEV_TTL_HOURS"

plan="$work/out/plan.json"
dry_source="$(printf '%s' "$DRY_RUN" | tr -d '[:space:]')"
case "$dry_source" in
1 | [Tt][Rr][Uu][Ee] | [Yy][Ee][Ss] | [Yy]) dry_run=1 ;;
*) dry_run=0 ;;
esac
if [ "$dry_run" = 1 ]; then
	echo "publish_registry: dry run, no uploads or deletes"
	python3 -c '
import json,sys
plan = json.load(open(sys.argv[1]))
for upload in plan["uploads"]:
    f, k, c, cc = upload["file"], upload["key"], upload["content_type"], upload["cache_control"]
    print(f"would upload {f} -> {k} ({c}, {cc})")
for key in plan["deletes"]:
    print(f"would delete {key}")
for name, notes in plan["packages"].items():
    v, new, tags, pruned = notes["version"], notes["new"], notes["tags"], notes["pruned"]
    print(f"{name}: version {v} (new: {new}), tags {tags}, pruned {pruned}")
' "$plan"
	exit 0
fi
python3 -c '
import json,sys,subprocess
plan = json.load(open(sys.argv[1]))
bucket, endpoint = sys.argv[2], sys.argv[3]
for upload in plan["uploads"]:
    f, k, c, cc = upload["file"], upload["key"], upload["content_type"], upload["cache_control"]
    subprocess.run(["aws", "s3", "cp", f, f"s3://{bucket}/{k}",
                    "--endpoint-url", endpoint, "--content-type", c,
                    "--cache-control", cc],
                   check=True)
for key in plan["deletes"]:
    subprocess.run(["aws", "s3", "rm", f"s3://{bucket}/{key}", "--endpoint-url", endpoint],
                   check=True)
n_up, n_del = len(plan["uploads"]), len(plan["deletes"])
print(f"publish_registry: {n_up} uploads, {n_del} deletes")
' "$plan" "$R2_PACKAGES_BUCKET_NAME" "$ENDPOINT"
trap - EXIT
rm -rf "$work"
echo "publish_registry: done"
