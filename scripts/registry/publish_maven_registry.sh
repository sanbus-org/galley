#!/bin/bash
# Publishes dev jars plus Maven metadata to the R2-hosted static Maven
# repository. One immutable push, same shape every run (mirrors
# publish_python_registry.sh for the PEP 503 index):
#
#   1. read the jar in <dist-dir> (the package job built it from one run
#      version; anything else fails loud) and its coordinates from the
#      embedded META-INF/maven/**/pom.properties (filenames are never
#      parsed),
#   2. fetch the current maven-metadata.xml from the registry (absent is
#      fine; any other fetch failure is fatal, so a blind run can never
#      reset history) and list the hosted files under the artifact dir
#      for age pruning (a listing failure is fatal for the same reason),
#   3. merge and prune in scripts/registry/build_maven_registry.py,
#   4. upload new files, then changed metadata, then delete pruned
#      files — in that order, so readers never see dangling references.
#
# Versions already listed keep their files untouched (files are never
# re-uploaded: served bytes stay bit-identical forever), and unchanged
# metadata is not re-uploaded, so retries and no-op pushes are quiet.
# Pruning keeps the newest KEEP_DEV_VERSIONS dev versions and drops
# hosted dev versions older than DEV_TTL_HOURS, so the metadata stops
# advertising pruned versions.
# No bucket lifecycle rule: pruning happens in the builder on every push,
# and a prefix-scoped expiry would also delete the mutable
# maven-metadata.xml and reset history after any push pause.
#
# Auth is S3 API keys (CI secrets); the endpoint derives from the
# account id. Reads are anonymous: consumers resolve with a plain
# <repository> pointing at /maven/.
#
# DRY_RUN=1/true/yes/y (any case, surrounding whitespace ignored):
# fetch and merge only, no uploads or deletes.
#
# Usage: ./scripts/registry/publish_maven_registry.sh <dist-dir>
set -euo pipefail

test $# = 1 || {
	echo "publish_maven_registry: usage: publish_maven_registry.sh <dist-dir>" >&2
	exit 2
}
DIST_DIR="$1"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KEEP_DEV_VERSIONS="${KEEP_DEV_VERSIONS:-20}"
DEV_TTL_HOURS="${DEV_TTL_HOURS:-48}"
DRY_RUN="${DRY_RUN:-0}"

for secret in R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_PACKAGES_BUCKET_NAME R2_PACKAGES_HOSTNAME; do
	test -n "${!secret:-}" || {
		echo "publish_maven_registry: $secret is unset" >&2
		exit 1
	}
done
for tool in aws python3 curl; do
	command -v "$tool" >/dev/null || {
		echo "publish_maven_registry: $tool is not installed" >&2
		exit 1
	}
done
test -d "$DIST_DIR" || {
	echo "publish_maven_registry: no such dir: $DIST_DIR" >&2
	exit 1
}
test -n "$(ls -A "$DIST_DIR")" || {
	echo "publish_maven_registry: no jars in $DIST_DIR" >&2
	exit 1
}

ENDPOINT="https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com"
# Host may carry an explicit scheme (plain http only ever happens in
# local tests against a loopback fixture server).
with_scheme() {
	case "$1" in
	http://* | https://*) printf '%s' "$1" ;;
	*) printf 'https://%s' "$1" ;;
	esac
}
HOST="$(with_scheme "$R2_PACKAGES_HOSTNAME")"
HOST="${HOST%/}"
NOW="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"

