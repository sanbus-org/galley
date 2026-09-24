package org.sanbus.galley;

import org.junit.jupiter.api.*;
import org.junit.jupiter.api.function.Executable;
import static org.junit.jupiter.api.Assertions.*;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.PrintStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Consumer;

/**
 * Behavioral tests for the Galley Java bindings.
 * Mirrors bindings/python/tests/test_bindings.py and bindings/js/node/tests/test_bindings.mjs.
 *
 * Requires the shared library built for the binding's own test fixture
 * (built on demand, never examples/):
 *   GALLEY_CHECKOUT=<checkout> java -cp bindings/java/out \
 *     org.sanbus.galley.build.GalleyBuild bindings/java/test-fixture
 * Point it at the file with GALLEY_LIBRARY_PATH (or -Dgalley.library.path);
 * a missing file is a loud error, never a search.
 */
public class GalleyTest {

    private static String fixtureLibraryPath() {
        String env = System.getenv("GALLEY_LIBRARY_PATH");
        if (env != null && !env.isEmpty()) return env;
        String prop = System.getProperty("galley.library.path");
        if (prop != null && !prop.isEmpty()) return prop;
        throw new IllegalStateException("GALLEY_LIBRARY_PATH (or galley.library.path) must point at the fixture library");
    }

    private static Parser fixtureParser() {
        try {
            Parser parser = Galley.load(fixtureLibraryPath());
            parser.clearProcedures();
            return parser;
        } catch (MissingArtifactException e) {
            throw new IllegalStateException("fixture library missing: " + e.getMessage(), e);
        }
    }

    @Test
    void versionReturnsNonEmptyString() throws Exception {
        String v = Galley.version();
        assertNotNull(v);
        assertFalse(v.isEmpty());
    }

    @Test
    void parserMetadataFlagsAreConsistent() throws Exception {
        assertEquals(ParserType.LL, Galley.parserType());
        assertTrue(Galley.hasAst());
        // boolean flags
        assertNotNull(Galley.hasProcedures());
        assertNotNull(Galley.allowsNoAstTreeProcedures());
        assertNotNull(Galley.sourceRetentionEnabled());
        assertNotNull(Galley.hasPositionTracking());
        assertNotNull(Galley.hasInputStreaming());
        assertNotNull(Galley.usesVerbatim());
        assertNotNull(Galley.stackOverflowRecoveryAvailable());
        RecoveryMode rm = Galley.errorRecoveryMode();
        assertTrue(rm == RecoveryMode.DISABLED || rm == RecoveryMode.AUTOMATIC || rm == RecoveryMode.EXPLICIT);
        assertEquals(0, ParserType.LL.getCode());
        assertEquals(1, ParserType.LR.getCode());
        assertEquals(ParserType.UNKNOWN, ParserType.fromCode(999));
        assertEquals(RecoveryMode.UNKNOWN, RecoveryMode.fromCode(999));
    }

    @Test
    void statusStringRendersKnownCodes() throws Exception {
        String rendered = Galley.statusString(StatusCode.ERROR_SYNTAX);
        assertNotNull(rendered);
        assertTrue(rendered.toLowerCase().contains("syntax"));
        assertEquals(StatusCode.UNKNOWN, StatusCode.fromCode(999999));
        assertNull(Galley.statusString(StatusCode.fromCode(999999)));
    }

    @Test
    void diagnosticTypeIsNotDirectlyConstructible() {
        // Diagnostic is a plain data holder; ensure it requires args
        try {
            Diagnostic.class.getDeclaredConstructor().newInstance();
            fail("expected no no-arg constructor");
        } catch (NoSuchMethodException e) {
            // expected
        } catch (Exception e) {
            // other reflection failure also ok if it indicates no default ctor
            assertTrue(e instanceof NoSuchMethodException || e.getCause() instanceof NoSuchMethodException);
        }
    }

    @Nested
    class SessionTests {
        Session session;
        Parser parser;

        @BeforeEach
        void setUp() {
            parser = fixtureParser();
            session = parser.openSession(SessionOptions.builder().maxErrors(10).build());
        }

        @AfterEach
        void tearDown() {
            session.close();
            parser.clearProcedures();
        }

        @Test
        void procedureHookCanReadNodeText() {
            List<byte[]> seen = new ArrayList<>();
            parser.installProcedure("reduction_Pair", args -> {
                Node node = args.currentNode();
                assertNotNull(node);
                assertNotNull(args.getSession());
                byte[] text = node.text();
                assertNotNull(text);
                assertTrue(text.length > 0);
                seen.add(text);
            });
            session.parse("alpha:12,beta:3");
            assertEquals(2, seen.size());
        }

        @Test
        void nestedParseRestoresOuterGates() {
            List<String> outerSeen = new ArrayList<>();
            List<String> innerSeen = new ArrayList<>();
            boolean[] nested = {false};
            AtomicReference<Consumer<ProcedureArguments>> outerHook = new AtomicReference<>();
            outerHook.set(args -> {
                Node node = args.currentNode();
                assertNotNull(node);
                outerSeen.add(new String(node.text(), StandardCharsets.UTF_8));
                if (!nested[0]) {
                    nested[0] = true;
                    Session innerSession = parser.openSession();
                    try {
                        parser.clearProcedures();
                        parser.installProcedure("reduction_Number", innerArgs -> {
                            Node innerNode = innerArgs.currentNode();
                            assertNotNull(innerNode);
                            innerSeen.add(new String(innerNode.text(), StandardCharsets.UTF_8));
                        });
                        try {
                            innerSession.parse("alpha:9");
                        } finally {
                            parser.clearProcedures();
                            parser.installProcedure("reduction_Pair", outerHook.get());
                        }
                    } finally {
                        innerSession.close();
                    }
                }
            });
            parser.installProcedure("reduction_Pair", outerHook.get());
            try {
                session.parse("alpha:12,beta:3");
            } finally {
                parser.clearProcedures();
            }
            assertEquals(List.of("alpha:12", "beta:3"), outerSeen);
            assertEquals(List.of("9"), innerSeen);
        }

