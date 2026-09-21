package org.sanbus.galley;

import org.junit.jupiter.api.*;
import static org.junit.jupiter.api.Assertions.*;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

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
        Parser parser = Galley.load(fixtureLibraryPath());
        parser.clearProcedures();
        return parser;
    }

    @Test
    void versionReturnsNonEmptyString() {
        String v = Galley.version();
        assertNotNull(v);
        assertFalse(v.isEmpty());
    }

    @Test
    void parserMetadataFlagsAreConsistent() {
        int pt = Galley.parserType();
        assertTrue(pt == Galley.PARSER_TYPE_LL || pt == Galley.PARSER_TYPE_LR);
        assertTrue(Galley.hasAst());
        // boolean flags
        assertNotNull(Galley.hasProcedures());
        assertNotNull(Galley.allowsNoAstTreeProcedures());
        assertNotNull(Galley.sourceRetentionEnabled());
        assertNotNull(Galley.hasPositionTracking());
        assertNotNull(Galley.hasInputStreaming());
        assertNotNull(Galley.usesVerbatim());
        assertNotNull(Galley.stackOverflowRecoveryAvailable());
        int rm = Galley.errorRecoveryMode();
        assertTrue(rm == Galley.RECOVERY_MODE_DISABLED || rm == Galley.RECOVERY_MODE_AUTOMATIC || rm == Galley.RECOVERY_MODE_EXPLICIT);
    }

    @Test
    void statusStringRendersKnownCodes() {
        String rendered = Galley.statusString(-2);
        assertNotNull(rendered);
        assertTrue(rendered.toLowerCase().contains("syntax"));
        assertNull(Galley.statusString(999999));
    }

    @Test
    void diagnosticTypeIsNotDirectlyConstructible() {
        // Diagnostic is a plain data holder; ensure it requires args
        // This mirrors Python's test that Diagnostic() raises TypeError – in Java we expect no no-arg constructor
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
        void syntaxErrorRaisesWithCodeAndDiagnostic() {
            GalleyException ex = assertThrows(GalleyException.class, () -> session.parse("alpha:"));
            assertEquals(-2, ex.getCode());
            Diagnostic d = ex.getDiagnostic();
            assertNotNull(d);
            assertTrue(session.hasDiagnostic());
            assertNotNull(session.diagnostic());
            assertEquals(Diagnostic.KIND_SYNTAX, d.getKind());
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
        void fileParsingReportsEndPosition() throws Exception {
            Path p = Path.of("/tmp/galley-java-bindings-test.kv");
            Files.writeString(p, "alpha:12,beta:3", StandardCharsets.UTF_8);
            int parsed = session.parseFile(p.toString());
            assertEquals(15, parsed);
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
            assertEquals(-12, ex.getCode());
            assertTrue(ex.getMessage().contains("value out of range"));
            assertEquals(List.of(1, 2), counts);
            Diagnostic d = session.diagnostic();
            assertNotNull(d);
            assertEquals(Diagnostic.KIND_SEMANTIC, d.getKind());
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
            assertArrayEquals("Document".getBytes(StandardCharsets.UTF_8), session.symbolName(root));
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
            assertArrayEquals("Document".getBytes(StandardCharsets.UTF_8), root.symbolName());
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
            byte[] sym = session.symbolName(node);
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
        void symbolAndVariableTables() {
            assertTrue(Galley.symbolCount() > 0);
            assertTrue(Galley.variableCount() > 0);
            byte[] firstName = session.symbolNameAt(0);
            assertNotNull(firstName);
            assertNotNull(session.symbolIsTerminal(0));
            byte[] varName = session.variableNameAt(0);
            assertNotNull(varName);
            assertNull(session.symbolNameAt(1_000_000_000L));
            assertNull(session.variableNameAt(1_000_000_000L));
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
            assertThrows(IllegalStateException.class, () -> s.parse("alpha:12"));
            assertThrows(IllegalStateException.class, () -> s.rootNode());
        }

        @Test
        void nodeAfterCloseThrows() {
            Session s = parser.openSession();
            s.parse("alpha:12,beta:3");
            Node root = s.rootNode();
            s.close();
            assertThrows(IllegalStateException.class, () -> root.children());
            assertThrows(IllegalStateException.class, () -> root.text());
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
    }

    @Nested
    class IsolationTests {
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
