#!/bin/bash
# Deploys a prebuilt Galley Java jar (see scripts/java/build_jar.sh) to
# GitHub Packages Maven. This is the dev channel: every main push deploys
# the VERSION-SNAPSHOT stream, overwriting the previous one, so no version
# bookkeeping is needed and no per-push versions accumulate.
#
# No pom changes are required: maven-deploy-plugin's deploy-file goal
# takes group/artifact/version on the command line, and GitHub Packages
# accepts any groupId. Auth is GITHUB_TOKEN (the workflow needs
# `packages: write`); no OSSRH/GPG secrets involved.
#
# First deploy lands private; flip the package to public once in the
# Packages UI so storage stays free (public packages are unbilled).
# Installs require authentication either way.
#
# Usage: ./scripts/java/deploy_github.sh <jar> <version>
set -euo pipefail

test $# = 2 || {
	echo "deploy_github: usage: deploy_github.sh <jar> <version>" >&2
	exit 2
}
JAR="$1"
VERSION="$2"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test -f "$JAR" || {
	echo "deploy_github: no such jar: $JAR" >&2
	exit 1
}
# Group and artifact come from the module pom, never from flags, so a
# rename in one place cannot silently deploy elsewhere.
read GROUP ARTIFACT <<<"$(python3 - "$ROOT/bindings/java/pom.xml" <<'EOF'
import sys
import xml.etree.ElementTree as ET
namespace = "{http://maven.apache.org/POM/4.0.0}"
root = ET.parse(sys.argv[1]).getroot()
print(root.find(f"{namespace}groupId").text, root.find(f"{namespace}artifactId").text)
EOF
)"
test "$GROUP" = "com.sassanh.sanbus" || {
	echo "deploy_github: unexpected groupId $GROUP" >&2
	exit 1
}
test "$ARTIFACT" = "galley" || {
	echo "deploy_github: unexpected artifactId $ARTIFACT" >&2
	exit 1
}
# The jar name is deterministic (artifactId-version.jar); pin it so a
# second attached jar (sources, javadoc, future plugin output) fails
# here instead of shifting the positional arguments.
test "$(basename "$JAR")" = "$ARTIFACT-$VERSION.jar" || {
	echo "deploy_github: expected $ARTIFACT-$VERSION.jar, got $JAR" >&2
	exit 1
}
test -n "${GITHUB_TOKEN:-}" || {
	echo "deploy_github: GITHUB_TOKEN is unset" >&2
	exit 1
}
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat >"$work/settings.xml" <<EOF
<settings>
  <servers>
    <server>
      <id>github</id>
      <username>\${env.GITHUB_ACTOR}</username>
      <password>\${env.GITHUB_TOKEN}</password>
    </server>
  </servers>
</settings>
EOF
echo "deploy_github: deploying $ARTIFACT@$VERSION"
mvn -B --settings "$work/settings.xml" \
	org.apache.maven.plugins:maven-deploy-plugin:3.1.2:deploy-file \
	"-Dfile=$JAR" "-DgroupId=$GROUP" "-DartifactId=$ARTIFACT" \
	"-Dversion=$VERSION" -Dpackaging=jar \
	-DrepositoryId=github -Durl=https://maven.pkg.github.com/sanbus-org/galley
trap - EXIT
rm -rf "$work"
echo "deploy_github: done"