        @Test
        void hookArgumentsReportSessionOpen() {
            List<Boolean> seen = new ArrayList<>();
            parser.installProcedure("reduction_Pair", args -> seen.add(args.isClosed()));
            try {
                session.parse("alpha:12,beta:3");
            } finally {
                parser.clearProcedures();
            }
            assertEquals(List.of(false, false), seen);
        }

        @Test
        void parseAcceptsStringAndBytes() {
            String sample = "alpha:12,beta:3";
            assertEquals(sample.length(), session.parse(sample));
            assertEquals(sample.length(), session.parse(sample.getBytes(StandardCharsets.UTF_8)));
            // byte array via parse
            assertEquals(sample.length(), session.parse(sample.getBytes(StandardCharsets.UTF_8)));
        }

        @Test
        void parseSentinelMatchesParseForNulFreeInput() {
            String sample = "alpha:12,beta:3";
            int a = session.parseSentinel(sample);
            int b = session.parse(sample);
            assertEquals(a, b);
        }

        @Test
        void syntaxErrorThrowsWithCodeAndDiagnostic() {
            GalleyException ex = assertThrows(GalleyException.class, () -> session.parse("alpha:"));
            assertEquals(StatusCode.ERROR_SYNTAX, ex.getCode());
            Diagnostic d = ex.getDiagnostic();
            assertNotNull(d);
            assertTrue(session.hasDiagnostic());
            assertNotNull(session.diagnostic());
            assertEquals(DiagnosticKind.SYNTAX, d.getKind());
            assertEquals(1, d.getLine());
            assertEquals(7, d.getColumn());
            assertTrue(d.getMessage().contains("parse failed"));
            assertNotNull(d.getMessageAnsi());
            assertFalse(d.getExpectedTokens().isEmpty());
            assertTrue(d.getExpectedTokens().stream().allMatch(t -> t instanceof byte[]));
            assertEquals("Number", d.getContext().get(d.getContext().size() - 1));
            assertTrue(d.getSyntaxErrorCount() >= 0);
        }

        @Test
        void diagnosticResetsAfterSuccessfulParse() {
            Session s = parser.openSession();
            try {
                assertThrows(GalleyException.class, () -> s.parse("alpha:"));
                assertNotNull(s.diagnostic());
                s.parse("alpha:1");
                assertFalse(s.hasDiagnostic());
                assertNull(s.diagnostic());
            } finally {
                s.close();
            }
        }

        @Test
        void failureDiagnosticIsFrozenAcrossLaterParses() {
            GalleyException failure = assertThrows(GalleyException.class, () -> session.parse("alpha:"));
            Diagnostic frozen = failure.getDiagnostic();
            assertNotNull(frozen);
            String message = frozen.getMessage();
            assertFalse(message.isEmpty());
            List<byte[]> expectedBefore = new ArrayList<>();
            for (byte[] token : frozen.getExpectedTokens()) expectedBefore.add(token.clone());
            assertFalse(expectedBefore.isEmpty());
            List<String> contextBefore = List.copyOf(frozen.getContext());
            List<byte[]> contextBytesBefore = new ArrayList<>();
            for (byte[] name : frozen.getContextBytes()) contextBytesBefore.add(name.clone());
            // A later successful parse cannot mutate the snapshot this failure carries.
            session.parse("alpha:12,beta:3");
            assertFalse(session.hasDiagnostic());
            assertEquals(message, frozen.getMessage());
            assertEquals(DiagnosticKind.SYNTAX, frozen.getKind());
            assertEquals(expectedBefore.size(), frozen.getExpectedTokens().size());
            for (int i = 0; i < expectedBefore.size(); i++) {
                assertArrayEquals(expectedBefore.get(i), frozen.getExpectedTokens().get(i));
            }
            assertEquals(contextBefore, frozen.getContext());
            assertEquals(contextBytesBefore.size(), frozen.getContextBytes().size());
            for (int i = 0; i < contextBytesBefore.size(); i++) {
                assertArrayEquals(contextBytesBefore.get(i), frozen.getContextBytes().get(i));
            }
            // Callers cannot mutate it through the getters either.
            List<byte[]> tokens = frozen.getExpectedTokens();
            assertEquals(expectedBefore.size(), tokens.size());
            for (int i = 0; i < tokens.size(); i++) {
                byte[] exposed = tokens.get(i);
                assertArrayEquals(expectedBefore.get(i), exposed);
                if (exposed.length > 0) {
                    exposed[0] ^= (byte) 0xFF;
                    assertArrayEquals(expectedBefore.get(i), frozen.getExpectedTokens().get(i));
                }
            }
            assertThrows(UnsupportedOperationException.class, () -> frozen.getExpectedTokens().add(new byte[0]));
        }

        @Test
        void fileParsingReportsEndPosition() throws Exception {
            Path p = Path.of("/tmp/galley-java-bindings-test.kv");
            Files.writeString(p, "alpha:12,beta:3", StandardCharsets.UTF_8);
            int parsed = session.parseFile(p.toString());
            assertEquals(15, parsed);
            assertEquals(15, session.parseFile(p));
            int[] pos = session.lastPosition();
            assertNotNull(pos);
            assertArrayEquals(new int[]{1, 17}, pos);
        }

        @Test
        void hookReportedSemanticErrorsAggregateAndFail() {
            List<Integer> counts = new ArrayList<>();
            parser.installProcedure("reduction_Number", args -> {
                Node node = args.currentNode();
                assertNotNull(node);
                int value = Integer.parseInt(new String(node.text(), StandardCharsets.UTF_8));
                if (value > 99) counts.add(args.reportSemanticError("value out of range"));
            });
            GalleyException ex = assertThrows(GalleyException.class,
                    () -> session.parse("alpha:12,beta:300,gamma:400"));
            assertEquals(StatusCode.ERROR_SEMANTIC, ex.getCode());
            assertTrue(ex.getMessage().contains("value out of range"));
            assertEquals(List.of(1, 2), counts);
            Diagnostic d = session.diagnostic();
            assertNotNull(d);
            assertEquals(DiagnosticKind.SEMANTIC, d.getKind());
            assertEquals(1, d.getLine());
            assertEquals(2, d.getSemanticErrorCount());
            assertArrayEquals(new String[]{"Number", "value out of range"}, d.getSemantic());
            assertTrue(d.getMessage().contains("SemanticError"));
            assertEquals(2, session.diagnostics().size());
        }

