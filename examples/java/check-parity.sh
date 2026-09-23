#!/bin/sh
# Byte-parity check: the Java demo transcript against the Python demo,
# comparing stdout and stderr as separate streams. Build first (see
# README.md): the kv grammar library plus the compiled demo classes.
set -eu
cd "$(dirname "$0")/../.."
case "$(uname -s)" in
Darwin) lib=libgalley-java.dylib ;;
*) lib=libgalley-java.so ;;
esac
for dir in bindings/java/out examples/java/out; do
	if [ ! -d "$dir" ]; then
		echo "check-parity: missing prebuilt dir $dir; build first (see README.md)" >&2
		exit 1
	fi
done
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
python3 examples/python/demo.py >"$work/python.out" 2>"$work/python.err"
GALLEY_LIBRARY_PATH="$PWD/examples/java/kv/$lib" \
	java --enable-native-access=ALL-UNNAMED -cp bindings/java/out:examples/java/out com.example.Demo \
	>"$work/java.out" 2>"$work/java.err"
diff -u "$work/python.out" "$work/java.out"
diff -u "$work/python.err" "$work/java.err"
echo "parity ok: demo stdout and stderr are byte-identical"