# Fetch a registry document: 200 stores it, 404 means absent (fine),
# anything else fails loud — a blind merge must never reset history.
fetch() {
	url="$1"
	dest="$2"
	code="$(curl -s --max-time 60 -o "$dest" -w '%{http_code}' "$url")" || {
		echo "publish_maven_registry: fetch failed: $url" >&2
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
		echo "publish_maven_registry: unexpected HTTP $code for $url" >&2
		return 1
		;;
	esac
}

# Coordinates come from the builder's --print-coordinates mode (the single
# jar reader); the layout below derives from them, so nothing here
# hardcodes the group or artifact.
coords="$(
	python3 "$ROOT/scripts/registry/build_maven_registry.py" --dist-dir "$DIST_DIR" --print-coordinates
)" || exit 1
read -r GROUP_PATH ARTIFACT VERSION <<EOF
$coords
EOF
test -n "${GROUP_PATH:-}" -a -n "${ARTIFACT:-}" -a -n "${VERSION:-}" || {
	echo "publish_maven_registry: cannot read coordinates from $DIST_DIR" >&2
	exit 1
}
ARTIFACT_DIR="maven/$GROUP_PATH/$ARTIFACT"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/out"
builder_args=()
metadata_status=0
fetch "$HOST/$ARTIFACT_DIR/maven-metadata.xml" "$work/base-metadata.xml" || metadata_status=$?
case "$metadata_status" in
0) builder_args+=(--base-metadata "$work/base-metadata.xml") ;;
2) ;;
*) exit 1 ;;
esac
# Hosted files under the artifact dir date every listed version for the
# age prune; an empty bucket lists nothing (fine on the first push), but
# any listing failure is fatal, so a blind merge can never reset history.
listing="$work/listing.json"
aws s3api list-objects-v2 --bucket "$R2_PACKAGES_BUCKET_NAME" \
	--prefix "$ARTIFACT_DIR/" --endpoint-url "$ENDPOINT" \
	--output json >"$listing" || {
	echo "publish_maven_registry: bucket listing failed for $ARTIFACT_DIR/" >&2
	exit 1
}
python3 - "$listing" "$work/hosted.json" <<'EOF'
import json, sys
listing = json.load(open(sys.argv[1]))
hosted = [{"key": item["Key"], "last_modified": item.get("LastModified", "")}
          for item in listing.get("Contents", []) if item.get("Key")]
json.dump(hosted, open(sys.argv[2], "w"), indent=2)
EOF
builder_args+=(--hosted "$work/hosted.json")

python3 "$ROOT/scripts/registry/build_maven_registry.py" \
	--dist-dir "$DIST_DIR" --out-dir "$work/out" \
	--now "$NOW" --keep "$KEEP_DEV_VERSIONS" \
	--max-age-hours "$DEV_TTL_HOURS" \
	"${builder_args[@]}"

plan="$work/out/plan.json"
dry_source="$(printf '%s' "$DRY_RUN" | tr -d '[:space:]')"
case "$dry_source" in
1 | [Tt][Rr][Uu][Ee] | [Yy][Ee][Ss] | [Yy]) dry_run=1 ;;
*) dry_run=0 ;;
esac
if [ "$dry_run" = 1 ]; then
	echo "publish_maven_registry: dry run, no uploads or deletes"
	python3 -c '
import json,sys
plan = json.load(open(sys.argv[1]))
for upload in plan["uploads"]:
    f, k, c, cc = upload["file"], upload["key"], upload["content_type"], upload["cache_control"]
    print(f"would upload {f} -> {k} ({c}, {cc})")
for key in plan["deletes"]:
    print(f"would delete {key}")
for name, notes in plan["packages"].items():
    v, new, pruned = notes["version"], notes["new"], notes["pruned"]
    print(f"{name}: version {v} (new: {new}), pruned {pruned}")
' "$plan"
	exit 0
fi
# Exact keys only: s3api put-object writes the key verbatim (trailing
# slashes included), where s3 cp would treat them as prefixes.
python3 -c '
import json,sys,subprocess
plan = json.load(open(sys.argv[1]))
bucket, endpoint = sys.argv[2], sys.argv[3]
for upload in plan["uploads"]:
    f, k, c, cc = upload["file"], upload["key"], upload["content_type"], upload["cache_control"]
    subprocess.run(["aws", "s3api", "put-object", "--bucket", bucket, "--key", k,
                    "--body", f, "--endpoint-url", endpoint,
                    "--content-type", c, "--cache-control", cc],
                   check=True)
for key in plan["deletes"]:
    if not key.startswith("maven/"):
        raise SystemExit(f"refusing to delete non-file key {key!r}")
    subprocess.run(["aws", "s3api", "delete-object", "--bucket", bucket, "--key", key,
                    "--endpoint-url", endpoint],
                   check=True)
n_up, n_del = len(plan["uploads"]), len(plan["deletes"])
print(f"publish_maven_registry: {n_up} uploads, {n_del} deletes")
' "$plan" "$R2_PACKAGES_BUCKET_NAME" "$ENDPOINT"
trap - EXIT
rm -rf "$work"
echo "publish_maven_registry: done"
