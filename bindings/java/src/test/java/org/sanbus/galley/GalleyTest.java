package org.sanbus.galley;

import org.junit.jupiter.api.*;
import org.junit.jupiter.api.function.Executable;
import static org.junit.jupiter.api.Assertions.*;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.PrintStream;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.math.BigInteger;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Stream;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
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

    /** Full signature — declaring class, member name, parameter types. */
    private static String signatureOf(Class<?> declaring, String name, Class<?>[] parameters) {
        return declaring.getName() + "#" + name + "("
                + String.join(",", Arrays.stream(parameters).map(Class::getName).toList()) + ")";
    }

    /** A node-address parameter: primitive, boxed, or arbitrary precision. */
    private static boolean isAddressShaped(Class<?> type) {
        return type == long.class || type == Long.class || type == BigInteger.class;
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
            session.installProcedure("reduction_Pair", args -> {
                Node node = args.currentNode();
                assertNotNull(node);
                byte[] text = node.text();
                assertNotNull(text);
                assertTrue(text.length > 0);
                seen.add(text);
            });
            session.parse("alpha:12,beta:3");
            assertEquals(2, seen.size());
        }

        @Test
        void nestedParseOfAnotherSessionUsesItsOwnHooks() {
            List<String> outerSeen = new ArrayList<>();
            List<String> innerSeen = new ArrayList<>();
            boolean[] nested = {false};
            session.installProcedure("reduction_Pair", args -> {
                Node node = args.currentNode();
                assertNotNull(node);
                outerSeen.add(new String(node.text(), StandardCharsets.UTF_8));
                if (!nested[0]) {
                    nested[0] = true;
                    try (Session innerSession = parser.openSession()) {
                        innerSession.installProcedure("reduction_Number", innerArgs -> {
                            Node innerNode = innerArgs.currentNode();
                            assertNotNull(innerNode);
                            innerSeen.add(new String(innerNode.text(), StandardCharsets.UTF_8));
                        });
                        innerSession.parse("alpha:9");
                    }
                }
            });
            session.parse("alpha:12,beta:3");
            // The inner parse neither fired the outer hook nor disturbed it.
            assertEquals(List.of("alpha:12", "beta:3"), outerSeen);
            assertEquals(List.of("9"), innerSeen);
        }

        @Test
        void hookThreadReadsWhileEveryOtherThreadIsRefused() throws Exception {
            // Establish a parse result: the refusal below is then the gate
            // itself, not the no-result default.
            session.parse("alpha:1");
            List<Boolean> hookReads = new ArrayList<>();
            List<Boolean> sameThreadReads = new ArrayList<>();
            List<StatusCode> refusals = new ArrayList<>();
            session.installProcedure("reduction_Pair", args -> {
                Node node = args.currentNode();
                hookReads.add(node != null && node.text() != null);
                // Called on the thread running the hook, the node crosses
                // the parse's hook door and reads.
                try {
                    session.variableIndex(node);
                    sameThreadReads.add(true);
                } catch (GalleyException e) {
                    sameThreadReads.add(false);
                }
                // The same call from any other thread crosses the session
                // door, which the core refuses while the parse holds the
                // session.
                Thread other = new Thread(() -> {
                    try {
                        session.variableIndex(node);
                        refusals.add(null);
                    } catch (GalleyException e) {
                        refusals.add(e.getCode());
                    }
                });
                other.start();
                try {
                    other.join();
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                }
            });
            try {
                session.parse("alpha:12,beta:3");
            } finally {
                session.clearProcedures();
            }
            assertEquals(List.of(true, true), hookReads);
            assertEquals(List.of(true, true), sameThreadReads);
            assertEquals(List.of(StatusCode.ERROR_SESSION_IN_USE, StatusCode.ERROR_SESSION_IN_USE), refusals);
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
            session.installProcedure("reduction_Number", args -> {
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
            session.installProcedure("reduction_Number", args -> {
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
        void everyPublicClassExposesNoRawAddressParameters() throws Exception {
            // Java's enforcement is compile time, so reflection proves it
            // holds for every public class of the package: every public
            // method and constructor with a `long`, boxed `Long` or
            // `BigInteger` parameter is a raw address unless its full
            // signature — class, member name, parameter types — is
            // sanctioned, so a new `long` overload of an allowed name, or
            // the same address widened into a box, fails.
            Set<String> sanctioned = Set.of(
                    "org.sanbus.galley.DiagnosticKind#fromCode(long)",
                    "org.sanbus.galley.Galley#statusString(long)",
                    "org.sanbus.galley.ParserType#fromCode(long)",
                    "org.sanbus.galley.RecoveryMode#fromCode(long)",
                    "org.sanbus.galley.RecoveryTarget#fromCode(long)",
                    "org.sanbus.galley.ResumeSide#fromCode(long)",
                    "org.sanbus.galley.Session#reserveNodes(long)",
                    "org.sanbus.galley.Session#symbolNameAt(long)",
                    "org.sanbus.galley.Session#symbolNameAtBytes(long)",
                    "org.sanbus.galley.Session#symbolIsTerminal(long)",
                    "org.sanbus.galley.Session#variableNameAt(long)",
                    "org.sanbus.galley.Session#variableNameAtBytes(long)",
                    "org.sanbus.galley.Session#statusString(long)",
                    "org.sanbus.galley.SessionOptions$Builder#astPreallocationCap(long)",
                    "org.sanbus.galley.StatusCode#fromCode(long)",
                    "org.sanbus.galley.TreeSnapshot#node(long)");

            // Scan the package's own classes from its class directory, so a
            // new public class joins the check without touching this test.
            Path packageDirectory = Paths.get(
                            Session.class.getProtectionDomain().getCodeSource().getLocation().toURI())
                    .resolve("org/sanbus/galley");
            assertTrue(Files.isDirectory(packageDirectory),
                    "package classes not found at " + packageDirectory);
            List<Class<?>> classes = new ArrayList<>();
            try (Stream<Path> entries = Files.list(packageDirectory)) {
                for (Path entry : entries.toList()) {
                    String fileName = entry.getFileName().toString();
                    if (!fileName.endsWith(".class") || !Files.isRegularFile(entry)) continue;
                    String binaryName = fileName.substring(0, fileName.length() - ".class".length());
                    Class<?> type = Class.forName("org.sanbus.galley." + binaryName);
                    if (Modifier.isPublic(type.getModifiers())) classes.add(type);
                }
            }
            assertTrue(classes.contains(Session.class) && classes.contains(TreeSnapshot.class),
                    "scan found " + classes.size() + " public classes, missing the API");

            Set<Class<?>> scanned = Set.copyOf(classes);
            for (Class<?> type : classes) {
                for (Method method : type.getMethods()) {
                    if (!scanned.contains(method.getDeclaringClass())) continue;
                    for (Class<?> parameter : method.getParameterTypes()) {
                        if (!isAddressShaped(parameter)) continue;
                        String signature = signatureOf(method.getDeclaringClass(), method.getName(),
                                method.getParameterTypes());
                        assertTrue(sanctioned.contains(signature), "raw address parameter: " + signature);
                    }
                }
                // Public constructors, same rule and the same allowlist,
                // keyed `Class#<init>(parameter types)`.
                for (Constructor<?> constructor : type.getConstructors()) {
                    for (Class<?> parameter : constructor.getParameterTypes()) {
                        if (!isAddressShaped(parameter)) continue;
                        String signature = signatureOf(type, "<init>", constructor.getParameterTypes());
                        assertTrue(sanctioned.contains(signature), "raw address parameter: " + signature);
                    }
                }
            }
            assertThrows(NoSuchMethodException.class, () -> Session.class.getMethod("nodeValid", long.class));
            assertThrows(NoSuchMethodException.class, () -> Session.class.getMethod("text", long.class));
            assertThrows(NoSuchMethodException.class, () -> Session.class.getMethod("text", Long.class));
            assertThrows(NoSuchMethodException.class, () -> Session.class.getMethod("text", BigInteger.class));
            assertThrows(NoSuchMethodException.class, () -> Session.class.getMethod("walk", long.class, boolean.class));
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
        void nullNodeAccessorsReturnEmpty() {
            assertNull(session.symbolName(null));
            assertNull(session.text(null));
            assertNull(session.span(null));
            assertNull(session.lineColumn(null));
            assertNull(session.variableIndex(null));
            assertEquals(0, session.childCount(null));
        }

        @Test
        void walkMatchesHandRolledRecursion() {
            session.parse("alpha:12,beta:3");
            Node root = session.rootNode();
            assertNotNull(root);
            List<long[]> expected = new ArrayList<>();
            collectRecursive(root, 0, expected);
            assertTrue(expected.size() > 1);
            Walker walker = session.walk(root, false);
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
                Node at = snap.node(address);
                assertNotNull(at);
                Node parent = session.parent(at);
                assertEquals(parent == null ? -1L : parent.getAddress(), snap.parent()[slot]);
                Node first = session.firstChild(at);
                assertEquals(first == null ? -1L : first.getAddress(), snap.firstChild()[slot]);
                Node next = session.nextSibling(at);
                assertEquals(next == null ? -1L : next.getAddress(), snap.next()[slot]);
                assertEquals(session.childCount(at), snap.childCount()[slot]);
                Integer variable = session.variableIndex(at);
                assertEquals(variable == null ? -1L : variable.longValue(), snap.variable()[slot]);
                long[] span = session.span(at);
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
            Walker walker = session.walk(root, false);
            assertNotNull(walker);
            List<Long> walked = new ArrayList<>();
            for (Walker.WalkStep step : walker) walked.add(step.node.getAddress());
            assertEquals(preorder, walked);
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
            Walker walker = session.walk(root, false);
            assertNotNull(walker);
            assertTrue(walker.hasNext());
            Walker.WalkStep first = walker.next();
            assertEquals(root.getAddress(), first.node.getAddress());
            assertEquals(0, first.depth);
            walker.skipChildren();
            assertFalse(walker.hasNext());
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
            // skipChildren is a pure host-side state write: staleness is the
            // next step's answer, not this one's.
            walker.skipChildren();
            assertThrows(GenerationInvalidatedException.class, walker::next);
            Node fresh = session.rootNode();
            assertNotNull(fresh);
            Walker rewound = session.walk(fresh, false);
            assertNotNull(rewound);
            assertTrue(rewound.hasNext());
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
            GalleyClosedException closed = assertThrows(GalleyClosedException.class, walker::next);
            assertEquals("walker's session", closed.getObjectName());
            assertThrows(GalleyClosedException.class, walker::skipChildren);
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
            Node fresh = session.rootNode();
            assertNotNull(fresh);
            Walker rewound = session.walk(fresh, false);
            assertNotNull(rewound);
            int steps = 0;
            while (rewound.hasNext()) {
                rewound.next();
                steps++;
            }
            assertTrue(steps > 1);
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
        }

        @Test
        void hookWalkPrunesSemanticErrorSubtrees() {
            // Error marks exist only in the in-flight tree: a semantic-failed
            // parse publishes nothing, so a walk inside the final hook is the
            // binding-side view that prunes a marked subtree where the plain
            // walk yields it.
            session.installProcedure("reduction_Number", args -> {
                Node node = args.currentNode();
                assertNotNull(node);
                int value = Integer.parseInt(new String(node.text(), StandardCharsets.UTF_8));
                if (value > 99) args.reportSemanticError("value out of range");
            });
            List<long[]> full = new ArrayList<>();
            List<long[]> pruned = new ArrayList<>();
            session.installProcedure("reduction_Document", args -> {
                Node node = args.currentNode();
                assertNotNull(node);
                for (Walker.WalkStep step : session.walk(node, false))
                    full.add(new long[]{step.node.getAddress(), step.depth, step.isSemanticError ? 1 : 0});
                for (Walker.WalkStep step : session.walk(node, true))
                    pruned.add(new long[]{step.node.getAddress(), step.depth});
            });
            GalleyException ex = assertThrows(GalleyException.class,
                    () -> session.parse("alpha:1,beta:2000"));
            assertEquals(StatusCode.ERROR_SEMANTIC, ex.getCode());
            assertFalse(full.isEmpty());
            List<Long> flagged = new ArrayList<>();
            for (long[] row : full) if (row[2] == 1) flagged.add(row[0]);
            assertFalse(flagged.isEmpty());          // the plain walk saw a mark
            assertTrue(pruned.size() < full.size()); // and the pruned walk dropped it
            List<Long> prunedAddresses = new ArrayList<>();
            for (long[] row : pruned) prunedAddresses.add(row[0]);
            for (long address : flagged) assertFalse(prunedAddresses.contains(address));
        }

        @Test
        void walkerStepDuringAParseReportsInUse() throws Exception {
            // The parse holds the session exclusively: a step from another
            // thread mid-parse is refused as in use, never a silent stop.
            Node root = session.rootNode();
            assertNotNull(root);
            Walker walker = session.walk(root, false);
            assertTrue(walker.hasNext());
            walker.next();
            CountDownLatch firstHookDone = new CountDownLatch(1);
            CountDownLatch probesDone = new CountDownLatch(1);
            List<StatusCode> codes = new ArrayList<>();
            session.installProcedure("reduction_Pair", args -> {
                if (firstHookDone.getCount() > 0) {
                    firstHookDone.countDown();
                    try {
                        assertTrue(probesDone.await(30, TimeUnit.SECONDS));
                    } catch (InterruptedException interrupted) {
                        Thread.currentThread().interrupt();
                    }
                }
            });
            Thread parseThread = new Thread(() -> session.parse("alpha:12,beta:3"));
            parseThread.start();
            try {
                assertTrue(firstHookDone.await(30, TimeUnit.SECONDS));
                codes.add(assertThrows(GalleyException.class, walker::next).getCode());
            } finally {
                probesDone.countDown();
                parseThread.join(TimeUnit.SECONDS.toMillis(30));
            }
            session.clearProcedures();
            assertEquals(List.of(StatusCode.ERROR_SESSION_IN_USE), codes);
        }

        @Test
        void walkStepAfterRemovingCurrentNodeThrows() {
            Node root = session.rootNode();
            assertNotNull(root);
            Walker walker = session.walk(root, false);
            Node leaf = null;
            while (walker.hasNext()) {
                Walker.WalkStep step = walker.next();
                if (step.depth >= 1 && session.childCount(step.node) == 0) {
                    leaf = step.node;
                    break;
                }
            }
            assertNotNull(leaf);
            session.removeSelf(leaf);
            // The step has no live position to advance from: invalid node,
            // and the cursor never moves past the failure.
            assertEquals(StatusCode.ERROR_INVALID_NODE,
                    assertThrows(GalleyException.class, walker::next).getCode());
            assertThrows(GalleyException.class, walker::next);
        }

        @Test
        void walkStepsSeeEditsBetweenSteps() {
            Node root = session.rootNode();
            assertNotNull(root);
            List<long[]> baseline = new ArrayList<>();
            for (Walker.WalkStep step : session.walk(root, false))
                baseline.add(new long[]{step.node.getAddress(), step.depth});
            assertTrue(baseline.size() > 1);

            Walker walker = session.walk(root, false);
            Walker.WalkStep first = walker.next();
            assertEquals(root.getAddress(), first.node.getAddress());
            Node removed = session.firstChild(root);
            assertNotNull(removed);
            assertEquals(baseline.get(1)[0], removed.getAddress());
            Node head = session.removeSelf(removed);
            assertNotNull(head);
            // The remainder follows the live links: the removed subtree —
            // and only it — is gone from the sequence.
            int skip = 2;
            while (skip < baseline.size() && baseline.get(skip)[1] > baseline.get(1)[1]) skip++;
            List<long[]> remaining = new ArrayList<>();
            while (walker.hasNext()) {
                Walker.WalkStep step = walker.next();
                remaining.add(new long[]{step.node.getAddress(), step.depth});
            }
            assertEquals(baseline.size() - skip, remaining.size());
            for (int i = 0; i < remaining.size(); i++)
                assertArrayEquals(baseline.get(skip + i), remaining.get(i));
            // Re-inserting the removed subtree brings it back into the walk.
            session.appendChildren(root, head);
            int restored = 0;
            boolean sawRemoved = false;
            for (Walker.WalkStep step : session.walk(root, false)) {
                if (step.node.getAddress() == removed.getAddress()) sawRemoved = true;
                restored++;
            }
            assertEquals(baseline.size(), restored);
            assertTrue(sawRemoved);
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
        void snapshotNodeBelongsToTheSnapshotParse() {
            TreeSnapshot snap = session.snapshot();
            Node root = session.rootNode();
            assertNotNull(root);
            Node node = snap.node(root.getAddress());
            assertEquals(root, node);
            Node first = session.firstChild(node);
            assertNotNull(first);
            long firstAddress = snap.firstChild()[(int) root.getAddress()];
            assertEquals(first.getAddress(), firstAddress);
            assertEquals(first, snap.node(firstAddress));
            // An absent node link answers null, never a node.
            assertNull(snap.node(Galley.INVALID_NODE));
            // The columns never follow a later parse: node() keeps answering
            // for its own parse, and that node reads as invalidated.
            assertEquals(7, session.parse("alpha:1"));
            assertEquals(node, snap.node(root.getAddress()));
            assertInvalidated(node::text);
            Node fresh = session.rootNode();
            assertNotNull(fresh);
            assertNotEquals(node, fresh);
            assertNotNull(fresh.text());
        }

        @Test
        void snapshotNodeOutOfRangeThrows() {
            TreeSnapshot snap = session.snapshot();
            assertTrue(snap.count() > 0);
            assertThrows(IndexOutOfBoundsException.class, () -> snap.node(snap.count()));
            assertThrows(IndexOutOfBoundsException.class, () -> snap.node(-2));
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
            session.installProcedure("reduction_Pair", args -> {
                try {
                    args.setCurrentNode(args.currentNode());
                } catch (Throwable t) {
                    seen.set(t);
                }
            });
            session.parse("alpha:12,beta:3");
            assertNull(seen.get());
            // A node left over from an older generation throws.
            Consumer<ProcedureArguments> useFresh = args -> {
                try {
                    args.setCurrentNode(fresh);
                } catch (Throwable t) {
                    seen.set(t);
                }
            };
            session.clearProcedures();
            session.installProcedure("reduction_Pair", useFresh);
            session.parse("alpha:12,beta:3");
            assertTrue(seen.get() instanceof GenerationInvalidatedException);
            // A handle of another session is refused as such, whichever
            // generation the other session is in.
            seen.set(null);
            try (Session other = parser.openSession()) {
                other.installProcedure("reduction_Pair", useFresh);
                other.parse("alpha:12,beta:3");
            }
            assertTrue(seen.get() instanceof IllegalArgumentException);
        }
    }

    @Nested
    class GenerationTests {
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

        private List<Node> stashPairsWhileParsing(String text) {
            List<Node> stashed = new ArrayList<>();
            session.installProcedure("reduction_Pair", args -> stashed.add(args.currentNode()));
            try {
                session.parse(text);
            } finally {
                session.clearProcedures();
            }
            return stashed;
        }

        @Test
        void refusedParseLeavesRunningHookNodesAndThePublishedTreeValid() throws Exception {
            // The core refuses a parse of a session that is already parsing
            // and changes nothing: a node stashed by hook 1 still reads in
            // hook 2, and the tree the running parse publishes is readable
            // afterwards.
            AtomicReference<Node> stashed = new AtomicReference<>();
            CountDownLatch firstHookDone = new CountDownLatch(1);
            CountDownLatch refusedParseDone = new CountDownLatch(1);
            List<String> laterReads = new ArrayList<>();
            session.installProcedure("reduction_Pair", args -> {
                if (stashed.get() == null) {
                    stashed.set(args.currentNode());
                    firstHookDone.countDown();
                    try {
                        assertTrue(refusedParseDone.await(30, TimeUnit.SECONDS));
                    } catch (InterruptedException interrupted) {
                        Thread.currentThread().interrupt();
                    }
                } else {
                    laterReads.add(new String(stashed.get().text(), StandardCharsets.UTF_8));
                }
            });
            AtomicInteger parsed = new AtomicInteger();
            Thread worker = new Thread(() -> parsed.set(session.parse("alpha:12,beta:3")));
            worker.start();
            try {
                assertTrue(firstHookDone.await(30, TimeUnit.SECONDS));
                GalleyException refusal = assertThrows(GalleyException.class, () -> session.parse("gamma:1"));
                assertEquals(StatusCode.ERROR_SESSION_IN_USE, refusal.getCode());
            } finally {
                refusedParseDone.countDown();
                worker.join(30_000);
            }
            assertEquals(15, parsed.get());
            assertEquals(List.of("alpha:12"), laterReads);
            Node root = session.rootNode();
            assertNotNull(root);
            assertEquals("alpha:12,beta:3", new String(session.text(root), StandardCharsets.UTF_8));
            assertEquals("alpha:12", new String(stashed.get().text(), StandardCharsets.UTF_8));
        }

        @Test
        void hookThatParsesItsOwnSessionIsRefusedAndKeepsItsNodes() {
            List<StatusCode> refusals = new ArrayList<>();
            List<String> reads = new ArrayList<>();
            AtomicReference<Node> stashed = new AtomicReference<>();
            session.installProcedure("reduction_Pair", args -> {
                if (stashed.get() == null) {
                    stashed.set(args.currentNode());
                    try {
                        session.parse("gamma:1");
                    } catch (GalleyException e) {
                        refusals.add(e.getCode());
                    }
                }
                reads.add(new String(stashed.get().text(), StandardCharsets.UTF_8));
            });
            session.parse("alpha:12,beta:3");
            assertEquals(List.of(StatusCode.ERROR_SESSION_IN_USE), refusals);
            assertEquals(List.of("alpha:12", "alpha:12"), reads);
            assertEquals("alpha:12", new String(stashed.get().text(), StandardCharsets.UTF_8));
        }

        @Test
        void hookNodeAfterASuccessfulParseReadsThroughTheSession() {
            List<Node> stashed = stashPairsWhileParsing("alpha:12,beta:3");
            assertEquals(2, stashed.size());
            Node first = stashed.get(0);
            assertEquals("alpha:12", new String(first.text(), StandardCharsets.UTF_8));
            assertEquals("alpha:12", new String(session.text(first), StandardCharsets.UTF_8));
            assertEquals(first.childCount(), session.childCount(first));
            Node found = null;
            Walker walker = session.walk(session.rootNode(), false);
            for (Walker.WalkStep step : walker) {
                if (step.node.getAddress() == first.getAddress()) {
                    found = step.node;
                    break;
                }
            }
            assertNotNull(found);
            assertEquals(found, first);
            assertEquals(found.hashCode(), first.hashCode());
            assertEquals("session", Map.of(found, "session").get(first));
        }

        @Test
        void hookNodeOfAFailedParseIsRefusedAfterwards() {
            List<Node> stashed = new ArrayList<>();
            session.installProcedure("reduction_Number", args -> stashed.add(args.currentNode()));
            assertThrows(GalleyException.class, () -> session.parse("alpha:12,beta:"));
            assertFalse(stashed.isEmpty());
            assertThrows(GenerationInvalidatedException.class, () -> stashed.get(0).text());
            assertThrows(GenerationInvalidatedException.class, () -> session.text(stashed.get(0)));
            session.clearProcedures();
            session.parse("alpha:12,beta:3");
            assertThrows(GenerationInvalidatedException.class, () -> stashed.get(0).text());
        }

        @Test
        void hookNodeUsedFromAnotherThreadIsRefusedBySessionDoor() throws Exception {
            // The hook door is ungated, so it is reachable only from the
            // thread running the hook. Any other thread crosses the session
            // door, which the core refuses while the parse runs.
            AtomicReference<Node> stashed = new AtomicReference<>();
            CountDownLatch firstHookDone = new CountDownLatch(1);
            CountDownLatch probesDone = new CountDownLatch(1);
            List<StatusCode> probeCodes = new ArrayList<>();
            session.installProcedure("reduction_Pair", args -> {
                if (stashed.get() == null) {
                    stashed.set(args.currentNode());
                    firstHookDone.countDown();
                    try {
                        assertTrue(probesDone.await(30, TimeUnit.SECONDS));
                    } catch (InterruptedException interrupted) {
                        Thread.currentThread().interrupt();
                    }
                }
            });
            Thread worker = new Thread(() -> session.parse("alpha:12,beta:3"));
            worker.start();
            try {
                assertTrue(firstHookDone.await(30, TimeUnit.SECONDS));
                Node node = stashed.get();
                for (Executable probe : List.<Executable>of(
                        node::text, node::children, () -> session.text(node), node::cleanChildren)) {
                    GalleyException refusal = assertThrows(GalleyException.class, probe);
                    probeCodes.add(refusal.getCode());
                }
            } finally {
                probesDone.countDown();
                worker.join(30_000);
            }
            assertEquals(List.of(StatusCode.ERROR_SESSION_IN_USE, StatusCode.ERROR_SESSION_IN_USE,
                    StatusCode.ERROR_SESSION_IN_USE, StatusCode.ERROR_SESSION_IN_USE), probeCodes);
            assertEquals("alpha:12", new String(stashed.get().text(), StandardCharsets.UTF_8));
        }

        @Test
        void nodeOfAnEarlierParseIsNotTheNodeAtTheSameAddress() {
            session.parse("alpha:12");
            Node firstRoot = session.rootNode();
            session.parse("alpha:12");
            Node secondRoot = session.rootNode();
            assertNotNull(firstRoot);
            assertNotNull(secondRoot);
            assertEquals(firstRoot.getAddress(), secondRoot.getAddress());
            assertNotEquals(firstRoot, secondRoot);
            assertEquals(2, java.util.Set.of(firstRoot, secondRoot).size());
            assertThrows(GenerationInvalidatedException.class, firstRoot::text);
            assertEquals("alpha:12", new String(secondRoot.text(), StandardCharsets.UTF_8));
        }

        @Test
        void walkInsideAHookEqualsThePostParseWalk() {
            // A walk created and stepped inside a hook goes through the
            // parse's own door over the in-flight tree; replayed after the
            // parse publishes from the same roots, each yields the
            // identical sequence.
            List<List<long[]>> recorded = new ArrayList<>();
            List<Node> hookRoots = new ArrayList<>();
            session.installProcedure("reduction_Pair", args -> {
                Node node = args.currentNode();
                assertNotNull(node);
                hookRoots.add(node);
                List<long[]> steps = new ArrayList<>();
                for (Walker.WalkStep step : session.walk(node, false))
                    steps.add(new long[]{step.node.getAddress(), step.depth});
                recorded.add(steps);
            });
            session.parse("alpha:12,beta:3");
            session.clearProcedures();
            assertFalse(recorded.isEmpty());
            for (int i = 0; i < hookRoots.size(); i++) {
                List<long[]> replayed = new ArrayList<>();
                for (Walker.WalkStep step : session.walk(hookRoots.get(i), false))
                    replayed.add(new long[]{step.node.getAddress(), step.depth});
                List<long[]> expected = recorded.get(i);
                assertEquals(expected.size(), replayed.size());
                for (int k = 0; k < expected.size(); k++)
                    assertArrayEquals(expected.get(k), replayed.get(k));
            }
            // walk() always hands back a walker, never null.
            assertNotNull(session.walk(session.rootNode(), false));
        }

        @Test
        void nodeEqualityIgnoresTheDoor() {
            List<Node> stashed = stashPairsWhileParsing("alpha:12");
            Node pair = session.firstChild(session.firstChild(session.rootNode()));
            assertEquals(stashed.get(0), pair);
            assertEquals(stashed.get(0).hashCode(), pair.hashCode());
        }
    }

    @Nested
    class FixtureHookTests {
        Session session;
        Parser parser;

        @BeforeEach
        void setUp() {
            parser = fixtureParser();
            test_fixture.procedures.register(parser);
            session = parser.openSession();
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
        void editsRefuseNodesFromAnotherSession() {
            // A node crosses as a bare address and the native side only
            // bounds-checks it, so a node from another session would alias
            // whatever node holds that index here. Every entry that takes a
            // node refuses one from another session, not only the Node
            // convenience methods.
            Session other = parser.openSession();
            try {
                other.parse("alpha:12");
                Node otherRoot = other.rootNode();
                assertNotNull(otherRoot);
                assertThrows(IllegalArgumentException.class, () -> root.appendChildren(otherRoot));
                assertThrows(IllegalArgumentException.class, () -> otherRoot.appendChildren(root));
                assertThrows(IllegalArgumentException.class, () -> session.appendChildren(root, otherRoot));
                assertThrows(IllegalArgumentException.class, () -> session.insertBefore(root, otherRoot));
                assertThrows(IllegalArgumentException.class, () -> session.insertAfter(root, otherRoot));
                assertThrows(IllegalArgumentException.class, () -> session.insertChildrenAt(root, 0, otherRoot));
                assertThrows(IllegalArgumentException.class, () -> session.text(otherRoot));
                assertThrows(IllegalArgumentException.class, () -> other.appendChildren(otherRoot, root));
            } finally {
                other.close();
            }
            // A hook's node handed to the session from inside that hook is
            // this session's node on the running parse, so it reads.
            AtomicInteger reads = new AtomicInteger();
            session.installProcedure("reduction_Pair", args -> {
                session.variableIndex(args.currentNode());
                reads.incrementAndGet();
            });
            try {
                session.parse("alpha:12,beta:3");
            } finally {
                session.clearProcedures();
            }
            assertEquals(2, reads.get());
        }

        @Test
        void hookRefusesNodesOfAnEarlierParse() {
            // A node of the previous parse against a node of the running
            // parse, both directions; the refusal must fire inside the hook.
            AtomicInteger refusals = new AtomicInteger();
            session.installProcedure("reduction_Pair", args -> {
                Node hookNode = args.currentNode();
                assertNotNull(hookNode);
                try {
                    root.appendChildren(hookNode);
                } catch (GenerationInvalidatedException expected) {
                    refusals.incrementAndGet();
                }
                try {
                    hookNode.appendChildren(root);
                } catch (GenerationInvalidatedException expected) {
                    refusals.incrementAndGet();
                }
            });
            try {
                session.parse("alpha:12,beta:3");
            } finally {
                session.clearProcedures();
            }
            assertEquals(4, refusals.get());
        }

        @Test
        void chainDetachedInOneHookAttachesInALaterHook() {
            // A chain detached in one hook can be attached in a later hook
            // of the same parse: both nodes carry the running parse's
            // generation.
            AtomicReference<Node> detached = new AtomicReference<>();
            List<String> outcomes = new ArrayList<>();
            session.installProcedure("reduction_Pair", args -> {
                Node node = args.currentNode();
                assertNotNull(node);
                if (detached.get() == null) {
                    detached.set(node.cleanChildren());
                    return;
                }
                try {
                    node.appendChildren(detached.get());
                    outcomes.add("ok");
                } catch (RuntimeException error) {
                    outcomes.add(error.toString());
                }
            });
            try {
                session.parse("alpha:12,beta:3");
            } finally {
                session.clearProcedures();
            }
            assertEquals(List.of("ok"), outcomes);
        }

        @Test
        void hookNodesOutliveTheirHookAndTheirParse() {
            // The tree belongs to the parse, not to the hook that handed out
            // a node: a node stashed by one hook stays usable from a later
            // hook of the same parse, after the parse succeeds, and refuses
            // only once the session parses again.
            AtomicReference<Node> stashed = new AtomicReference<>();
            List<String> seen = new ArrayList<>();
            session.installProcedure("reduction_Pair", args -> {
                if (stashed.get() == null) stashed.set(args.currentNode());
            });
            session.installProcedure("reduction_Document", args -> {
                seen.add(new String(stashed.get().text(), StandardCharsets.UTF_8));
            });
            try {
                session.parse("alpha:12,beta:3");
            } finally {
                session.clearProcedures();
            }
            assertEquals(List.of("alpha:12"), seen);
            assertEquals("alpha:12", new String(stashed.get().text(), StandardCharsets.UTF_8));
            session.parse("gamma:7");
            assertThrows(GenerationInvalidatedException.class, () -> stashed.get().text());
        }

        @Test
        void procedureArgumentsDieWithTheirHook() {
            // The arguments carry per-hook state (current node, position,
            // drop and replace). A reference stashed past its hook refuses
            // instead of touching a frame that is gone.
            AtomicReference<ProcedureArguments> stashed = new AtomicReference<>();
            List<Class<?>> outcomes = new ArrayList<>();
            session.installProcedure("reduction_Pair", args -> {
                if (stashed.get() == null) stashed.set(args);
            });
            session.installProcedure("reduction_Document", args -> {
                for (Runnable use : List.<Runnable>of(
                        () -> stashed.get().currentLine(),
                        () -> stashed.get().currentNode(),
                        () -> stashed.get().dropIfEmpty())) {
                    try {
                        use.run();
                    } catch (GalleyClosedException error) {
                        outcomes.add(error.getClass());
                    }
                }
            });
            try {
                session.parse("alpha:12,beta:3");
            } finally {
                session.clearProcedures();
            }
            assertEquals(3, outcomes.size());
            assertTrue(outcomes.stream().allMatch(GenerationInvalidatedException.class::equals));
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
                // A session starts with a copy of the parser's defaults.
                assertEquals(2, sess.listProcedures().size());
                sess.parse("alpha:12,beta:3");
                assertTrue(called.get() > 0);
                int before = called.get();
                sess.clearProcedures();
                assertEquals(0, sess.listProcedures().size());
                assertEquals(2, parser.listProcedures().size());
                sess.parse("alpha:12");
                assertEquals(before, called.get());
            } finally {
                sess.close();
            }
        }

        @Test
        void sessionsOwnTheirHooks() {
            AtomicInteger firstCalls = new AtomicInteger(0);
            AtomicInteger secondCalls = new AtomicInteger(0);
            try (Session first = parser.openSession(); Session second = parser.openSession()) {
                first.installProcedure("reduction_Pair", args -> firstCalls.incrementAndGet());
                second.installProcedure("reduction_Number", args -> secondCalls.incrementAndGet());
                first.parse("alpha:12,beta:3");
                assertEquals(2, firstCalls.get());
                assertEquals(0, secondCalls.get());
                second.parse("alpha:12,beta:3");
                assertEquals(2, firstCalls.get());
                assertEquals(2, secondCalls.get());
                assertNotNull(first.lookupProcedure("reduction_Pair"));
                assertNull(first.lookupProcedure("reduction_Number"));
                assertNull(second.lookupProcedure("reduction_Pair"));
            }
        }

        @Test
        void parserInstallsReachOnlyLaterSessions() {
            AtomicInteger called = new AtomicInteger(0);
            try (Session earlier = parser.openSession()) {
                parser.installProcedure("reduction_Pair", args -> called.incrementAndGet());
                try (Session later = parser.openSession()) {
                    earlier.parse("alpha:12,beta:3");
                    assertEquals(0, called.get());
                    later.parse("alpha:12,beta:3");
                    assertEquals(2, called.get());
                    parser.clearProcedures();
                    later.parse("alpha:12,beta:3");
                    assertEquals(4, called.get());
                }
            }
        }

        @Test
        void changingHooksDuringAParseIsRefused() {
            AtomicReference<Throwable> refusal = new AtomicReference<>();
            try (Session sess = parser.openSession()) {
                sess.installProcedure("reduction_Pair", args -> {
                    try {
                        sess.installProcedure("reduction_Number", innerArgs -> {});
                    } catch (Throwable t) {
                        refusal.compareAndSet(null, t);
                    }
                    try {
                        sess.clearProcedures();
                    } catch (Throwable t) {
                        refusal.compareAndSet(null, t);
                    }
                });
                sess.parse("alpha:12");
                assertTrue(refusal.get() instanceof GalleyException);
                assertEquals(StatusCode.ERROR_SESSION_IN_USE, ((GalleyException) refusal.get()).getCode());
                // The refused changes left the table as it was.
                assertEquals(1, sess.listProcedures().size());
                assertNotNull(sess.lookupProcedure("reduction_Pair"));
            }
        }

        @Test
        void sessionInstallsFollowTheSameNamingRules() {
            PrintStream original = System.err;
            ByteArrayOutputStream captured = new ByteArrayOutputStream();
            System.setErr(new PrintStream(captured, true, StandardCharsets.UTF_8));
            try (Session sess = parser.openSession()) {
                sess.installProcedure("reduction_Pair", args -> {});
                sess.installProcedure("reductionPair", args -> {});
                assertEquals(1, sess.installProcedures(Map.of(
                        "hook_print", (Runnable) () -> {},
                        "myHelper", (Runnable) () -> {})));
                assertEquals(2, sess.listProcedures().size());
                assertNull(sess.lookupProcedure("reductionPair"));
            } finally {
                System.setErr(original);
            }
            String warnings = captured.toString(StandardCharsets.UTF_8);
            assertTrue(warnings.contains("\"reductionPair\""));
            assertFalse(warnings.contains("myHelper"));
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
