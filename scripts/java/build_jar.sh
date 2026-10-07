#!/bin/bash
# Builds the Galley Java jar from a temp copy whose pom version is pinned
# to the requested version. Repo files are never touched.
#
# The jar is the CI package artifact: uploaded on every run, published
# to Maven Central on tags (scripts/java/publish_java.sh, which keeps its
# own sources/javadoc/signing flow).
#
# Usage: ./scripts/java/build_jar.sh <dest-dir> <version>
set -euo pipefail

test $# = 2 || {
	echo "build_jar: usage: build_jar.sh <dest-dir> <version>" >&2
	exit 2
}
DEST="$1"
VERSION="$2"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODULE_DIR="$ROOT/bindings/java"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# Copy the module without build trees; snapshots must not leak in.
tar --exclude='./target' --exclude='./out' -cf - -C "$MODULE_DIR" . | tar -xf - -C "$work"
# The requested version is the single source of truth here: pin the
# top-level project version only, never plugin or dependency versions.
python3 "$ROOT/scripts/java/pin_pom.py" "$work/pom.xml" "$VERSION"
grep -qF "<version>$VERSION</version>" "$work/pom.xml" || {
	echo "build_jar: version pin failed" >&2
	exit 1
}
echo "build_jar: building galley@$VERSION"
cd "$work"
# The jar needs no tests, and the test sources reference generated fixture
# classes that a fresh checkout does not have, so skip compiling them too.
log="$work/mvn.log"
mvn -B -Dmaven.test.skip=true package >"$log" 2>&1 || {
	cat "$log" >&2
	exit 1
}
mkdir -p "$DEST"
cp "$work"/target/*.jar "$DEST/"
trap - EXIT
rm -rf "$work"
echo "build_jar: done"
