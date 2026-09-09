#!/bin/bash
# Publishes the Galley Java artifact to Maven Central.
#
# Idempotent: a VERSION already on Central is skipped, so re-runs are
# green. The artifact is deployed from a temp copy whose pom version is
# pinned to the root VERSION file. Repo files are never touched.
#
# Auth is a central.sonatype.com user token plus a GPG signing key
# (one-time setup: claim the com.sassanh.sanbus namespace, create a token,
# store OSSRH_USERNAME/OSSRH_TOKEN, an armored GPG_PRIVATE_KEY, and
# GPG_PASSPHRASE as CI secrets). All four are only required when a publish
# is actually needed; pure skip runs stay green without them.
#
# Run (CI publish-java job does this after the test gate is green):
#   ./scripts/java/publish_java.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODULE_DIR="$ROOT/bindings/java"
VERSION="$(python3 "$ROOT/scripts/product_version.py")"

group_path="com/sassanh/sanbus"
artifact="galley"
if curl -fsSL "https://repo1.maven.org/maven2/$group_path/$artifact/$VERSION/$artifact-$VERSION.pom" >/dev/null 2>&1; then
	echo "publish_java: skip $artifact@$VERSION (already on the registry)"
	exit 0
fi
for secret in OSSRH_USERNAME OSSRH_TOKEN GPG_PRIVATE_KEY GPG_PASSPHRASE; do
	test -n "${!secret:-}" || {
		echo "publish_java: $artifact@$VERSION is new but $secret is unset" >&2
		exit 1
	}
done
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# Copy the module without the build tree; snapshots must not leak in.
tar --exclude='./target' -cf - -C "$MODULE_DIR" . | tar -xf - -C "$work"
# The root VERSION file is the single source of truth for the version too,
# not just the skip check above: pin the top-level project version only,
# never plugin or dependency versions.
python3 - "$work/pom.xml" "$VERSION" <<'EOF'
import sys
import xml.etree.ElementTree as ET
path, version = sys.argv[1], sys.argv[2]
namespace = "{http://maven.apache.org/POM/4.0.0}"
ET.register_namespace("", "http://maven.apache.org/POM/4.0.0")
tree = ET.parse(path)
root = tree.getroot()
element = root.find(f"{namespace}version")
assert element is not None
element.text = version
tree.write(path, encoding="utf-8", xml_declaration=True)
EOF
grep -q "<version>$VERSION</version>" "$work/pom.xml" || {
	echo "publish_java: version pin failed" >&2
	exit 1
}
cat >"$work/settings.xml" <<EOF
<settings>
  <servers>
    <server>
      <id>central</id>
      <username>$OSSRH_USERNAME</username>
      <password>$OSSRH_TOKEN</password>
    </server>
  </servers>
</settings>
EOF
export GNUPGHOME="$work/gnupg"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"
echo "$GPG_PRIVATE_KEY" | gpg --batch --import 2>/dev/null
echo "publish_java: publishing $artifact@$VERSION"
cd "$work"
mvn --settings "$work/settings.xml" -P central -DskipTests "-Dgpg.passphrase=$GPG_PASSPHRASE" deploy
trap - EXIT
rm -rf "$work"
echo "publish_java: done"