        @Test
        void semanticCountsResetAfterSuccessfulParse() {
            parser.installProcedure("reduction_Number", args -> {
                Node node = args.currentNode();
                assertNotNull(node);
                int value = Integer.parseInt(new String(node.text(), StandardCharsets.UTF_8));
                if (value > 99) args.reportSemanticError("value out of range");
            });
            assertThrows(GalleyException.class, () -> session.parse("alpha:300"));
            session.parse("alpha:12");
            assertFalse(session.hasDiagnostic());
            assertNull(session.diagnostic());
            assertTrue(session.diagnostics().isEmpty());
        }

        @Test
        void messageOverrideAcceptsRawBytes() {
            Session s = parser.openSession();
            try {
                s.setMessageOverride("Number", "välue {line}".getBytes(StandardCharsets.UTF_8));
                GalleyException ex = assertThrows(GalleyException.class, () -> s.parse("alpha:"));
                assertTrue(ex.getDiagnostic().getMessage().contains("välue 1"));
            } finally {
                s.close();
            }
            Session built = parser.openSession(SessionOptions.builder()
                    .messageOverride("Number", "built {line}".getBytes(StandardCharsets.UTF_8))
                    .build());
            try {
                GalleyException ex = assertThrows(GalleyException.class, () -> built.parse("alpha:"));
                assertTrue(ex.getDiagnostic().getMessage().contains("built 1"));
            } finally {
                built.close();
            }
        }

        @Test
        void parseEntriesRejectNullLoudly() {
            assertThrows(IllegalArgumentException.class, () -> session.parse((byte[]) null));
            assertThrows(IllegalArgumentException.class, () -> session.parse((String) null));
            assertThrows(IllegalArgumentException.class, () -> session.parse((ByteBuffer) null));
            assertThrows(IllegalArgumentException.class, () -> session.parseFile((String) null));
            assertThrows(IllegalArgumentException.class, () -> session.parseFile((File) null));
            assertThrows(IllegalArgumentException.class, () -> session.parseFile((Path) null));
            assertThrows(IllegalArgumentException.class, () -> session.setMessageOverride(null, "x"));
            assertThrows(IllegalArgumentException.class, () -> session.setMessageOverride("Number", (String) null));
            assertThrows(IllegalArgumentException.class, () -> session.setMessageOverride("Number", (byte[]) null));
            assertThrows(IllegalArgumentException.class, () -> SessionOptions.builder().messageOverride(null, "x"));
            assertThrows(IllegalArgumentException.class, () -> SessionOptions.builder().messageOverride("Number", (byte[]) null));
            assertThrows(IllegalArgumentException.class, () -> SessionOptions.builder().messageOverrides(null));
        }

        @Test
        void parseFileRejectsNulPathLoudly() {
            assertThrows(IllegalArgumentException.class, () -> session.parseFile("kv\0.txt"));
        }
    }

    @Nested
    class WalkTests {
        Session session;
        Parser parser;

        @BeforeEach
        void setUp() {
            parser = fixtureParser();
            session = parser.openSession();
            session.parse("alpha:12,beta:3");
        }

        @AfterEach
        void tearDown() {
            session.close();
            parser.clearProcedures();
        }

        @Test
        void rootAndNavigationLinks() {
            Node root = session.rootNode();
            assertNotNull(root);
            assertTrue(session.nodeValid(root));
            assertNull(session.parent(root));
            assertFalse(session.nodeValid(0xFFFFFFFFFFFFFFFFL));
            Node first = session.firstChild(root);
            Node last = session.lastChild(root);
            assertNotNull(first);
            assertNotNull(last);
            assertNull(session.nextSibling(last));
            assertNull(session.priorSibling(first));
            assertEquals(root.getAddress(), session.parent(first).getAddress());
            List<Node> visited = new ArrayList<>();
            Node child = first;
            while (child != null) {
                visited.add(child);
                child = session.nextSibling(child);
            }
            assertEquals(visited.size(), session.childCount(root));
        }

        @Test
        void symbolNamesTextSpansAndPositions() {
            Node root = session.rootNode();
            assertNotNull(root);
            assertEquals("Document", session.symbolName(root));
            assertArrayEquals("Document".getBytes(StandardCharsets.UTF_8), session.symbolNameBytes(root));
            byte[] text = session.text(root);
            assertArrayEquals("alpha:12,beta:3".getBytes(StandardCharsets.UTF_8), text);
            long[] span = session.span(root);
            assertNotNull(span);
            assertEquals(0, span[0]);
            assertEquals(text.length, span[1]);
            int[] pos = session.lineColumn(root);
            assertNotNull(pos);
            assertArrayEquals(new int[]{1, 1}, pos);
            assertNotNull(session.variableIndex(root));
            assertTrue(session.nodeCount() > 0);
        }

        @Test
        void nodeObjectMirrorsSessionNavigation() {
            Node root = session.rootNode();
            assertNotNull(root);
            assertEquals("Document", root.symbolName());
            assertArrayEquals("Document".getBytes(StandardCharsets.UTF_8), root.symbolNameBytes());
            assertNotNull(root.text());
            assertArrayEquals(new long[]{0, 15}, root.span());
            assertArrayEquals(new int[]{1, 1}, root.lineColumn());
            assertEquals(session.childCount(root), root.length());
            assertNotNull(root.firstChild());
            assertNotNull(root.lastChild());
            assertNull(root.parent());
            List<Node> kids = root.children();
            assertEquals(1, kids.size());
            int count = 0;
            for (Node c : root) count++;
            assertEquals(1, count);
            assertEquals(kids.get(0).getAddress(), root.at(0).getAddress());
            assertThrows(IndexOutOfBoundsException.class, () -> root.at(100));
            Node root2 = session.rootNode();
            assertEquals(root, root2);
            assertNotEquals(root, 123L);
        }

