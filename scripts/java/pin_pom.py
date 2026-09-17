#!/usr/bin/env python3
"""Pin the top-level project version of a pom.xml, nothing else.

Plugin and dependency versions are never touched. Used by the Java build
and publish scripts so the pin logic lives in exactly one place.

Run: python3 scripts/java/pin_pom.py <pom.xml> <version>
"""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET

NAMESPACE = "{http://maven.apache.org/POM/4.0.0}"


def main() -> None:
    if len(sys.argv) != 3:
        print("pin_pom: usage: pin_pom.py <pom.xml> <version>", file=sys.stderr)
        raise SystemExit(2)
    path, version = sys.argv[1], sys.argv[2]
    ET.register_namespace("", "http://maven.apache.org/POM/4.0.0")
    tree = ET.parse(path)
    root = tree.getroot()
    element = root.find(f"{NAMESPACE}version")
    if element is None:
        print(f"pin_pom: {path} has no top-level project version", file=sys.stderr)
        raise SystemExit(1)
    element.text = version
    tree.write(path, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    main()
