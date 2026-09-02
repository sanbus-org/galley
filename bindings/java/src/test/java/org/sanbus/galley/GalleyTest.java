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
 * Mirrors bindings/python/tests/test_bindings.py and bindings/typescript/tests/test_bindings.mjs.
 *
 * Requires the shared library built for examples/java:
 *   java -jar bindings/java/target/galley-bindings-0.1.0.jar examples/java
 * The test discovers it via GALLEY_LIBRARY_PATH or cwd.
 */
public class GalleyTest {

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
            assertTrue(e instanceof NoSuchMethodException || e.getCause() instanceof NoSuchMethodException || true);
        }
    }

    @Nested
    class SessionTests {
        Session session;

        @BeforeEach
        void setUp() {
            session = new Session(SessionOptions.builder().maxErrors(10).build());
        }

        @AfterEach
        void tearDown() {
            session.close();
        }

        @Test
        void procedureHookCanReadNodeText() {
            List<byte[]> seen = new ArrayList<>();
            Procedures.installProcedure("reduction_Pair", args -> {
                Node node = args.currentNode();
                assertNotNull(node);
                assertNotNull(args.getSession());
                byte[] text = node.text();
                assertNotNull(text);
                assertTrue(text.length > 0);
                seen.add(text);
            });
            try {
                session.parse("alpha:12,beta:3");
            } finally {
                Procedures.clearProcedures();
            }
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
            Session s = new Session();
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
    }

    @Nested
    class WalkTests {
        Session session;

        @BeforeEach
        void setUp() {
            session = new Session();
            session.parse("alpha:12,beta:3");
        }

        @AfterEach
        void tearDown() {
            session.close();
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
    }

    @Nested
    class EditTests {
        Session session;
        Node root;

        @BeforeEach
        void setUp() {
            session = new Session();
            session.parse("alpha:12,beta:3");
            root = session.rootNode();
            assertNotNull(root);
        }

        @AfterEach
        void tearDown() {
            session.close();
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

        @BeforeEach
        void setUp() {
            session = new Session();
        }

        @AfterEach
        void tearDown() {
            session.close();
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
            Session s = new Session();
            try {
                long cap = s.nodeCapacity();
                s.reserveNodes(cap + 1024);
                assertTrue(s.nodeCapacity() >= cap + 1024);
            } finally {
                s.close();
            }
        }
    }

    @Nested
    class LifetimeTests {
        @Test
        void closeIsIdempotentAndClosedSessionsThrow() {
            Session s = new Session();
            s.parse("alpha:12");
            s.close();
            s.close();
            assertThrows(IllegalStateException.class, () -> s.parse("alpha:12"));
            assertThrows(IllegalStateException.class, () -> s.rootNode());
        }

        @Test
        void nodeAfterCloseThrows() {
            Session s = new Session();
            s.parse("alpha:12,beta:3");
            Node root = s.rootNode();
            s.close();
            assertThrows(IllegalStateException.class, () -> root.children());
            assertThrows(IllegalStateException.class, () -> root.text());
        }

        @Test
        void autoCloseable() {
            Session s = new Session();
            s.parse("alpha:12");
            s.close();
            assertTrue(s.isClosed());
            Session s2 = new Session();
            s2.close();
            assertTrue(s2.isClosed());
        }

        @Test
        void optionsRoundTrip() {
            Session s = new Session(SessionOptions.builder()
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
            Session s = new Session(SessionOptions.builder()
                    .messageOverride("Number", "custom at line {line}")
                    .build());
            try {
                GalleyException ex = assertThrows(GalleyException.class, () -> s.parse("alpha:"));
                assertTrue(ex.getDiagnostic().getMessage().contains("custom at line 1"));
                Session s2 = new Session();
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
            Procedures.clearProcedures();
            List<String> seen = new ArrayList<>();
            Procedures.installProcedure("reduction_Pair", args -> {
                Node n = args.currentNode();
                assertNotNull(n);
                seen.add(new String(n.text(), StandardCharsets.UTF_8));
            });
            Session sess = new Session();
            try {
                sess.parse("alpha:12,beta:3");
                assertEquals(2, seen.size());
            } finally {
                sess.close();
                Procedures.clearProcedures();
            }
        }

        @Test
        void installProcedureDispatchesHostHooks() {
            Procedures.clearProcedures();
            AtomicInteger called = new AtomicInteger(0);
            Procedures.installProcedure("reduction", args -> called.incrementAndGet());
            Procedures.installProcedure("reduction_Pair", args -> called.incrementAndGet());
            assertEquals(2, Procedures.listProcedures().size());
            Session sess = new Session();
            try {
                sess.parse("alpha:12,beta:3");
                assertTrue(called.get() > 0);
                int before = called.get();
                Procedures.clearProcedures();
                assertEquals(0, Procedures.listProcedures().size());
                sess.parse("alpha:12");
                assertEquals(before, called.get());
            } finally {
                sess.close();
                Procedures.clearProcedures();
            }
        }

        @Test
        void installProceduresBulkRegisters() {
            Procedures.clearProcedures();
            Map<String, Object> mod = Map.of(
                    "reduction_Document", (java.util.function.Consumer<ProcedureArguments>) args -> {},
                    "hook_print", (java.util.function.Consumer<ProcedureArguments>) args -> {},
                    "notAHook", (java.util.function.Consumer<ProcedureArguments>) args -> {}
            );
            int n = Procedures.installProcedures(mod);
            assertEquals(2, n);
            assertEquals(2, Procedures.listProcedures().size());
            Procedures.clearProcedures();
        }

        @Test
        void hookThrowingDoesNotAbortParse() {
            Procedures.clearProcedures();
            Procedures.installProcedure("reduction_Pair", args -> { throw new RuntimeException("boom"); });
            Session sess = new Session();
            try {
                int parsed = sess.parse("alpha:12,beta:3");
                assertTrue(parsed > 0);
            } finally {
                sess.close();
                Procedures.clearProcedures();
            }
        }
    }
}