        @Test
        void terminalOnlyNodesHaveEmptySymbolNames() {
            // Find a node with empty symbol name
            Node root = session.rootNode();
            assertNotNull(root);
            Node found = findTerminal(root);
            assertNotNull(found);
        }

        private Node findTerminal(Node node) {
            byte[] sym = session.symbolNameBytes(node);
            if (sym != null && sym.length == 0) return node;
            Node child = session.firstChild(node);
            while (child != null) {
                Node f = findTerminal(child);
                if (f != null) return f;
                child = session.nextSibling(child);
            }
            return null;
        }

        @Test
        void invalidNodeAccessorsReturnNull() {
            long invalid = 0xFFFFFFFFFFFFFFFFL;
            assertNull(session.symbolName(invalid));
            assertNull(session.text(invalid));
            assertNull(session.span(invalid));
            assertNull(session.lineColumn(invalid));
            assertNull(session.variableIndex(invalid));
            assertEquals(0, session.childCount(invalid));
        }

        @Test
        void walkMatchesHandRolledRecursion() {
            session.parse("alpha:12,beta:3");
            Node root = session.rootNode();
            assertNotNull(root);
            List<long[]> expected = new ArrayList<>();
            collectRecursive(root, 0, expected);
            assertTrue(expected.size() > 1);
            try (Walker walker = session.walk(root, false)) {
                assertNotNull(walker);
                List<long[]> walked = new ArrayList<>();
                List<Boolean> flags = new ArrayList<>();
                for (Walker.WalkStep step : walker) {
                    walked.add(new long[]{step.node.getAddress(), step.depth});
                    flags.add(step.isSemanticError);
                }
                assertEquals(expected.size(), walked.size());
                for (int i = 0; i < expected.size(); i++) {
                    assertArrayEquals(expected.get(i), walked.get(i));
                    assertFalse(flags.get(i));
                }
            }
        }

        @Test
        void snapshotMatchesPerNodeAccessors() {
            TreeSnapshot snap = session.snapshot();
            long count = session.nodeCount();
            assertEquals(count, snap.count());
            assertTrue(count > 0);
            assertEquals(count, snap.parent().length);
            assertEquals(count, snap.firstChild().length);
            assertEquals(count, snap.next().length);
            assertEquals(count, snap.childCount().length);
            assertEquals(count, snap.variable().length);
            assertEquals(count, snap.spanStart().length);
            assertEquals(count, snap.spanLen().length);
            assertEquals(count, snap.isSemanticError().length);
            for (long address = 0; address < count; address++) {
                int slot = (int) address;
                Node parent = session.parent(address);
                assertEquals(parent == null ? -1L : parent.getAddress(), snap.parent()[slot]);
                Node first = session.firstChild(address);
                assertEquals(first == null ? -1L : first.getAddress(), snap.firstChild()[slot]);
                Node next = session.nextSibling(address);
                assertEquals(next == null ? -1L : next.getAddress(), snap.next()[slot]);
                assertEquals(session.childCount(address), snap.childCount()[slot]);
                Integer variable = session.variableIndex(address);
                assertEquals(variable == null ? -1L : variable.longValue(), snap.variable()[slot]);
                long[] span = session.span(address);
                assertNotNull(span);
                assertEquals(span[0], snap.spanStart()[slot]);
                assertEquals(span[1], snap.spanLen()[slot]);
            }
            // The snapshot alone drives the same preorder walk as the walker.
            Node root = session.rootNode();
            assertNotNull(root);
            List<Long> preorder = new ArrayList<>();
            List<Long> stack = new ArrayList<>();
            stack.add(root.getAddress());
            while (!stack.isEmpty()) {
                long node = stack.remove(stack.size() - 1);
                preorder.add(node);
                long child = snap.firstChild()[(int) node];
                List<Long> chain = new ArrayList<>();
                while (child != -1L) {
                    chain.add(child);
                    child = snap.next()[(int) child];
                }
                assertEquals(chain.size(), snap.childCount()[(int) node]);
                for (int k = chain.size() - 1; k >= 0; k--) stack.add(chain.get(k));
            }
            try (Walker walker = session.walk(root, false)) {
                assertNotNull(walker);
                List<Long> walked = new ArrayList<>();
                for (Walker.WalkStep step : walker) walked.add(step.node.getAddress());
                assertEquals(preorder, walked);
            }
            // Spans index lastInput.
            assertArrayEquals(
                    "alpha:12,beta:3".getBytes(StandardCharsets.UTF_8),
                    session.lastInput());
        }

        private void collectRecursive(Node node, int depth, List<long[]> out) {
            out.add(new long[]{node.getAddress(), depth});
            for (Node child : session.children(node)) collectRecursive(child, depth + 1, out);
        }

        @Test
        void walkSkipChildrenPrunesSubtree() {
            session.parse("alpha:12,beta:3");
            Node root = session.rootNode();
            assertNotNull(root);
            try (Walker walker = session.walk(root, false)) {
                assertNotNull(walker);
                assertTrue(walker.hasNext());
                Walker.WalkStep first = walker.next();
                assertEquals(root.getAddress(), first.node.getAddress());
                assertEquals(0, first.depth);
                walker.skipChildren();
                assertFalse(walker.hasNext());
            }
            assertNull(session.walk(0xFFFFFFFFFFFFFFFFL, false));
        }

        @Test
        void walkerStepAfterReparseThrows() {
            Node root = session.rootNode();
            assertNotNull(root);
            Walker walker = session.walk(root, false);
            assertNotNull(walker);
            assertTrue(walker.hasNext());
            walker.next();
            assertEquals(15, session.parse("alpha:12,beta:3"));
            GenerationInvalidatedException invalidated = assertThrows(GenerationInvalidatedException.class, walker::next);
            assertEquals("walker", invalidated.getObjectName());
            assertThrows(GalleyClosedException.class, walker::skipChildren);
            walker.close();
            walker.close();
            Node fresh = session.rootNode();
            assertNotNull(fresh);
            try (Walker rewound = session.walk(fresh, false)) {
                assertNotNull(rewound);
                assertTrue(rewound.hasNext());
            }
        }

