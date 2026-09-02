# Java

Galley-generated parsers can be consumed from Java through Panama FFI
(Java 22+): Galley compiles a generated parser into a shared library
(`lib<name>.dylib` / `.so`) together with the C header
[`bindings/c/galley.h`](https://github.com/sanbus-org/galley/blob/main/bindings/c/galley.h),
and the Java bindings (`java.lang.foreign`) wrap that API in a safe, typed
surface (sessions, node handles, structured diagnostics, tree editing) with
no third-party runtime.

The bindings live in
[`bindings/java`](https://github.com/sanbus-org/galley/tree/main/bindings/java).
A complete, runnable consumer lives in
[`examples/java`](https://github.com/sanbus-org/galley/tree/main/examples/java);
it is built and executed by CI on every push, byte-for-byte identical in
output to the Python, Go, Rust, and TypeScript examples.

## Getting Started

Requires `java` ≥ 22, `javac`, `zig` 0.16, and `git` (`GALLEY_CHECKOUT` skips `git`).

Build the bindings (no Maven, no JNA):

```sh
javac --release 22 -d bindings/java/out $(find bindings/java/src/main/java -name "*.java")
```

Then generate and build the shared library for your language directory (a
directory containing `ll.grm` and `config.zig`):

```sh
java --enable-native-access=ALL-UNNAMED -cp bindings/java/out org.sanbus.galley.build.GalleyBuild <language-dir>
```

The tool resolves Galley exactly like the other bindings:
`GALLEY_CHECKOUT` (existing working tree) wins over `GALLEY_REPOSITORY` +
`GALLEY_TAG` (default `main`); `ZIG_EXECUTABLE` selects zig. It generates
the parser (`--emit-metadata`), builds the shared library through
`bindings/c/consumer/build.zig`, detects optional hook files next to your
grammar (`procedures.java` for native Java hooks, `procedures.c` for legacy
C hooks, `ll_error_messages.zig`), and copies `libgalley-java.*` into the
language directory. Regenerate after changing the grammar; commit nothing it
generates. One library embeds one parser — split grammars across language
directories exactly like the other bindings.

Run the demo:

```sh
javac --release 22 -d bindings/java/out $(find bindings/java/src/main/java -name "*.java")
java --enable-native-access=ALL-UNNAMED -cp bindings/java/out org.sanbus.galley.build.GalleyBuild examples/java
javac --release 22 -cp bindings/java/out -d examples/java/out $(find examples/java/src/main/java -name "*.java")
java --enable-native-access=ALL-UNNAMED -cp bindings/java/out:examples/java/out com.example.Demo
# With file argument
java --enable-native-access=ALL-UNNAMED -cp bindings/java/out:examples/java/out com.example.Demo path/to/file
# Benchmark (no AST/procedures/recovery)
java --enable-native-access=ALL-UNNAMED -cp bindings/java/out org.sanbus.galley.build.GalleyBuild examples/java/benchmark
java --enable-native-access=ALL-UNNAMED -cp bindings/java/out:examples/java/out com.example.Benchmark
```

Library discovery order: `SessionOptions.libraryPath` (explicit) →
`GALLEY_LIBRARY_PATH` env → `galley.library.path` system property →
`<cwd>/libgalley-java.*` → `~/Library/Caches/galley-bindings/java/capi/lib/libgalley-java.*`
(macOS) or `~/.cache/galley-bindings/java/capi/lib/libgalley-java.*` (Linux).

## Performance Notes

The Panama FFI boundary is the only overhead over the C API:

- Every method is a direct `Linker.downcallHandle` / `MemorySegment` call; no JSON or subprocess marshalling. Sessions are not thread-safe — keep one per thread or guard it externally.
- Node handles are `Node` objects that wrap a stable address in the library's non-relocating node storage and keep a strong reference to their owning `Session`; plain `long` addresses are also accepted wherever a node is expected. Iteration and indexing are zero-copy (`for (Node child : session.children(root))`, `root.children()`, `node.length`).
- Text accessors (`text`, `symbolName`, diagnostic tokens) return `byte[]` copies with no UTF-8 decoding; decode on demand.
- `parse(byte[])` allocates a confined `Arena` per call (`arena.allocateFrom(ValueLayout.JAVA_BYTE, input)`) — no cached `Memory`; direct `ByteBuffer` is zero-copy via `MemorySegment.ofBuffer` (no allocation, no copy). Use `FileChannel` → `allocateDirect` → `flip()` → `rewind()` before each `parse` for benchmark-grade throughput, mirroring Go's `unsafe.Pointer(&input[0])`, Rust's `as_ptr()`, and Python's `PyBytes_AS_STRING`. Heap `ByteBuffer` copies via `Arena` like `byte[]`.
- `parse(String)` encodes to UTF-8 once per call (`String.getBytes(UTF_8)`). The session copies into its own storage so node text stays valid after return.

Node text, diagnostics, and expected-token data remain valid only until the next parse on the same session; every accessor copies before returning. `Node` methods check that their session is still open and throw after `session.close()`.

## Procedures

Set `pub const procedures = true;` in your grammar's `config.zig` and
implement the hooks in Java in a `procedures.java` file next to your grammar
— ordinary Java registered at runtime into the generated shim:

```java
// procedures.java
import org.sanbus.galley.*;

public final class procedures {
    public static void reduction_Pair(ProcedureArguments args) {
        Node node = args.currentNode();
        if (node == null) return;
        byte[] text = node.text();
        int[] pos = node.lineColumn();
        System.err.printf("Pair %s (%d children) at %d:%d%n",
            new String(text), node.length(), pos[0], pos[1]);
    }
    public static void reduction_KeyTail(ProcedureArguments args) {
        args.dropIfEmpty();
    }
    public static void hook_print(ProcedureArguments args) {
        Node node = args.currentNode();
        if (node == null) return;
        int[] pos = node.lineColumn();
        System.err.printf("@print \"%s\" at %d:%d%n",
            new String(node.text()), pos[0], pos[1]);
    }
    public static void register() {
        Procedures.installProcedure("reduction_Pair", procedures::reduction_Pair);
        Procedures.installProcedure("reduction_KeyTail", procedures::reduction_KeyTail);
        Procedures.installProcedure("hook_print", procedures::hook_print);
    }
}
```

Then register before parsing:

```java
procedures.register(); // or manually
Procedures.installProcedure("reduction_Pair", args -> {
    Node n = args.currentNode();
    System.err.println(new String(n.text()));
});
```

Mechanically, the build tool reads the grammar's generated hook list
(`procedures.zig`) and produces a Zig shim (`procedures_java.zig`)
containing one dispatch slot per hook; the JVM registers each Java hook
address into that single slot at `Procedures.installProcedure` time
(via JNA `galley_install_java_dispatch`). The parser calls through the slot
directly, so hook code executes in the host's JVM. Unregistered slots are
no-ops. Reduction hooks keep their `reduction_<VariableName>` names (plus
the general `reduction`); author-defined grammar hooks are declared as
`hook_<name>`. Semantic payloads are unavailable through bindings.

You can also bulk-register from a map or object:

```java
Map<String, Consumer<ProcedureArguments>> map = Map.of(
    "reduction_Pair", args -> {},
    "hook_print", args -> {}
);
Procedures.installProcedures(map);
Procedures.listProcedures(); // Map<String, Consumer>
Procedures.clearProcedures();
```

Legacy `procedures.c` / `procedures.cpp` hooks continue to work exactly like
the C/C++ consumers: the build compiles the C file into the shared library
when no `procedures.java` is present. If both Java and C files exist, Java
takes precedence and a warning is emitted.

## Error Messages

To replace messages with fixed strings — no Zig file at all — pass
`messageOverrides` in the session options. Keys are structured identities:
the innermost in-progress variable name (for example `"Number"`), or `"*"`
for every syntax and indentation error. Variable keys win over `"*"`, and
overrides take priority over hooks. Placeholders expand against the failing
diagnostic:

```java
SessionOptions opts = SessionOptions.builder()
    .messageOverride("Number", "expected a number after ':' (digits only) at line {line}")
    .build();
try (Session s = new Session(opts)) { ... }
// Or per-session:
s.setMessageOverride("Number", "expected a number after ':' (digits only) at line {line}");
```

Override messages may contain `{line}`, `{column}`, `{unexpected}`,
`{expected}`, and `{context}` placeholders, expanded against the failing
diagnostic. Run `galley --fill-error-messages <language-dir>` and edit the
generated `ll_error_messages.zig` next to your grammar for Zig-level hooks
instead; the build detects it and compiles it into the shared library.

## Sessions

```java
try (Session session = new Session(SessionOptions.builder()
        .maxErrors(10)
        .recoveryWindow(500)
        .build())) {
    int parsed = session.parse("alpha:12,beta:3");
    Node root = session.rootNode();
    if (root != null) {
        for (Node child : session.children(root)) {
            System.out.println(new String(session.symbolName(child)));
            System.out.println("  → " + new String(session.text(child)));
        }
        // Node convenience: root.children(), root.text(), etc.
        for (Node child : root) {
            System.out.println(child.symbolNameString() + " " + new String(child.text()));
        }
    }
    // Zero-copy direct buffer for throughput-sensitive paths (benchmarks):
    // ByteBuffer buf = ByteBuffer.allocateDirect(data.length);
    // buf.put(data).flip();
    // for (int i = 0; i < iterations; i++) { buf.rewind(); session.parse(buf); }
    // Heap ByteBuffer and byte[] reuse the same cached native Memory.
} catch (GalleyException e) {
    Diagnostic d = e.getDiagnostic();
    if (d != null) System.err.println(d.getLine() + ":" + d.getColumn() + " " + d.getMessage());
}
// Or inspect after catch:
// if (session.hasDiagnostic()) { Diagnostic d = session.diagnostic(); }
```

Parsing entry points: `parse(byte[])`, `parse(ByteBuffer)`, `parse(String)`, `parseSentinel(String|byte[]|ByteBuffer)`, and `parseFile(String|File)`. `ByteBuffer` honors `position`/`remaining`/`arrayOffset`; direct buffers are passed by pointer with `Reference.reachabilityFence`.

Sessions own their IO backend and allocator and are not safe for concurrent
use — keep one per thread or guard it externally. Node handles, text slices,
and diagnostics remain valid until the next parse on the same session or
`close()`. `try (Session s = new Session())` is the idiomatic close pattern
(`s.close()` is idempotent).

Tree editing follows the same address-stable model as the C API: addresses
never invalidate across edits.

```java
Node head = session.cleanChildren(root);
session.appendChildren(root, head);
// Node wrappers:
Node head2 = root.cleanChildren();
root.appendChildren(head2);
```

## Module Queries

```java
Galley.version();                         // String
Galley.parserType();                       // PARSER_TYPE_LL / PARSER_TYPE_LR
Galley.hasAst();                           // boolean
Galley.hasProcedures();
Galley.errorRecoveryMode();                // RECOVERY_MODE_*
Galley.statusString(-2);                   // "syntax error" / null
Galley.symbolCount();                      // long
Galley.variableCount();
session.symbolNameAt(0);                   // byte[] / null
session.symbolIsTerminal(0);
session.variableNameAt(0);
```

## Related Pages

- [C and C++](/bindings_c) — the underlying C ABI
- [Rust](/bindings_rust) — bindings over the same shared library
- [Go](/bindings_go) — cgo bindings over the same shared library
- [Python](/bindings_python) — Python bindings over the same shared library
- [TypeScript](/bindings_typescript) — FFI bindings over the same shared library
- [Configuration](/configuration) — the config.zig contract
- [Grammar Guidelines](/grammar_guidelines)