        @Test
        void walkerStepAfterSessionCloseThrows() {
            Node root = session.rootNode();
            assertNotNull(root);
            Walker walker = session.walk(root, false);
            assertNotNull(walker);
            assertTrue(walker.hasNext());
            walker.next();
            session.close();
            assertThrows(GalleyClosedException.class, walker::next);
            assertThrows(GalleyClosedException.class, walker::skipChildren);
            walker.close();
            walker.close();
        }

        @Test
        void parseWithAbandonedWalkerSucceeds() {
            Node root = session.rootNode();
            assertNotNull(root);
            Walker walker = session.walk(root, false);
            assertNotNull(walker);
            // Parsing never throws merely because a walker is open; the
            // abandoned walker fails at its next step instead.
            assertEquals(15, session.parse("alpha:12,beta:3"));
            assertThrows(GalleyClosedException.class, walker::next);
            walker.close();
            Node fresh = session.rootNode();
            assertNotNull(fresh);
            try (Walker rewound = session.walk(fresh, false)) {
                assertNotNull(rewound);
                int steps = 0;
                while (rewound.hasNext()) {
                    rewound.next();
                    steps++;
                }
                assertTrue(steps > 1);
            }
        }

        @Test
        void failedParseInvalidatesWalkers() {
            Node root = session.rootNode();
            assertNotNull(root);
            Walker walker = session.walk(root, false);
            assertNotNull(walker);
            assertTrue(walker.hasNext());
            walker.next();
            assertThrows(GalleyException.class, () -> session.parse("alpha:"));
            assertThrows(GalleyClosedException.class, walker::next);
            walker.close();
        }
    }

    @Nested
    class NodeGenerationTests {
        Session session;
        Parser parser;

        @BeforeEach
        void setUp() {
            parser = fixtureParser();
            session = parser.openSession();
            session.parse("alpha:12,beta:3");
        }

        @AfterEach
        void tearDown() {
            session.close();
            parser.clearProcedures();
        }

        private static void assertInvalidated(Executable read) {
            assertThrows(GenerationInvalidatedException.class, read);
        }

        @Test
        void nodeReadsAfterReparseThrow() {
            Node stale = session.rootNode();
            assertNotNull(stale);
            Node staleChild = stale.firstChild();
            assertNotNull(staleChild);
            assertEquals(7, session.parse("alpha:1"));
            // Every Node accessor family throws instead of reading stale storage.
            assertInvalidated(stale::text);
            assertInvalidated(stale::symbolName);
            assertInvalidated(stale::symbolNameBytes);
            assertInvalidated(stale::span);
            assertInvalidated(stale::lineColumn);
            assertInvalidated(stale::parent);
            assertInvalidated(stale::firstChild);
            assertInvalidated(stale::children);
            assertInvalidated(stale::childCount);
            assertInvalidated(stale::variableIndex);
            assertInvalidated(stale::isValid);
            assertInvalidated(() -> stale.at(0));
            assertInvalidated(stale::iterator);
            assertInvalidated(stale::cleanChildren);
            assertInvalidated(() -> stale.appendChildren(staleChild));
            // Session crossings that take the handle throw too.
            assertInvalidated(() -> session.text(stale));
            assertInvalidated(() -> session.symbolName(stale));
            assertInvalidated(() -> session.span(stale));
            assertInvalidated(() -> session.childCount(stale));
            assertInvalidated(() -> session.children(stale));
            assertInvalidated(() -> session.parent(stale));
            assertInvalidated(() -> session.nodeValid(stale));
            assertInvalidated(() -> session.cleanChildren(stale));
            assertInvalidated(() -> session.walk(stale, false));
            // Fresh handles from the new generation read fine.
            Node fresh = session.rootNode();
            assertNotNull(fresh);
            assertNotNull(fresh.text());
        }

        @Test
        void rawAddressesReadTheNewParseAfterReparse() {
            long address = session.rootNode().getAddress();
            assertNotNull(session.text(address));
            assertEquals(7, session.parse("alpha:1"));
            // Raw addresses carry no generation: they read the new parse, never throw.
            assertNotNull(session.text(address));
            assertNotNull(session.symbolName(address));
            assertNotNull(session.symbolNameBytes(address));
            assertNotNull(session.span(address));
            assertNotNull(session.lineColumn(address));
            assertTrue(session.nodeValid(address));
            assertNotNull(session.children(address));
            assertNotNull(session.firstChild(address));
            assertNull(session.parent(address));
            // Fresh handles read the same new parse.
            assertNotNull(session.rootNode().text());
        }

        @Test
        void failedParseBumpsGeneration() {
            Node stale = session.rootNode();
            assertNotNull(stale);
            assertThrows(GalleyException.class, () -> session.parse("alpha:"));
            assertInvalidated(stale::text);
            assertInvalidated(() -> session.text(stale));
            // The session stays usable: the next parse yields live nodes.
            assertEquals(7, session.parse("alpha:1"));
            assertNotNull(session.rootNode().text());
        }

        @Test
        void setCurrentNodeValidatesHandle() {
            Node fresh = session.rootNode();
            assertNotNull(fresh);
            session.parse("alpha:1");
            AtomicReference<Throwable> seen = new AtomicReference<>();
            // Redirecting to the live node is fine.
            parser.installProcedure("reduction_Pair", args -> {
                try {
                    args.setCurrentNode(args.currentNode());
                } catch (Throwable t) {
                    seen.set(t);
                }
            });
            session.parse("alpha:12,beta:3");
            assertNull(seen.get());
            // A node left over from an older generation throws.
            parser.clearProcedures();
            parser.installProcedure("reduction_Pair", args -> {
                try {
                    args.setCurrentNode(fresh);
                } catch (Throwable t) {
                    seen.set(t);
                }
            });
            session.parse("alpha:12,beta:3");
            assertTrue(seen.get() instanceof GenerationInvalidatedException);
            // A node from another session throws.
            seen.set(null);
            Session other = parser.openSession();
            try {
                other.parse("alpha:12,beta:3");
            } finally {
                other.close();
            }
            assertTrue(seen.get() instanceof IllegalArgumentException);
        }
    }

    @Nested
    class FixtureHookTests {
        Session session;
        Parser parser;

        @BeforeEach
        void setUp() {
            parser = fixtureParser();
            session = parser.openSession();
            test_fixture.procedures.register(parser);
        }

        @AfterEach
        void tearDown() {
            session.close();
            parser.clearProcedures();
        }

        @Test
        void hugeDigitStringsReportOutOfRange() {
            // Old parseLong logic went silent past Long.MAX; digit extraction reports.
            GalleyException ex = assertThrows(GalleyException.class,
                    () -> session.parse("alpha:99999999999999999999999"));
            assertEquals(StatusCode.ERROR_SEMANTIC, ex.getCode());
            assertTrue(ex.getMessage().contains("value out of range"));
        }

        @Test
        void ordinaryNumbersStillPassWithRealHooks() {
            assertEquals(8, session.parse("alpha:12"));
        }
    }

    @Nested
    class EditTests {
        Session session;
        Parser parser;
        Node root;

        @BeforeEach
        void setUp() {
            parser = fixtureParser();
            session = parser.openSession();
            session.parse("alpha:12,beta:3");
            root = session.rootNode();
            assertNotNull(root);
        }

        @AfterEach
        void tearDown() {
            session.close();
            parser.clearProcedures();
        }

        @Test
        void cleanAndAppendRoundTrip() {
            int before = session.childCount(root);
            Node head = session.cleanChildren(root);
            assertNotNull(head);
            assertEquals(0, session.childCount(root));
            session.appendChildren(root, head);
            assertEquals(before, session.childCount(root));
        }

        @Test
        void nodeCleanAndAppendRoundTrip() {
            int before = root.length();
            Node head = root.cleanChildren();
            assertNotNull(head);
            assertEquals(0, root.length());
            root.appendChildren(head);
            assertEquals(before, root.length());
        }

        @Test
        void insertBeforeReordersSiblings() {
            Node wrapper = session.firstChild(root);
            assertNotNull(wrapper);
            Node pair = session.firstChild(wrapper);
            assertNotNull(pair);
            Node tail = session.nextSibling(pair);
            assertNotNull(tail);
            Node detached = session.removeSiblings(tail, 1);
            assertNotNull(detached);
            session.insertBefore(pair, detached);
            assertEquals(tail.getAddress(), session.firstChild(wrapper).getAddress());
            assertNull(session.nextSibling(pair));
            assertEquals(pair.getAddress(), session.nextSibling(tail).getAddress());
        }

        @Test
        void removeSelfDetachesSingleNode() {
            Node first = session.firstChild(root);
            assertNotNull(first);
            Node head = session.removeSelf(first);
            assertEquals(first.getAddress(), head.getAddress());
            assertNull(session.parent(first));
        }

        @Test
        void insertAndRemoveChildrenAt() {
            int original = session.childCount(root);
            Node head = session.cleanChildren(root);
            assertNotNull(head);
            session.insertChildrenAt(root, 0, head);
            assertEquals(original, session.childCount(root));
            Node removed = session.removeChildrenAt(root, 0, original);
            assertNotNull(removed);
            assertEquals(0, session.childCount(root));
        }

        @Test
        void promoteAndUnlinkWrapper() {
            Node wrapper = session.firstChild(root);
            assertNotNull(wrapper);
            Node grandchildrenHead = session.cleanChildren(wrapper);
            assertNotNull(grandchildrenHead);
            session.appendChildren(wrapper, grandchildrenHead);
            Node promoted = session.promoteChildrenOverWrapper(wrapper);
            assertNotNull(promoted);
            List<Node> active = new ArrayList<>();
            Node child = session.firstChild(root);
            while (child != null) {
                active.add(child);
                child = session.nextSibling(child);
            }
            assertTrue(active.stream().noneMatch(n -> n.getAddress() == wrapper.getAddress()));
            assertTrue(active.stream().anyMatch(n -> n.getAddress() == promoted.getAddress()));
        }

        @Test
        void unlinkWrapperDetachesWithoutTouchingChildren() {
            Node wrapper = session.firstChild(root);
            assertNotNull(wrapper);
            int before = session.childCount(wrapper);
            session.unlinkWrapper(wrapper);
            assertEquals(before, session.childCount(wrapper));
            Node first = session.firstChild(root);
            // wrapper was the only child; after unlink root has no children (null) which is not wrapper
            if (first == null) {
                assertNotEquals(wrapper.getAddress(), 0xFFFFFFFFFFFFFFFFL);
            } else {
                assertNotEquals(wrapper.getAddress(), first.getAddress());
            }
        }

        @Test
        void rawAddressOverloadsMirrorNodeOverloads() {
            long rootAddr = root.getAddress();
            int before = session.childCount(rootAddr);
            Node head = session.cleanChildren(rootAddr);
            assertNotNull(head);
            assertEquals(0, session.childCount(rootAddr));
            session.appendChildren(rootAddr, head.getAddress());
            assertEquals(before, session.childCount(rootAddr));

            Node wrapper = session.firstChild(rootAddr);
            assertNotNull(wrapper);
            long wrapperAddr = wrapper.getAddress();
            Node pair = session.firstChild(wrapperAddr);
            assertNotNull(pair);
            Node tail = session.nextSibling(pair.getAddress());
            assertNotNull(tail);
            Node detached = session.removeSiblings(tail.getAddress(), 1);
            assertNotNull(detached);
            session.insertBefore(pair.getAddress(), detached.getAddress());
            assertEquals(tail.getAddress(), session.firstChild(wrapperAddr).getAddress());
            session.insertAfter(pair.getAddress(), detached.getAddress());
            assertEquals(detached.getAddress(), session.nextSibling(pair.getAddress()).getAddress());

            Node removedSelf = session.removeSelf(pair.getAddress());
            assertEquals(pair.getAddress(), removedSelf.getAddress());
            assertNull(session.parent(pair.getAddress()));

            Node grandchildrenHead = session.cleanChildren(wrapperAddr);
            assertNotNull(grandchildrenHead);
            session.appendChildren(wrapperAddr, grandchildrenHead.getAddress());
            Node promoted = session.promoteChildrenOverWrapper(wrapperAddr);
            assertNotNull(promoted);

            int original = session.childCount(rootAddr);
            Node childrenHead = session.cleanChildren(rootAddr);
            assertNotNull(childrenHead);
            session.insertChildrenAt(rootAddr, 0, childrenHead.getAddress());
            assertEquals(original, session.childCount(rootAddr));
            Node removed = session.removeChildrenAt(rootAddr, 0, original);
            assertNotNull(removed);
            assertEquals(0, session.childCount(rootAddr));

            // Fresh tree for the unlink path.
            session.parse("alpha:12,beta:3");
            root = session.rootNode();
            assertNotNull(root);
            Node freshWrapper = session.firstChild(root.getAddress());
            assertNotNull(freshWrapper);
            int wrapperKids = session.childCount(freshWrapper.getAddress());
            session.unlinkWrapper(freshWrapper.getAddress());
            assertEquals(wrapperKids, session.childCount(freshWrapper.getAddress()));
        }
    }

    @Nested
    class SymbolTableTests {
        Session session;
        Parser parser;

        @BeforeEach
        void setUp() {
            parser = fixtureParser();
            session = parser.openSession();
        }

        @AfterEach
        void tearDown() {
            session.close();
            parser.clearProcedures();
        }

        @Test
        void symbolAndVariableTables() throws Exception {
            assertTrue(Galley.symbolCount() > 0);
            assertTrue(Galley.variableCount() > 0);
            String firstName = session.symbolNameAt(0);
            assertNotNull(firstName);
            assertFalse(firstName.isEmpty());
            assertArrayEquals(firstName.getBytes(StandardCharsets.UTF_8), session.symbolNameAtBytes(0));
            assertNotNull(session.symbolIsTerminal(0));
            String varName = session.variableNameAt(0);
            assertNotNull(varName);
            assertFalse(varName.isEmpty());
            assertArrayEquals(varName.getBytes(StandardCharsets.UTF_8), session.variableNameAtBytes(0));
            assertNull(session.symbolNameAt(1_000_000_000L));
            assertNull(session.symbolNameAtBytes(1_000_000_000L));
            assertNull(session.variableNameAt(1_000_000_000L));
            assertNull(session.variableNameAtBytes(1_000_000_000L));
        }
    }

    @Nested
    class ReservationTests {
        @Test
        void reserveAndReportCapacity() {
            Parser parser = fixtureParser();
            Session s = parser.openSession();
            try {
                long cap = s.nodeCapacity();
                s.reserveNodes(cap + 1024);
                assertTrue(s.nodeCapacity() >= cap + 1024);
            } finally {
                s.close();
                parser.clearProcedures();
            }
        }
    }

    @Nested
    class LifetimeTests {
        Parser parser;

        @BeforeEach
        void setUp() {
            parser = fixtureParser();
        }

        @AfterEach
        void tearDown() {
            parser.clearProcedures();
        }

        @Test
        void closeIsIdempotentAndClosedSessionsThrow() {
            Session s = parser.openSession();
            s.parse("alpha:12");
            s.close();
            s.close();
            GalleyClosedException closed = assertThrows(GalleyClosedException.class, () -> s.parse("alpha:12"));
            assertTrue(closed.getMessage().contains("session"));
            assertThrows(GalleyClosedException.class, () -> s.rootNode());
        }

        @Test
        void closedObjectsNameThemselves() {
            Session s = parser.openSession();
            s.parse("alpha:12,beta:3");
            Node root = s.rootNode();
            assertNotNull(root);
            Walker walker = s.walk(root, false);
            assertNotNull(walker);
            walker.close();
            walker.close();
            GalleyClosedException walkerClosed = assertThrows(GalleyClosedException.class, walker::hasNext);
            assertTrue(walkerClosed.getMessage().contains("walker"));
            assertEquals("walker", walkerClosed.getObjectName());
            s.close();
            GalleyClosedException sessionClosed = assertThrows(GalleyClosedException.class, () -> root.text());
            assertTrue(sessionClosed.getMessage().contains("session"));
            assertEquals("node's session", sessionClosed.getObjectName());
        }

        @Test
        void nodeAfterCloseThrows() {
            Session s = parser.openSession();
            s.parse("alpha:12,beta:3");
            Node root = s.rootNode();
            s.close();
            assertThrows(GalleyClosedException.class, () -> root.children());
            assertThrows(GalleyClosedException.class, () -> root.text());
        }

        @Test
        void autoCloseable() {
            Session s = parser.openSession();
            s.parse("alpha:12");
            s.close();
            assertTrue(s.isClosed());
            Session s2 = parser.openSession();
            s2.close();
            assertTrue(s2.isClosed());
        }

        @Test
        void optionsRoundTrip() {
            Session s = parser.openSession(SessionOptions.builder()
                    .maxErrors(3)
                    .recoveryWindow(100)
                    .stackOverflowRecovery(false)
                    .syntaxErrorStackDepth(8)
                    .verbosity(0)
                    .astPreallocationRatio(2.0)
                    .astPreallocationCap(4096)
                    .build());
            try {
                assertTrue(s.parse("alpha:12") > 0);
            } finally {
                s.close();
            }
        }

        @Test
        void messageOverride() {
            Session s = parser.openSession(SessionOptions.builder()
                    .messageOverride("Number", "custom at line {line}")
                    .build());
            try {
                GalleyException ex = assertThrows(GalleyException.class, () -> s.parse("alpha:"));
                assertTrue(ex.getDiagnostic().getMessage().contains("custom at line 1"));
                Session s2 = parser.openSession();
                try {
                    s2.setMessageOverride("Number", "override2 {line}:{column}");
                    GalleyException ex2 = assertThrows(GalleyException.class, () -> s2.parse("alpha:"));
                    assertTrue(ex2.getDiagnostic().getMessage().contains("override2"));
                } finally {
                    s2.close();
                }
            } finally {
                s.close();
            }
        }

        @Test
        void procedureHookCanReadNodeTextWithSession() {
            List<String> seen = new ArrayList<>();
            parser.installProcedure("reduction_Pair", args -> {
                Node n = args.currentNode();
                assertNotNull(n);
                seen.add(new String(n.text(), StandardCharsets.UTF_8));
            });
            Session sess = parser.openSession();
            try {
                sess.parse("alpha:12,beta:3");
                assertEquals(2, seen.size());
            } finally {
                sess.close();
            }
        }

        @Test
        void installProcedureDispatchesHostHooks() {
            AtomicInteger called = new AtomicInteger(0);
            parser.installProcedure("reduction", () -> called.incrementAndGet());
            parser.installProcedure("reduction_Pair", args -> called.incrementAndGet());
            assertEquals(2, parser.listProcedures().size());
            Session sess = parser.openSession();
            try {
                sess.parse("alpha:12,beta:3");
                assertTrue(called.get() > 0);
                int before = called.get();
                parser.clearProcedures();
                assertEquals(0, parser.listProcedures().size());
                sess.parse("alpha:12");
                assertEquals(before, called.get());
            } finally {
                sess.close();
            }
        }

        @Test
        void installProceduresBulkRegisters() {
            Map<String, Object> mod = Map.of(
                    "reduction_Document", (java.util.function.Consumer<ProcedureArguments>) args -> {},
                    "hook_print", (Runnable) () -> {},
                    "notAHook", (java.util.function.Consumer<ProcedureArguments>) args -> {}
            );
            int n = parser.installProcedures(mod);
            assertEquals(2, n);
            assertEquals(2, parser.listProcedures().size());
        }

        @Test
        void hookThrowingDoesNotAbortParse() {
            parser.installProcedure("reduction_Pair", args -> { throw new RuntimeException("boom"); });
            Session sess = parser.openSession();
            try {
                int parsed = sess.parse("alpha:12,beta:3");
                assertTrue(parsed > 0);
            } finally {
                sess.close();
            }
        }

        @Test
        void nearMissHookNamesWarnAndStayUninstalled() {
            PrintStream original = System.err;
            ByteArrayOutputStream captured = new ByteArrayOutputStream();
            System.setErr(new PrintStream(captured, true, StandardCharsets.UTF_8));
            try {
                parser.installProcedure("reduction_Pair", args -> {});
                parser.installProcedure("reductionPair", args -> {});
                parser.installProcedure("hookPrint", () -> {});
                int installed = parser.installProcedures(Map.of(
                        "reducton_X", (Runnable) () -> {},
                        "myHelper", (Runnable) () -> {}));
                assertEquals(0, installed);
            } finally {
                System.setErr(original);
            }
            String warnings = captured.toString(StandardCharsets.UTF_8);
            assertEquals(1, parser.listProcedures().size());
            assertNotNull(parser.lookupProcedure("reduction_Pair"));
            assertNull(parser.lookupProcedure("reductionPair"));
            assertNull(parser.lookupProcedure("hookPrint"));
            assertNull(parser.lookupProcedure("reducton_X"));
            assertNull(parser.lookupProcedure("myHelper"));
            assertFalse(warnings.contains("reduction_Pair"));
            assertTrue(warnings.contains("\"reductionPair\""));
            assertTrue(warnings.contains("\"hookPrint\""));
            assertTrue(warnings.contains("\"reducton_X\""));
            assertTrue(warnings.contains("reduction, reduction_*, or hook_*"));
            assertFalse(warnings.contains("myHelper"));
        }
    }

    @Nested
    class IsolationTests {
        @Test
        void missingArtifactNamesPathCodeAndBuildHint() {
            String missing = "/tmp/galley-java-no-such-dir-7f3a/libgalley-java.so";
            MissingArtifactException ex = assertThrows(MissingArtifactException.class,
                    () -> Galley.load(missing));
            assertEquals("galley:missing-artifact", ex.getCode());
            assertInstanceOf(FileNotFoundException.class, ex);
            assertTrue(ex.getMessage().contains(missing));
            assertTrue(ex.getMessage().contains("GalleyBuild <language-dir>"));
        }

        @Test
        void loadCachesByCanonicalPath() throws Exception {
            String path = fixtureLibraryPath();
            Parser first = Galley.load(path);
            try {
                assertSame(first, Galley.load(path));
                assertSame(first, Galley.load(Path.of(path).toRealPath().toString()));
                assertSame(first, Galley.load());
                Path dir = Files.createTempDirectory("galley-java-symlink");
                Path link = dir.resolve("fixture-link");
                Files.createSymbolicLink(link, Path.of(path));
                try {
                    assertSame(first, Galley.load(link.toString()));
                } finally {
                    Files.deleteIfExists(link);
                    Files.deleteIfExists(dir);
                }
            } finally {
                first.clearProcedures();
            }
        }

        @Test
        void parsersOnDifferentPathsDoNotShareHooks() throws Exception {
            Parser first = Galley.load(fixtureLibraryPath());
            Path dir = Files.createTempDirectory("galley-java-isolation");
            Path copy = dir.resolve(Path.of(fixtureLibraryPath()).getFileName());
            Files.copy(Path.of(fixtureLibraryPath()), copy);
            Parser second = Galley.load(copy.toString());
            try {
                assertNotSame(first, second);
                AtomicInteger firstCalls = new AtomicInteger(0);
                AtomicInteger secondCalls = new AtomicInteger(0);
                first.installProcedure("reduction_Pair", args -> firstCalls.incrementAndGet());
                second.installProcedure("reduction_Pair", args -> secondCalls.incrementAndGet());
                assertNotNull(first.lookupProcedure("reduction_Pair"));
                assertNotNull(second.lookupProcedure("reduction_Pair"));
                assertNull(first.lookupProcedure("reduction_Never"));
                try (Session a = first.openSession(); Session b = second.openSession()) {
                    a.parse("alpha:12,beta:3");
                    b.parse("alpha:1");
                }
                assertEquals(2, firstCalls.get());
                assertEquals(1, secondCalls.get());
                first.clearProcedures();
                assertNull(first.lookupProcedure("reduction_Pair"));
                assertNotNull(second.lookupProcedure("reduction_Pair"));
            } finally {
                first.clearProcedures();
                second.clearProcedures();
                Files.deleteIfExists(copy);
                Files.deleteIfExists(dir);
            }
        }
    }
}
