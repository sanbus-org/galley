package org.sanbus.galley;

import org.junit.jupiter.api.*;
import org.junit.jupiter.api.function.Executable;
import static org.junit.jupiter.api.Assertions.*;

import org.sanbus.galley.internal.GalleyLibraryLoader;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
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
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
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
 * The suite locates that file itself; a missing fixture is a loud error
 * naming its path, never a search.
 */
public class GalleyTest {

    /** A hook class for the method scan: two hooks, a helper and a misspelled hook. */
    public static final class ScannedHooks {
        static final List<String> calls = new ArrayList<>();

        public static void reduction_Pair(ProcedureArguments args) {
            calls.add(args.currentNode() != null ? "Pair" : "Pair without node");
        }

        public static void hook_print() {
            calls.add("print");
        }

        public static void reductionTypo(ProcedureArguments args) {}

        public static int helper() {
            return 0;
        }
    }

    /** A scanned hook whose method declares a checked exception. */
    public static final class CheckedFailureHooks {
        static final java.io.IOException failure = new java.io.IOException("checked failure");

        public static void reduction_Pair(ProcedureArguments args) throws java.io.IOException {
            throw failure;
        }
    }

    /** A hook-named method whose signature no hook can have. */
    public static final class MisdeclaredHooks {
        public static void reduction_Pair(String text) {}
    }

    private static String fixtureLibraryPath() {
        return FixtureLibrary.path("test-fixture");
    }

    private static Parser fixtureParser() {
        try {
            return Galley.load(fixtureLibraryPath());
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
        String v = fixtureParser().version();
        assertNotNull(v);
        assertFalse(v.isEmpty());
    }

    @Test
    void parserMetadataFlagsAreConsistent() throws Exception {
        Parser parser = fixtureParser();
        assertEquals(ParserType.LL, parser.parserType());
        assertTrue(parser.hasAst());
        // boolean flags
        assertNotNull(parser.hasProcedures());
        assertNotNull(parser.allowsNoAstTreeProcedures());
        assertNotNull(parser.sourceRetentionEnabled());
        assertNotNull(parser.hasPositionTracking());
        assertNotNull(parser.hasInputStreaming());
        assertNotNull(parser.usesVerbatim());
        assertNotNull(parser.stackOverflowRecoveryAvailable());
        RecoveryMode rm = parser.errorRecoveryMode();
        assertTrue(rm == RecoveryMode.DISABLED || rm == RecoveryMode.AUTOMATIC || rm == RecoveryMode.EXPLICIT);
        assertEquals(0, ParserType.LL.getCode());
        assertEquals(1, ParserType.LR.getCode());
        assertEquals(ParserType.UNKNOWN, ParserType.fromCode(999));
        assertEquals(RecoveryMode.UNKNOWN, RecoveryMode.fromCode(999));
    }

    @Test
    void statusStringRendersKnownCodes() throws Exception {
        Parser parser = fixtureParser();
        String rendered = parser.statusString(StatusCode.ERROR_SYNTAX);
        assertNotNull(rendered);
        assertTrue(rendered.toLowerCase().contains("syntax"));
        assertEquals(StatusCode.UNKNOWN, StatusCode.fromCode(999999));
        assertNull(parser.statusString(StatusCode.fromCode(999999)));
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
        void closeIsRefusedWhileACallIsInFlight() throws Exception {
            // galley_parse_file opens the file before the core takes its
            // lease, so a named pipe with no writer leaves the parse holding
            // only this binding's count: nothing is locked in the core, and
            // the refusal below is the count's alone. Nothing outside the
            // binding can see that window — a writer's appearance ends it —
            // so the count is what tells us the claim exists; close runs
            // only after it reads 1. Both threads are daemons and every
            // join has a deadline, so a red assertion reports instead of
            // hanging the suite on the blocked pipe.
            Path directory = Files.createTempDirectory("galley-java-inflight");
            Path fifo = directory.resolve("input.kv");
            Process mkfifo = new ProcessBuilder("mkfifo", fifo.toString())
                    .redirectErrorStream(true).start();
            Assumptions.assumeTrue(mkfifo.waitFor(30, TimeUnit.SECONDS) && mkfifo.exitValue() == 0,
                    "no mkfifo on this platform");
            AtomicInteger outcome = new AtomicInteger(-1);
            CountDownLatch started = new CountDownLatch(1);
            Thread parser = new Thread(() -> {
                started.countDown();
                outcome.set(session.parseFile(fifo.toString()));
            });
            parser.setDaemon(true);
            parser.start();
            try {
                assertTrue(started.await(30, TimeUnit.SECONDS));
                long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(30);
                while (session.inFlightCount() < 1) {
                    if (System.nanoTime() > deadline) fail("the parse never claimed the session");
                    Thread.sleep(1);
                }
                GalleyException refusal = assertThrows(GalleyException.class, session::close);
                assertEquals(StatusCode.ERROR_SESSION_IN_USE, refusal.getCode());
                assertFalse(session.isClosed());
                assertEquals(-1, outcome.get(), "the parse was not in flight");
            } finally {
                Thread writer = new Thread(() -> {
                    try {
                        Files.write(fifo, "alpha:12,beta:3".getBytes(StandardCharsets.UTF_8));
                    } catch (IOException unwritable) {
                        // No reader arrived: the test's own assertion, not
                        // this cleanup, is what reports.
                    }
                });
                writer.setDaemon(true);
                writer.start();
                writer.join(30_000);
                parser.join(30_000);
                try {
                    Files.deleteIfExists(fifo);
                    Files.deleteIfExists(directory);
                } catch (IOException uncleaned) {
                    // Temp-directory cleanup is not the test's claim.
                }
            }

            // The count covered the whole call, so the parse finished on a
            // live session and the close it was refused for now goes through.
            assertEquals(15, outcome.get());
            session.close();
            assertTrue(session.isClosed());
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
            // No validity probe: a real read is the answer, and it reads.
            assertTrue(session.childCount(root) > 0);
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
                    "org.sanbus.galley.Parser#statusString(long)",
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
        void nullNodeAccessorsRejectTheMissingArgument() {
            // A null handle is a missing argument, not an empty answer: an
            // empty read here would be indistinguishable from "no children".
            for (Executable read : new Executable[]{
                    () -> session.symbolName(null),
                    () -> session.text(null),
                    () -> session.span(null),
                    () -> session.lineColumn(null),
                    () -> session.variableIndex(null),
                    () -> session.childCount(null),
                    () -> session.parent(null),
                    () -> session.children(null),
            }) {
                assertThrows(NullPointerException.class, read);
            }
        }

        @Test
        void walkMatchesHandRolledRecursion() {
            session.parse("alpha:12,beta:3");
            Node root = session.rootNode();
            assertNotNull(root);
            List<long[]> expected = new ArrayList<>();
            collectRecursive(root, 0, expected);
            assertTrue(expected.size() > 1);
            Walker walker = root.walk(false, false);
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
        void sessionHasNoWalkMethod() {
            for (java.lang.reflect.Method method : Session.class.getDeclaredMethods()) {
                assertNotEquals("walk", method.getName());
            }
            assertDoesNotThrow(() -> Node.class.getMethod("walk", boolean.class, boolean.class));
        }

        @Test
        void walkFromANonRootNodeYieldsItsSubtreeWithRelativeDepths() {
            session.parse("alpha:12,beta:3");
            Node root = session.rootNode();
            assertNotNull(root);
            Node pairList = root.firstChild();
            assertNotNull(pairList);
            Node pair = pairList.firstChild();
            assertNotNull(pair);
            assertNotEquals(root, pair);
            List<long[]> expected = new ArrayList<>();
            collectRecursive(pair, 0, expected);
            List<long[]> walked = new ArrayList<>();
            for (Walker.WalkStep step : pair.walk(false, false)) {
                walked.add(new long[]{step.node.getAddress(), step.depth});
            }
            assertTrue(expected.size() > 1);
            assertEquals(expected.size(), walked.size());
            for (int i = 0; i < expected.size(); i++) {
                assertArrayEquals(expected.get(i), walked.get(i));
            }
            assertArrayEquals(new long[]{pair.getAddress(), 0}, walked.get(0));
            // A strict subtree: the full walk from the root visits more.
            int full = 0;
            for (Walker.WalkStep ignored : root.walk(false, false)) full++;
            assertTrue(walked.size() < full);
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
                assertEquals(parent == null ? Galley.INVALID_NODE : parent.getAddress(), snap.parent()[slot]);
                Node first = session.firstChild(at);
                assertEquals(first == null ? Galley.INVALID_NODE : first.getAddress(), snap.firstChild()[slot]);
                Node next = session.nextSibling(at);
                assertEquals(next == null ? Galley.INVALID_NODE : next.getAddress(), snap.next()[slot]);
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
                while (child != Galley.INVALID_NODE) {
                    chain.add(child);
                    child = snap.next()[(int) child];
                }
                assertEquals(chain.size(), snap.childCount()[(int) node]);
                for (int k = chain.size() - 1; k >= 0; k--) stack.add(chain.get(k));
            }
            Walker walker = root.walk(false, false);
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
            Walker walker = root.walk(false, false);
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
            Walker walker = root.walk(false, false);
            assertNotNull(walker);
            assertTrue(walker.hasNext());
            walker.next();
            assertEquals(15, session.parse("alpha:12,beta:3"));
            StaleTreeException stale = assertThrows(StaleTreeException.class, walker::next);
            assertEquals(StatusCode.ERROR_STALE_TREE, stale.getCode());
            // skipChildren is a pure host-side state write: staleness is the
            // next step's answer, not this one's.
            walker.skipChildren();
            assertThrows(StaleTreeException.class, walker::next);
            Node fresh = session.rootNode();
            assertNotNull(fresh);
            Walker rewound = fresh.walk(false, false);
            assertNotNull(rewound);
            assertTrue(rewound.hasNext());
        }

        @Test
        void completedWalkerThrowsStaleTreeAfterAReparse() {
            Node root = session.rootNode();
            assertNotNull(root);
            Walker walker = root.walk(false, false);
            int steps = 0;
            while (walker.hasNext()) {
                walker.next();
                steps++;
            }
            assertTrue(steps > 0);
            // A finished walk is still answered by the core, which says
            // "done" only while the walker's tree is live: it belongs to the
            // parse of the tree it was created over, finished or not.
            assertFalse(walker.hasNext());
            assertEquals(15, session.parse("alpha:12,beta:3"));
            assertThrows(StaleTreeException.class, walker::hasNext);
            assertThrows(StaleTreeException.class, walker::next);
        }

        @Test
        void walkerStepAfterSessionCloseThrows() {
            Node root = session.rootNode();
            assertNotNull(root);
            Walker walker = root.walk(false, false);
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
            Walker walker = root.walk(false, false);
            assertNotNull(walker);
            // Parsing never throws merely because a walker is open; the
            // abandoned walker fails at its next step instead.
            assertEquals(15, session.parse("alpha:12,beta:3"));
            assertThrows(StaleTreeException.class, walker::next);
            Node fresh = session.rootNode();
            assertNotNull(fresh);
            Walker rewound = fresh.walk(false, false);
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
            Walker walker = root.walk(false, false);
            assertNotNull(walker);
            assertTrue(walker.hasNext());
            walker.next();
            assertThrows(GalleyException.class, () -> session.parse("alpha:"));
            assertThrows(StaleTreeException.class, walker::next);
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
                for (Walker.WalkStep step : node.walk(false, false))
                    full.add(new long[]{step.node.getAddress(), step.depth, step.isSemanticError ? 1 : 0});
                for (Walker.WalkStep step : node.walk(true, false))
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
            Walker walker = root.walk(false, false);
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
            Walker walker = root.walk(false, false);
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
            for (Walker.WalkStep step : root.walk(false, false))
                baseline.add(new long[]{step.node.getAddress(), step.depth});
            assertTrue(baseline.size() > 1);

            Walker walker = root.walk(false, false);
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
            for (Walker.WalkStep step : root.walk(false, false)) {
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

        private static void assertStale(Executable read) {
            assertThrows(StaleTreeException.class, read);
        }

        @Test
        void nodeReadsAfterReparseThrow() {
            Node stale = session.rootNode();
            assertNotNull(stale);
            Node staleChild = stale.firstChild();
            assertNotNull(staleChild);
            assertEquals(7, session.parse("alpha:1"));
            // Every Node accessor family throws instead of reading stale storage.
            assertStale(stale::text);
            assertStale(stale::symbolName);
            assertStale(stale::symbolNameBytes);
            assertStale(stale::span);
            assertStale(stale::lineColumn);
            assertStale(stale::parent);
            assertStale(stale::firstChild);
            assertStale(stale::children);
            assertStale(stale::childCount);
            assertStale(stale::variableIndex);
            assertStale(() -> stale.at(0));
            assertStale(stale::iterator);
            assertStale(stale::cleanChildren);
            assertStale(() -> stale.appendChildren(staleChild));
            // A walk binds its cursor to this node's generation; the refusal
            // arrives at its first step, which is where the core checks.
            assertStale(() -> stale.walk(false, false).next());
            // Session crossings that take the handle throw too.
            assertStale(() -> session.text(stale));
            assertStale(() -> session.symbolName(stale));
            assertStale(() -> session.span(stale));
            assertStale(() -> session.childCount(stale));
            assertStale(() -> session.children(stale));
            assertStale(() -> session.parent(stale));
            assertStale(() -> session.cleanChildren(stale));
            assertStale(() -> session.appendChildren(stale, staleChild));
            assertStale(() -> session.insertBefore(stale, staleChild));
            assertStale(() -> session.insertChildrenAt(stale, 0, staleChild));
            assertStale(() -> session.removeChildrenAt(stale, 0, 1));
            assertStale(() -> session.removeSiblings(stale, 1));
            assertStale(() -> session.removeSelf(stale));
            // Fresh handles from the new generation read fine.
            Node fresh = session.rootNode();
            assertNotNull(fresh);
            assertNotNull(fresh.text());
        }

        @Test
        void editMixingTwoGenerationsThrows() {
            Node oldChild = session.rootNode().firstChild();
            assertEquals(7, session.parse("alpha:1"));
            Node freshRoot = session.rootNode();
            // Each node crosses with its own generation and the core refuses a
            // pair from two parses; the host compares nothing.
            assertStale(() -> session.appendChildren(freshRoot, oldChild));
            assertStale(() -> session.insertBefore(freshRoot, oldChild));
            assertStale(() -> session.insertAfter(freshRoot, oldChild));
            assertStale(() -> session.insertChildrenAt(freshRoot, 0, oldChild));
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
            // Every address and the sentinel are non-negative: only statuses are negative.
            assertEquals(Long.MAX_VALUE, Galley.INVALID_NODE);
            assertEquals(Long.MAX_VALUE, Galley.NO_VARIABLE);
            // The columns never follow a later parse: node() keeps answering
            // for its own parse, and that node reads as stale.
            assertEquals(7, session.parse("alpha:1"));
            assertEquals(node, snap.node(root.getAddress()));
            assertStale(node::text);
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
            assertStale(stale::text);
            assertStale(() -> session.text(stale));
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
            assertTrue(seen.get() instanceof StaleTreeException);
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
    class NothingPublishedTests {
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

        private void assertNothingPublished(Session target) {
            // Root answers null, the one "nothing here" answer, and every
            // other session-door read, the input and the position included,
            // refuses rather than reporting a zero or an empty value.
            assertNull(target.rootNode());
            assertThrows(StaleTreeException.class, target::nodeCount);
            assertThrows(StaleTreeException.class, target::snapshot);
            assertThrows(StaleTreeException.class, target::lastInput);
            assertThrows(StaleTreeException.class, target::lastPosition);
        }

        @Test
        void rootIsTheProbeAndEverythingElseRefuses() {
            // Before any parse there is no tree.
            assertNothingPublished(session);
        }

        @Test
        void aParseThatPublishesNothingRefusesEverything() {
            // One error is the limit, so the parser raises instead of
            // recovering and the failing parse publishes nothing.
            try (Session strict = parser.openSession(SessionOptions.builder().maxErrors(1).build())) {
                strict.parse("alpha:12");
                assertArrayEquals("alpha:12".getBytes(StandardCharsets.UTF_8), strict.lastInput());
                assertThrows(GalleyException.class, () -> strict.parse("alpha:"));
                assertNothingPublished(strict);
            }
        }

        @Test
        void finishedParseQueriesAreRefusedInsideAHook() {
            // Inside a hook (this thread, this session) nothing that describes
            // a finished parse answers: not before the first parse publishes,
            // not with a tree published, never 0 or empty. "Session in use"
            // comes first and is not a stale tree.
            List<String> outcomes = new ArrayList<>();
            Map<String, Executable> reads = new java.util.LinkedHashMap<>();
            reads.put("nodeCapacity", session::nodeCapacity);
            reads.put("nodeCount", session::nodeCount);
            reads.put("snapshot", session::snapshot);
            reads.put("lastInput", session::lastInput);
            reads.put("lastPosition", session::lastPosition);
            reads.put("rootNode", session::rootNode);
            session.installProcedure("reduction_Document", args -> {
                for (Map.Entry<String, Executable> read : reads.entrySet()) {
                    try {
                        read.getValue().execute();
                        outcomes.add(read.getKey() + ":answered");
                    } catch (StaleTreeException stale) {
                        outcomes.add(read.getKey() + ":stale");
                    } catch (GalleyException refused) {
                        outcomes.add(read.getKey() + ":" + refused.getCode());
                    } catch (Throwable other) {
                        outcomes.add(read.getKey() + ":" + other);
                    }
                }
            });
            List<String> expected = new ArrayList<>();
            for (String name : reads.keySet()) expected.add(name + ":" + StatusCode.ERROR_SESSION_IN_USE);
            for (int attempt = 0; attempt < 2; attempt++) { // nothing published, then a tree
                outcomes.clear();
                session.parse("alpha:12,beta:3");
                assertEquals(expected, outcomes, "attempt " + attempt);
            }
            session.clearProcedures();
        }

        @Test
        void nodeCapacityAndFinishedParseQueriesAreRefusedWhileAnotherThreadParses() throws Exception {
            CountDownLatch entered = new CountDownLatch(1);
            CountDownLatch release = new CountDownLatch(1);
            session.installProcedure("reduction_Document", args -> {
                entered.countDown();
                try {
                    assertTrue(release.await(30, TimeUnit.SECONDS));
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                }
            });
            List<StatusCode> codes = new ArrayList<>();
            Thread parseThread = new Thread(() -> session.parse("alpha:12,beta:3"));
            parseThread.start();
            try {
                assertTrue(entered.await(30, TimeUnit.SECONDS));
                for (Executable read : new Executable[]{
                        session::nodeCapacity, session::nodeCount, session::snapshot,
                        session::lastInput, session::lastPosition}) {
                    codes.add(assertThrows(GalleyException.class, read).getCode());
                }
            } finally {
                release.countDown();
                parseThread.join(TimeUnit.SECONDS.toMillis(30));
                session.clearProcedures();
            }
            assertEquals(Collections.nCopies(5, StatusCode.ERROR_SESSION_IN_USE), codes);
        }

        @Test
        void useAfterCloseIsNotAStaleTree() {
            session.parse("alpha:12,beta:3");
            Node root = session.rootNode();
            assertNotNull(root);
            session.close();
            // The closed session has its own error: the tree being gone is a
            // different failure, and neither stands in for the other.
            for (Executable read : new Executable[]{
                    root::text, session::nodeCount, session::rootNode, session::snapshot}) {
                RuntimeException closed = assertThrows(RuntimeException.class, read);
                assertFalse(closed instanceof StaleTreeException,
                        () -> "expected the closed-session error, got " + closed);
            }
        }
    }


    /**
     * A parse that fails after running to its end publishes its tree:
     * semantic errors mark nodes, recovered syntax errors leave flagged nodes
     * over the damaged input, and {@code parse} still throws. A parse the
     * parser cannot recover from publishes nothing.
     */
    @Nested
    class PublishedFailureTests {
        /** Recovery skips {@code x,beta:} to resynchronize, then {@code 2}: two recovered nodes. */
        static final String RECOVERED = "alpha:x,beta:2";
        /** Parses, but a hook reports one semantic error on the Number {@code 2000}. */
        static final String SEMANTIC = "alpha:1,beta:2000";

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

        private List<Walker.WalkStep> steps(boolean skipSemanticErrors, boolean skipRecovered) {
            Node root = session.rootNode();
            assertNotNull(root);
            List<Walker.WalkStep> steps = new ArrayList<>();
            for (Walker.WalkStep step : root.walk(skipSemanticErrors, skipRecovered)) steps.add(step);
            return steps;
        }

        private String symbolOf(Walker.WalkStep step) {
            return session.symbolName(step.node);
        }

        @Test
        void aSemanticOnlyFailurePublishesItsTree() {
            session.installProcedure("reduction_Number", args -> {
                Node node = args.currentNode();
                assertNotNull(node);
                if (Integer.parseInt(new String(node.text(), StandardCharsets.UTF_8)) > 999) {
                    args.reportSemanticError("value out of range");
                }
            });
            GalleyException failure = assertThrows(GalleyException.class, () -> session.parse(SEMANTIC));
            assertEquals(StatusCode.ERROR_SEMANTIC, failure.getCode());

            List<Walker.WalkStep> full = steps(false, false);
            List<Walker.WalkStep> marked = full.stream().filter(step -> step.isSemanticError).toList();
            assertEquals(1, marked.size());
            assertEquals("Number", symbolOf(marked.get(0)));
            assertArrayEquals(new long[]{13, 4}, session.span(marked.get(0).node));
            assertTrue(full.stream().noneMatch(step -> step.isRecovered));

            List<Walker.WalkStep> pruned = steps(true, false);
            assertTrue(pruned.size() < full.size());
            assertTrue(pruned.stream().noneMatch(step -> step.isSemanticError));
            // Nothing is recovered, so skipping recovered nodes changes nothing.
            assertEquals(full.size(), steps(false, true).size());

            TreeSnapshot snapshot = session.snapshot();
            assertEquals(1, countTrue(snapshot.isSemanticError()));
            assertEquals(0, countTrue(snapshot.isRecovered()));
            assertArrayEquals(SEMANTIC.getBytes(StandardCharsets.UTF_8), session.lastInput());
            assertEquals(SEMANTIC.length() + 2, session.lastPosition()[1]);

            // The next parse retires the errored tree's nodes.
            Node stale = session.rootNode();
            assertNotNull(stale);
            session.parse("alpha:12,beta:3");
            assertThrows(StaleTreeException.class, stale::text);
        }

        @Test
        void aRecoveredSyntaxErrorPublishesItsTree() {
            GalleyException failure = assertThrows(GalleyException.class, () -> session.parse(RECOVERED));
            assertEquals(StatusCode.ERROR_SYNTAX, failure.getCode());

            List<Walker.WalkStep> full = steps(false, false);
            List<Walker.WalkStep> recovered = full.stream().filter(step -> step.isRecovered).toList();
            assertEquals(2, recovered.size());
            assertTrue(full.stream().noneMatch(step -> step.isSemanticError));
            // The damaged Number covers the input recovery skipped: x,beta:
            assertEquals("Number", symbolOf(recovered.get(0)));
            assertArrayEquals(new long[]{6, 7}, session.span(recovered.get(0).node));

            // Skipping them leaves only undamaged nodes, none inside the damage.
            List<Walker.WalkStep> undamaged = steps(false, true);
            assertEquals(full.size() - 2, undamaged.size());
            for (Walker.WalkStep step : undamaged) {
                assertFalse(step.isRecovered);
                long start = session.span(step.node)[0];
                assertTrue(start < 6 || start >= 13);
            }

            // The snapshot column reads what the walk reports, node for node.
            TreeSnapshot snapshot = session.snapshot();
            List<Long> flagged = new ArrayList<>();
            for (int i = 0; i < snapshot.isRecovered().length; i++) {
                if (snapshot.isRecovered()[i]) flagged.add((long) i);
            }
            assertEquals(recovered.stream().map(step -> step.node.getAddress()).toList(), flagged);

            assertArrayEquals(RECOVERED.getBytes(StandardCharsets.UTF_8), session.lastInput());
            assertNotNull(session.lastPosition());

            Node stale = session.rootNode();
            assertNotNull(stale);
            session.parse("alpha:12,beta:3");
            assertThrows(StaleTreeException.class, stale::text);
        }

        @Test
        void anUnrecoveredSyntaxErrorPublishesNothing() {
            // One error is the limit, so the parser raises instead of recovering.
            try (Session strict = parser.openSession(SessionOptions.builder().maxErrors(1).build())) {
                assertThrows(GalleyException.class, () -> strict.parse(RECOVERED));
                assertNull(strict.rootNode());
                assertThrows(StaleTreeException.class, strict::lastInput);
                assertThrows(StaleTreeException.class, strict::lastPosition);
                assertThrows(StaleTreeException.class, strict::nodeCount);
            }
        }

        @Test
        void lastInputAndPositionRefuseBeforeAnyParse() {
            assertThrows(StaleTreeException.class, session::lastInput);
            assertThrows(StaleTreeException.class, session::lastPosition);
        }

        @Test
        void aFailureWithoutARootStillPublishesItsInput() {
            // Recovery skips all of the input before the grammar's first
            // symbol: the parse publishes, but there is no tree to hold a root.
            assertThrows(GalleyException.class, () -> session.parse("?"));
            assertNull(session.rootNode());
            assertArrayEquals("?".getBytes(StandardCharsets.UTF_8), session.lastInput());
        }

        private int countTrue(boolean[] flags) {
            int count = 0;
            for (boolean flag : flags) if (flag) count++;
            return count;
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
            Walker walker = session.rootNode().walk(false, false);
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
        void hookNodeOfAParseThatPublishesNothingIsRefusedAfterwards() {
            // One error is the limit, so the failing parse raises instead of
            // recovering and publishes nothing: its nodes die with it.
            try (Session strict = parser.openSession(SessionOptions.builder().maxErrors(1).build())) {
                List<Node> stashed = new ArrayList<>();
                strict.installProcedure("reduction_Number", args -> stashed.add(args.currentNode()));
                assertThrows(GalleyException.class, () -> strict.parse("alpha:12,beta:"));
                assertFalse(stashed.isEmpty());
                assertThrows(StaleTreeException.class, () -> stashed.get(0).text());
                assertThrows(StaleTreeException.class, () -> strict.text(stashed.get(0)));
                strict.clearProcedures();
                strict.parse("alpha:12,beta:3");
                assertThrows(StaleTreeException.class, () -> stashed.get(0).text());
            }
        }

        @Test
        void hookNodeOfAPublishedFailureLivesUntilTheNextParse() {
            List<Node> stashed = new ArrayList<>();
            session.installProcedure("reduction_Number", args -> stashed.add(args.currentNode()));
            // The parser recovers from the missing Number, so the failure
            // publishes its tree and the nodes its hooks saw stay valid.
            assertThrows(GalleyException.class, () -> session.parse("alpha:12,beta:"));
            session.clearProcedures();
            assertFalse(stashed.isEmpty());
            assertArrayEquals("12".getBytes(StandardCharsets.UTF_8), stashed.get(0).text());
            session.parse("alpha:12,beta:3");
            assertThrows(StaleTreeException.class, () -> stashed.get(0).text());
        }

        @Test
        void hookNodeUsedFromAnotherThreadIsRefusedBySessionDoor() throws Exception {
            // The hook door takes no lock, so it is reachable only from the
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
            assertThrows(StaleTreeException.class, firstRoot::text);
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
                for (Walker.WalkStep step : node.walk(false, false))
                    steps.add(new long[]{step.node.getAddress(), step.depth});
                recorded.add(steps);
            });
            session.parse("alpha:12,beta:3");
            session.clearProcedures();
            assertFalse(recorded.isEmpty());
            for (int i = 0; i < hookRoots.size(); i++) {
                List<long[]> replayed = new ArrayList<>();
                for (Walker.WalkStep step : hookRoots.get(i).walk(false, false))
                    replayed.add(new long[]{step.node.getAddress(), step.depth});
                List<long[]> expected = recorded.get(i);
                assertEquals(expected.size(), replayed.size());
                for (int k = 0; k < expected.size(); k++)
                    assertArrayEquals(expected.get(k), replayed.get(k));
            }
            // walk() always hands back a walker, never null.
            assertNotNull(session.rootNode().walk(false, false));
        }

        @Test
        void nodeEqualityIgnoresTheDoor() {
            List<Node> stashed = stashPairsWhileParsing("alpha:12");
            Node pair = session.firstChild(session.firstChild(session.rootNode()));
            assertEquals(stashed.get(0), pair);
            assertEquals(stashed.get(0).hashCode(), pair.hashCode());
        }
    }

    /**
     * Text and input pointers the core returns are borrowed: valid until the
     * next parse (inside a hook, until it returns), and the session reuses two
     * buffers for its input, so the third parse after a read rewrites the
     * memory the read came from. Every accessor must copy before it returns;
     * each read below is kept across such parses and must still hold what it
     * held when it was made.
     */
    @Nested
    class BorrowedMemoryTests {
        static final String FIRST = "alpha:12,beta:3";
        // Same length as FIRST, so each one lands in a buffer FIRST used.
        static final String[] CHURN = {"qqqqq:88,wwww:7", "xxxxx:77,yyyy:6", "ppppp:66,rrrr:5"};
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

        private void churn() {
            for (String text : CHURN) session.parse(text);
        }

        @Test
        void nodeTextNamesAndInputAreCopies() {
            session.parse(FIRST);
            Node root = session.rootNode();
            assertNotNull(root);
            List<byte[]> texts = new ArrayList<>();
            List<byte[]> names = new ArrayList<>();
            Walker walker = root.walk(false, false);
            while (walker.hasNext()) {
                Node node = walker.next().node;
                texts.add(node.text());
                names.add(session.symbolNameBytes(node));
            }
            byte[] input = session.lastInput();
            churn();
            assertArrayEquals(CHURN[CHURN.length - 1].getBytes(StandardCharsets.UTF_8), session.lastInput());
            assertArrayEquals(FIRST.getBytes(StandardCharsets.UTF_8), input);
            assertArrayEquals(FIRST.getBytes(StandardCharsets.UTF_8), texts.get(0));
            assertTrue(texts.stream().anyMatch(text -> Arrays.equals(text, "alpha:12".getBytes(StandardCharsets.UTF_8))));
            assertTrue(texts.stream().anyMatch(text -> Arrays.equals(text, "beta:3".getBytes(StandardCharsets.UTF_8))));
            assertEquals(2, names.stream().filter(name -> Arrays.equals(name, "Pair".getBytes(StandardCharsets.UTF_8))).count());
        }

        @Test
        void hookTextIsACopy() {
            List<byte[]> seen = new ArrayList<>();
            session.installProcedure("reduction_Pair", args -> seen.add(args.currentNode().text()));
            session.parse(FIRST);
            churn();
            assertArrayEquals("alpha:12".getBytes(StandardCharsets.UTF_8), seen.get(0));
            assertArrayEquals("beta:3".getBytes(StandardCharsets.UTF_8), seen.get(1));
        }

        @Test
        void diagnosticsAreCopies() {
            GalleyException failure = assertThrows(GalleyException.class, () -> session.parse("alpha:"));
            Diagnostic frozen = failure.getDiagnostic();
            Diagnostic current = session.diagnostic();
            List<Diagnostic> recorded = session.diagnostics();
            assertNotNull(frozen);
            assertNotNull(current);
            List<String> before = fields(frozen, current, recorded);
            assertFalse(frozen.getExpectedTokens().isEmpty());
            // Failures of the same shape rewrite the input buffers and the
            // rendered message; successes release the diagnostic memory.
            for (String text : List.of("beta:?", "gamma:", FIRST, "delta:", FIRST)) {
                try {
                    session.parse(text);
                } catch (GalleyException expected) {
                    // a failing parse is the point
                }
            }
            assertEquals(before, fields(frozen, current, recorded));
        }

        private static List<String> fields(Diagnostic frozen, Diagnostic current, List<Diagnostic> recorded) {
            List<String> out = new ArrayList<>();
            List<Diagnostic> all = new ArrayList<>(List.of(frozen, current));
            all.addAll(recorded);
            for (Diagnostic diagnostic : all) {
                StringBuilder row = new StringBuilder();
                row.append(diagnostic.getMessage()).append('|').append(diagnostic.getMessageAnsi()).append('|');
                row.append(Arrays.toString(diagnostic.getUnexpectedToken())).append('|');
                for (byte[] token : diagnostic.getExpectedTokens()) row.append(Arrays.toString(token));
                row.append('|').append(diagnostic.getContext());
                row.append('|').append(Arrays.toString(diagnostic.getRecoveryTerminal()));
                out.add(row.toString());
            }
            return out;
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

        @Test
        void installingANameTheArtifactDoesNotDefineRaises() {
            IllegalArgumentException onParser = assertThrows(IllegalArgumentException.class,
                    () -> parser.installProcedure("reduction_Nonexistent", args -> {}));
            assertTrue(onParser.getMessage().contains("reduction_Nonexistent"), onParser.getMessage());
            assertTrue(onParser.getMessage().contains("does not define a hook of that name"), onParser.getMessage());
            assertFalse(onParser.getMessage().contains("did you mean"), onParser.getMessage());
            IllegalArgumentException annotation = assertThrows(IllegalArgumentException.class,
                    () -> parser.installProcedure("print", args -> {}));
            assertTrue(annotation.getMessage().contains("did you mean \"hook_print\"?"), annotation.getMessage());
            IllegalArgumentException symbol = assertThrows(IllegalArgumentException.class,
                    () -> session.installProcedure("Pair", args -> {}));
            assertTrue(symbol.getMessage().contains("did you mean \"reduction_Pair\"?"), symbol.getMessage());
            assertFalse(parser.listProcedures().containsKey("reduction_Nonexistent"));
            IllegalArgumentException onSession = assertThrows(IllegalArgumentException.class,
                    () -> session.installProcedure("helperFunction", args -> {}));
            assertTrue(onSession.getMessage().contains("helperFunction"), onSession.getMessage());
            assertFalse(session.listProcedures().containsKey("helperFunction"));
            assertThrows(IllegalArgumentException.class,
                    () -> session.installProcedure("helperFunction", (Runnable) () -> {}));
        }

        @Test
        void productionAndEscapedTerminalHooksFire() {
            List<String> fired = new ArrayList<>();
            session.clearProcedures();
            session.installProcedure("reduction_Pair_0", () -> fired.add("Pair_0"));
            session.installProcedure("reduction_terminal__x58", () -> fired.add(":"));
            session.installProcedure("reduction_generative_terminal_digit", () -> fired.add("digit"));
            session.parse("alpha:12,beta:3");
            assertEquals(2, fired.stream().filter("Pair_0"::equals).count());
            assertEquals(2, fired.stream().filter(":"::equals).count());
            assertEquals(3, fired.stream().filter("digit"::equals).count());
        }

        @Test
        void zigOnlySpellingsAndHelpersAreNotHooks() {
            for (String name : List.of("reduction_\":\"", "reduction_digit", "reduction__AugmentedStart")) {
                assertThrows(IllegalArgumentException.class, () -> parser.installProcedure(name, args -> {}), name);
            }
        }

        @Test
        void classScanInstallsTheHooksItsMethodsDefine() {
            parser.clearProcedures();
            PrintStream original = System.err;
            ByteArrayOutputStream buffer = new ByteArrayOutputStream();
            int installed;
            try {
                System.setErr(new PrintStream(buffer, true, StandardCharsets.UTF_8));
                installed = parser.installProcedures(ScannedHooks.class);
            } finally {
                System.setErr(original);
            }
            String err = buffer.toString(StandardCharsets.UTF_8);
            assertEquals(2, installed);
            assertEquals(Set.of("reduction_Pair", "hook_print"), parser.listProcedures().keySet());
            assertTrue(err.contains("\"reductionTypo\"") && err.contains("does not define it"), err);
            assertFalse(err.contains("helper"), err);

            ScannedHooks.calls.clear();
            Session scanned = parser.openSession();
            try {
                scanned.parse("alpha:12,beta:3");
            } finally {
                scanned.close();
            }
            assertEquals(List.of("print", "Pair", "print", "Pair"), ScannedHooks.calls);

            assertThrows(IllegalArgumentException.class, () -> parser.installProcedures(MisdeclaredHooks.class));
        }

        @Test
        void classScannedHookFailureKeepsItsCheckedCause() {
            Session scanned = parser.openSession();
            try {
                scanned.clearProcedures();
                assertEquals(1, scanned.installProcedures(CheckedFailureHooks.class));
                GalleyException failure = assertThrows(GalleyException.class, () -> scanned.parse("alpha:12"));
                assertEquals(StatusCode.ERROR_HOOK_FAILED, failure.getCode());
                assertSame(CheckedFailureHooks.failure, failure.getCause());
            } finally {
                scanned.close();
            }
        }

        @Test
        void scansConsiderOnlyHookShapedExports() {
            Map<String, Object> exports = new LinkedHashMap<>();
            exports.put("reduction_Pair", (Consumer<ProcedureArguments>) args -> {});
            exports.put("reductionPair", (Consumer<ProcedureArguments>) args -> {});
            exports.put("hookTypo", (Consumer<ProcedureArguments>) args -> {});
            exports.put("hooky", (Consumer<ProcedureArguments>) args -> {});
            exports.put("myHelper", (Consumer<ProcedureArguments>) args -> {});
            PrintStream original = System.err;
            ByteArrayOutputStream buffer = new ByteArrayOutputStream();
            int installed;
            try {
                System.setErr(new PrintStream(buffer, true, StandardCharsets.UTF_8));
                installed = parser.installProcedures(exports);
            } finally {
                System.setErr(original);
            }
            String err = buffer.toString(StandardCharsets.UTF_8);
            assertEquals(1, installed);
            assertTrue(err.contains("\"reductionPair\"") && err.contains("does not define it"), err);
            assertTrue(err.contains("\"hookTypo\"") && err.contains("does not define it"), err);
            assertFalse(err.contains("hooky"), err);
            assertFalse(err.contains("myHelper"), err);
            assertFalse(err.contains("reduction_Pair"), err);
        }
    }

    @Nested
    class DisabledArtifactTests {
        @Test
        void noProceduresArtifactBuildsAndRefusesEveryInstall() throws Exception {
            String checkout = System.getenv("GALLEY_CHECKOUT");
            assertNotNull(checkout, "GALLEY_CHECKOUT must name the checkout that builds fixtures");
            Path source = FixtureLibrary.directory("test-fixture");
            // The builder spells the Java package from the directory name
            // (test-fixture → test_fixture), so the copy keeps the name.
            Path work = Paths.get(System.getProperty("java.io.tmpdir"))
                    .resolve("galley-java-test").resolve("noprocs").resolve("test-fixture");
            Files.createDirectories(work.resolve("test_fixture"));
            Files.copy(source.resolve("config.zig"), work.resolve("config.zig"),
                    StandardCopyOption.REPLACE_EXISTING);
            Files.copy(source.resolve("ll.grm"), work.resolve("ll.grm"),
                    StandardCopyOption.REPLACE_EXISTING);
            Files.copy(source.resolve("test_fixture").resolve("procedures.java"),
                    work.resolve("test_fixture").resolve("procedures.java"),
                    StandardCopyOption.REPLACE_EXISTING);
            Path config = work.resolve("config.zig");
            String enabled = "pub const procedures = true;";
            String sourceText = Files.readString(config);
            assertTrue(sourceText.contains(enabled), config + " must declare the procedures default");
            Files.writeString(config, sourceText.replace(enabled, "pub const procedures = false;"));

            List<String> command = List.of(
                    Paths.get(System.getProperty("java.home"), "bin", "java").toString(),
                    "--enable-native-access=ALL-UNNAMED",
                    "-cp", System.getProperty("java.class.path"),
                    "org.sanbus.galley.build.GalleyBuild", work.toString());
            ProcessBuilder builder = new ProcessBuilder(command).redirectErrorStream(true);
            builder.environment().put("GALLEY_CHECKOUT", checkout);
            Process process = builder.start();
            String output = new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
            assertEquals(0, process.waitFor(), output);

            Path library = work.resolve(GalleyLibraryLoader.libFileName());
            assertTrue(Files.isRegularFile(library), "no built library at " + library);
            Parser parser = Galley.load(library.toString());
            assertEquals(0, parser.hookCount());
            IllegalArgumentException onParser = assertThrows(IllegalArgumentException.class,
                    () -> parser.installProcedure("reduction", args -> {}));
            assertTrue(onParser.getMessage().contains("defines no procedure hooks"), onParser.getMessage());
            Session session = parser.openSession();
            try {
                IllegalArgumentException onSession = assertThrows(IllegalArgumentException.class,
                        () -> session.installProcedure("reduction_Pair", args -> {}));
                assertTrue(onSession.getMessage().contains("defines no procedure hooks"), onSession.getMessage());
                assertTrue(session.parse("alpha:12") > 0);
            } finally {
                session.close();
            }
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
                } catch (StaleTreeException expected) {
                    refusals.incrementAndGet();
                }
                try {
                    hookNode.appendChildren(root);
                } catch (StaleTreeException expected) {
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
        void hookDoorRefusesANodeOfAnEarlierParseOnEveryCapability() {
            // The core checks the generation inside every hook-door call: a
            // node of the previous parse raises the one stale-tree error on a
            // read, a link, a count, an edit and a walk step, and nothing
            // answers null, while a node of the running parse still reads and
            // edits.
            List<String> outcomes = new ArrayList<>();
            List<String> live = new ArrayList<>();
            Node previousChild = root.firstChild();
            assertNotNull(previousChild);
            session.installProcedure("reduction_Pair", args -> {
                Node current = args.currentNode();
                assertNotNull(current);
                List<Runnable> calls = List.of(
                    () -> session.text(root),
                    () -> session.symbolNameBytes(root),
                    () -> session.span(root),
                    () -> session.lineColumn(root),
                    () -> session.variableIndex(root),
                    () -> session.firstChild(root),
                    () -> session.lastChild(root),
                    () -> session.nextSibling(root),
                    () -> session.priorSibling(root),
                    () -> session.parent(root),
                    () -> session.childCount(root),
                    () -> root.walk(false, false).next(),
                    () -> root.appendChildren(current),
                    () -> current.appendChildren(root),
                    // Both nodes of the previous parse: the host's own
                    // mixed-generation check passes, so the core's decides.
                    () -> root.appendChildren(previousChild),
                    () -> session.insertBefore(root, previousChild),
                    () -> session.insertAfter(root, previousChild),
                    () -> session.insertChildrenAt(root, 0, previousChild),
                    () -> session.removeSiblings(root, 1),
                    () -> session.removeChildrenAt(root, 0, 1),
                    () -> session.cleanChildren(root),
                    () -> session.removeSelf(root),
                    () -> args.setCurrentNode(root));
                for (Runnable call : calls) {
                    try {
                        call.run();
                        outcomes.add("answered");
                    } catch (StaleTreeException expected) {
                        outcomes.add("stale");
                    }
                }
                assertEquals(current, args.currentNode());
                args.setCurrentNode(current);
                assertEquals(current, args.currentNode());
                live.add(new String(current.text(), StandardCharsets.UTF_8));
                Node detached = current.cleanChildren();
                if (detached != null) current.appendChildren(detached);
            });
            try {
                session.parse("alpha:12,beta:3");
            } finally {
                session.clearProcedures();
            }
            assertEquals(Collections.nCopies(23 * 2, "stale"), outcomes);
            assertEquals(List.of("alpha:12", "beta:3"), live);
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
            assertThrows(StaleTreeException.class, () -> stashed.get().text());
        }

        @Test
        void procedureArgumentsDieWithTheirHook() {
            // The arguments carry per-hook state (current node, position,
            // drop and replace). The core refuses every call made with a hook
            // that has returned, from a later hook of the same parse and after
            // the parse alike; the object keeps no expiry flag of its own.
            AtomicReference<ProcedureArguments> stashed = new AtomicReference<>();
            AtomicReference<ProcedureArguments> last = new AtomicReference<>();
            AtomicReference<Node> lastNode = new AtomicReference<>();
            List<StatusCode> during = new ArrayList<>();
            session.installProcedure("reduction_Pair", args -> {
                if (stashed.get() == null) stashed.set(args);
            });
            session.installProcedure("reduction_Document", args -> {
                last.set(args);
                lastNode.set(args.currentNode());
                for (Runnable use : uses(stashed.get(), lastNode.get())) {
                    try {
                        use.run();
                    } catch (GalleyException error) {
                        during.add(error.getCode());
                        assertFalse(error instanceof StaleTreeException);
                    }
                }
            });
            try {
                session.parse("alpha:12,beta:3");
            } finally {
                session.clearProcedures();
            }
            int calls = uses(stashed.get(), lastNode.get()).size();
            assertEquals(Collections.nCopies(calls, StatusCode.ERROR_STALE_HOOK), during);
            for (ProcedureArguments args : List.of(stashed.get(), last.get())) {
                for (Runnable use : uses(args, root)) {
                    GalleyException refused = assertThrows(GalleyException.class, use::run);
                    assertEquals(StatusCode.ERROR_STALE_HOOK, refused.getCode());
                    assertFalse(refused instanceof StaleTreeException);
                }
            }
        }

        private List<Runnable> uses(ProcedureArguments args, Node node) {
            return List.of(
                    args::currentLine,
                    args::currentColumn,
                    args::currentNode,
                    args::dropSelf,
                    args::dropChildren,
                    args::dropIfEmpty,
                    args::replaceWithChildren,
                    () -> args.reportSemanticError("late"),
                    () -> args.setCurrentNode(node));
        }

        @Test
        void liveArgumentsAreRefusedOnAnyThreadButTheHooks() {
            // A hook's arguments live on the dispatching thread's stack: every
            // other thread is refused with session in use while it runs.
            List<StatusCode> codes = new ArrayList<>();
            AtomicInteger probed = new AtomicInteger();
            session.installProcedure("reduction_Document", args -> {
                Thread thread = new Thread(() -> {
                    for (Runnable use : List.<Runnable>of(args::currentLine, args::currentNode, args::dropSelf,
                            () -> args.reportSemanticError("late"))) {
                        try {
                            use.run();
                        } catch (GalleyException error) {
                            codes.add(error.getCode());
                        }
                    }
                    probed.incrementAndGet();
                });
                thread.start();
                try {
                    thread.join(30_000);
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                }
                args.currentLine();
            });
            try {
                session.parse("alpha:12,beta:3");
            } finally {
                session.clearProcedures();
            }
            assertEquals(1, probed.get());
            assertEquals(Collections.nCopies(4, StatusCode.ERROR_SESSION_IN_USE), codes);
        }

        @Test
        void staleArgumentsOnAnotherThreadAreRefusedAsInUseFirst() throws Exception {
            // Refusals apply in the stated order: a call that overlaps a
            // running parse from another thread is session in use even when
            // the arguments belong to a hook that has returned. On the
            // dispatching thread the same arguments are a stale hook, and once
            // the parse is over nothing overlaps, so any thread gets stale hook.
            AtomicReference<ProcedureArguments> stashed = new AtomicReference<>();
            List<StatusCode> foreign = new ArrayList<>();
            List<StatusCode> own = new ArrayList<>();
            session.installProcedure("reduction_Pair", args -> {
                if (stashed.get() == null) stashed.set(args);
            });
            session.installProcedure("reduction_Document", args -> {
                ProcedureArguments returned = stashed.get();
                Thread thread = new Thread(() -> {
                    for (Runnable use : List.<Runnable>of(returned::currentLine, returned::currentNode,
                            returned::dropSelf, () -> returned.reportSemanticError("late"))) {
                        try {
                            use.run();
                        } catch (GalleyException error) {
                            foreign.add(error.getCode());
                        }
                    }
                });
                thread.start();
                try {
                    thread.join(30_000);
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                }
                try {
                    returned.currentLine();
                } catch (GalleyException error) {
                    own.add(error.getCode());
                }
            });
            try {
                session.parse("alpha:12,beta:3");
            } finally {
                session.clearProcedures();
            }
            assertEquals(Collections.nCopies(4, StatusCode.ERROR_SESSION_IN_USE), foreign);
            assertEquals(List.of(StatusCode.ERROR_STALE_HOOK), own);
            List<StatusCode> after = new ArrayList<>();
            Thread thread = new Thread(() -> {
                try {
                    stashed.get().currentLine();
                } catch (GalleyException error) {
                    after.add(error.getCode());
                }
            });
            thread.start();
            thread.join(30_000);
            assertEquals(List.of(StatusCode.ERROR_STALE_HOOK), after);
        }

        @Test
        void messageOverrideIsRefusedWhileAParseRuns() throws Exception {
            // A message override changes what the running parse reads, so
            // from another thread and from inside a hook it is session in use
            // and changes nothing; with no parse running it works.
            String text = "expected digits here";
            CountDownLatch entered = new CountDownLatch(1);
            CountDownLatch release = new CountDownLatch(1);
            List<StatusCode> fromHook = new ArrayList<>();
            List<StatusCode> fromThread = new ArrayList<>();
            session.installProcedure("reduction_Document", args -> {
                try {
                    session.setMessageOverride("Number", text);
                } catch (GalleyException error) {
                    fromHook.add(error.getCode());
                }
                entered.countDown();
                try {
                    release.await(30, TimeUnit.SECONDS);
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                }
            });
            Thread parser = new Thread(() -> session.parse("alpha:12,beta:3"));
            parser.start();
            try {
                assertTrue(entered.await(30, TimeUnit.SECONDS));
                try {
                    session.setMessageOverride("Number", text);
                } catch (GalleyException error) {
                    fromThread.add(error.getCode());
                }
            } finally {
                release.countDown();
                parser.join(30_000);
                session.clearProcedures();
            }
            assertEquals(List.of(StatusCode.ERROR_SESSION_IN_USE), fromHook);
            assertEquals(List.of(StatusCode.ERROR_SESSION_IN_USE), fromThread);
            GalleyException before = assertThrows(GalleyException.class, () -> session.parse("alpha:"));
            assertFalse(before.getDiagnostic().getMessage().contains(text));
            session.setMessageOverride("Number", text);
            GalleyException after = assertThrows(GalleyException.class, () -> session.parse("alpha:"));
            assertTrue(after.getDiagnostic().getMessage().contains(text));
        }

        @Test
        void closeIsRefusedWhileAParseRuns() throws Exception {
            // Closing takes the same lease: from inside a hook and from
            // another thread it throws session in use, frees nothing, and
            // leaves the session open and reading.
            CountDownLatch entered = new CountDownLatch(1);
            CountDownLatch release = new CountDownLatch(1);
            List<StatusCode> fromHook = new ArrayList<>();
            List<StatusCode> fromThread = new ArrayList<>();
            session.installProcedure("reduction_Document", args -> {
                try {
                    session.close();
                } catch (GalleyException error) {
                    fromHook.add(error.getCode());
                }
                entered.countDown();
                try {
                    release.await(30, TimeUnit.SECONDS);
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                }
            });
            Thread parser = new Thread(() -> session.parse("alpha:12,beta:3"));
            parser.start();
            try {
                assertTrue(entered.await(30, TimeUnit.SECONDS));
                try {
                    session.close();
                } catch (GalleyException error) {
                    fromThread.add(error.getCode());
                }
            } finally {
                release.countDown();
                parser.join(30_000);
                session.clearProcedures();
            }
            assertEquals(List.of(StatusCode.ERROR_SESSION_IN_USE), fromHook);
            assertEquals(List.of(StatusCode.ERROR_SESSION_IN_USE), fromThread);
            assertFalse(session.isClosed());
            assertEquals("alpha:12,beta:3", new String(session.rootNode().text(), StandardCharsets.UTF_8));
            session.close();
            assertTrue(session.isClosed());
        }

        @Test
        void parsingCopiesTheInput() {
            // The caller may overwrite or release its buffer once parse returns.
            ByteBuffer buffer = ByteBuffer.allocateDirect(15);
            buffer.put("alpha:12,beta:3".getBytes(StandardCharsets.UTF_8)).flip();
            session.parse(buffer);
            for (int i = 0; i < buffer.limit(); i++) buffer.put(i, (byte) 'Z');
            assertEquals("alpha:12,beta:3", new String(session.lastInput(), StandardCharsets.UTF_8));
            assertEquals("alpha:12,beta:3", new String(session.rootNode().text(), StandardCharsets.UTF_8));
        }

        @Test
        void aRefusedCallWithReturnedArgumentsChangesNothing() {
            // drop_self through the first Pair's arguments, made from a later
            // Pair hook, is refused and cannot drop that hook's node.
            AtomicReference<ProcedureArguments> stashed = new AtomicReference<>();
            List<StatusCode> refusals = new ArrayList<>();
            session.installProcedure("reduction_Pair", args -> {
                if (stashed.get() == null) {
                    stashed.set(args);
                    return;
                }
                try {
                    stashed.get().dropSelf();
                } catch (GalleyException error) {
                    refusals.add(error.getCode());
                }
            });
            try {
                session.parse("alpha:12,beta:3");
            } finally {
                session.clearProcedures();
            }
            assertEquals(List.of(StatusCode.ERROR_STALE_HOOK), refusals);
            List<String> pairs = new ArrayList<>();
            Walker walker = session.rootNode().walk(false, false);
            while (walker.hasNext()) {
                Node node = walker.next().node;
                if ("Pair".equals(node.symbolName())) pairs.add(new String(node.text(), StandardCharsets.UTF_8));
            }
            assertEquals(List.of("alpha:12", "beta:3"), pairs);
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
            assertTrue(parser.symbolCount() > 0);
            assertTrue(parser.variableCount() > 0);
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
                IllegalArgumentException unknown = assertThrows(IllegalArgumentException.class,
                        () -> sess.installProcedure("reductionPair", args -> {}));
                assertTrue(unknown.getMessage().contains("reductionPair"), unknown.getMessage());
                assertEquals(1, sess.installProcedures(Map.of(
                        "hook_print", (Runnable) () -> {},
                        "myHelper", (Runnable) () -> {})));
                assertEquals(2, sess.listProcedures().size());
                assertNull(sess.lookupProcedure("reductionPair"));
            } finally {
                System.setErr(original);
            }
            String warnings = captured.toString(StandardCharsets.UTF_8);
            assertFalse(warnings.contains("reductionPair"), warnings);
            assertFalse(warnings.contains("myHelper"), warnings);
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
        void hookThrowingAbortsTheParseAndKeepsTheCause() {
            RuntimeException boom = new RuntimeException("boom");
            List<Node> fired = new ArrayList<>();
            parser.installProcedure("reduction_Number", args -> {
                fired.add(args.currentNode());
                throw boom;
            });
            Session openedSession = parser.openSession();
            try {
                GalleyException failure = assertThrows(GalleyException.class, () -> openedSession.parse("alpha:12,beta:3"));
                // The parse stopped at the first hook; the failure carries the
                // hook's own throwable, the status and where the parse stopped.
                assertEquals(1, fired.size());
                assertSame(boom, failure.getCause());
                assertEquals(StatusCode.ERROR_HOOK_FAILED, failure.getCode());
                Diagnostic diagnostic = failure.getDiagnostic();
                assertNotNull(diagnostic);
                assertEquals(DiagnosticKind.HOOK, diagnostic.getKind());
                assertTrue(diagnostic.getLine() >= 1 && diagnostic.getColumn() >= 1);
                assertTrue(failure.getMessage().contains("reduction_Number"));
                // Nothing was published and the nodes of the parse are refused.
                assertNull(openedSession.rootNode());
                assertThrows(StaleTreeException.class, openedSession::nodeCount);
                assertThrows(StaleTreeException.class, () -> fired.get(0).text());
            } finally {
                openedSession.close();
            }
        }

        @Test
        void hookFailureAfterARecoveredSyntaxErrorReportsTheHook() {
            parser.installProcedure("reduction_Document", args -> { throw new IllegalStateException("late failure"); });
            Session openedSession = parser.openSession();
            try {
                GalleyException failure = assertThrows(GalleyException.class, () -> openedSession.parse("alpha:12,beta@3"));
                assertEquals(StatusCode.ERROR_HOOK_FAILED, failure.getCode());
                Diagnostic diagnostic = failure.getDiagnostic();
                assertNotNull(diagnostic);
                assertEquals(DiagnosticKind.HOOK, diagnostic.getKind());
                assertTrue(failure.getMessage().contains("HookError"));
                assertTrue(diagnostic.getMessage().contains("HookError"));
                assertFalse(diagnostic.getMessage().contains("SyntaxError"));
                assertEquals(diagnostic.getMessage(), diagnostic.getMessageAnsi().replaceAll("\u001b\\[[0-9;]*m", ""));
            } finally {
                openedSession.close();
            }
        }

        @Test
        void sessionParsesAgainAfterAHookAbortedTheParse() {
            AtomicInteger calls = new AtomicInteger();
            parser.installProcedure("reduction_Number", args -> {
                if (calls.incrementAndGet() == 1) throw new IllegalStateException("first parse only");
            });
            Session openedSession = parser.openSession();
            try {
                GalleyException failure = assertThrows(GalleyException.class, () -> openedSession.parse("alpha:12,beta:3"));
                assertInstanceOf(IllegalStateException.class, failure.getCause());
                assertEquals(15, openedSession.parse("alpha:12,beta:3"));
                assertEquals(3, calls.get());
                Node root = openedSession.rootNode();
                assertNotNull(root);
                assertEquals("alpha:12,beta:3", new String(root.text(), StandardCharsets.UTF_8));
                assertNull(openedSession.diagnostic());
            } finally {
                openedSession.close();
            }
        }

        @Test
        void hookFailureOfANestedSessionStaysWithThatSession() {
            RuntimeException innerFailure = new RuntimeException("inner");
            List<GalleyException> innerFailures = new ArrayList<>();
            List<String> outerSeen = new ArrayList<>();
            boolean[] nested = {false};
            Session openedSession = parser.openSession();
            try {
                openedSession.installProcedure("reduction_Pair", args -> {
                    outerSeen.add(new String(args.currentNode().text(), StandardCharsets.UTF_8));
                    if (!nested[0]) {
                        nested[0] = true;
                        try (Session innerSession = parser.openSession()) {
                            innerSession.installProcedure("reduction_Number", innerArgs -> { throw innerFailure; });
                            try {
                                innerSession.parse("alpha:9");
                            } catch (GalleyException failure) {
                                innerFailures.add(failure);
                            }
                        }
                    }
                });
                assertEquals(15, openedSession.parse("alpha:12,beta:3"));
                assertEquals(List.of("alpha:12", "beta:3"), outerSeen);
                assertEquals(1, innerFailures.size());
                assertSame(innerFailure, innerFailures.get(0).getCause());
                assertNotNull(openedSession.rootNode());
            } finally {
                openedSession.close();
            }
        }

        @Test
        void nearMissNamesRaiseAndScanStaysQuiet() {
            PrintStream original = System.err;
            ByteArrayOutputStream captured = new ByteArrayOutputStream();
            System.setErr(new PrintStream(captured, true, StandardCharsets.UTF_8));
            try {
                parser.installProcedure("reduction_Pair", args -> {});
                IllegalArgumentException pair = assertThrows(IllegalArgumentException.class,
                        () -> parser.installProcedure("reductionPair", args -> {}));
                assertTrue(pair.getMessage().contains("reductionPair"), pair.getMessage());
                assertThrows(IllegalArgumentException.class,
                        () -> parser.installProcedure("hookPrint", () -> {}));
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
            assertFalse(warnings.contains("reductionPair"), warnings);
            assertFalse(warnings.contains("reducton_X"), warnings);
            assertFalse(warnings.contains("myHelper"), warnings);
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
        void everyLoadReturnsAFreshParserWithItsOwnDefaults() throws Exception {
            String path = fixtureLibraryPath();
            Parser first = Galley.load(path);
            Parser second = Galley.load(path);
            assertNotSame(first, second);
            assertTrue(first.listProcedures().isEmpty());
            assertTrue(second.listProcedures().isEmpty());

            AtomicInteger firstCalls = new AtomicInteger(0);
            first.installProcedure("reduction_Pair", args -> firstCalls.incrementAndGet());
            assertNotNull(first.lookupProcedure("reduction_Pair"));
            assertNull(second.lookupProcedure("reduction_Pair"));

            // Each session sees its own parser's defaults only.
            try (Session fromFirst = first.openSession(); Session fromSecond = second.openSession()) {
                assertEquals(1, fromFirst.listProcedures().size());
                assertEquals(0, fromSecond.listProcedures().size());
                fromFirst.parse("alpha:12,beta:3");
                fromSecond.parse("alpha:12,beta:3");
                assertEquals(2, firstCalls.get());
            }

            // The real path of the same artifact is a fresh independent
            // parser too, never the one already handed out.
            Parser viaRealPath = Galley.load(Path.of(path).toRealPath().toString());
            assertNotSame(first, viaRealPath);
            assertNotSame(second, viaRealPath);
            assertTrue(viaRealPath.listProcedures().isEmpty());
            assertNull(viaRealPath.lookupProcedure("reduction_Pair"));

            // So is a load through a symlink of that artifact.
            Path dir = Files.createTempDirectory("galley-java-symlink");
            Path link = dir.resolve("fixture-link");
            Files.createSymbolicLink(link, Path.of(path));
            try {
                Parser viaLink = Galley.load(link.toString());
                assertNotSame(first, viaLink);
                assertNotSame(second, viaLink);
                assertNotSame(viaRealPath, viaLink);
                assertTrue(viaLink.listProcedures().isEmpty());
                assertNull(viaLink.lookupProcedure("reduction_Pair"));
            } finally {
                Files.deleteIfExists(link);
                Files.deleteIfExists(dir);
            }
        }

        /** Loads a parser, runs a session with a hook, and returns weak references to both. */
        private List<java.lang.ref.WeakReference<Object>> loadUseAndDrop() throws Exception {
            Parser parser = Galley.load(fixtureLibraryPath());
            Object marker = new Object();
            parser.installProcedure("reduction_Number", args -> marker.hashCode());
            try (Session session = parser.openSession()) {
                session.parse("alpha:12");
            }
            return List.of(new java.lang.ref.WeakReference<>(parser), new java.lang.ref.WeakReference<>(marker));
        }

        @Test
        void droppedParserIsCollectable() throws Exception {
            List<java.lang.ref.WeakReference<Object>> references = loadUseAndDrop();
            for (int attempt = 0; attempt < 100
                    && (references.get(0).get() != null || references.get(1).get() != null); attempt++) {
                System.gc();
                Thread.sleep(20);
            }
            assertNull(references.get(0).get(), "a dropped parser must be collectable");
            assertNull(references.get(1).get(), "a dropped parser's hooks must be collectable");
        }

        @Test
        void severalLiveParsersRouteHooksToTheirOwnSessions() throws Exception {
            int count = 5;
            List<Parser> parsers = new ArrayList<>();
            List<AtomicInteger> calls = new ArrayList<>();
            for (int i = 0; i < count; i++) {
                Parser parser = Galley.load(fixtureLibraryPath());
                AtomicInteger counter = new AtomicInteger(0);
                parser.installProcedure("reduction_Pair", args -> counter.incrementAndGet());
                parsers.add(parser);
                calls.add(counter);
            }
            List<Session> sessions = new ArrayList<>();
            try {
                for (Parser parser : parsers) sessions.add(parser.openSession());
                // Parser i's session parses i + 1 times; each hook fires twice per parse.
                for (int round = 0; round < count; round++) {
                    for (int i = round; i < count; i++) sessions.get(i).parse("alpha:12,beta:3");
                }
                for (int i = 0; i < count; i++) {
                    assertEquals(2 * (i + 1), calls.get(i).get(), "parser " + i);
                }
            } finally {
                for (Session session : sessions) session.close();
            }
        }

        @Test
        void bareLoadAfterPackageImportHasNoBundledHooks() throws Exception {
            Parser packageParser = test_fixture.Parser.load(fixtureLibraryPath());
            assertFalse(packageParser.listProcedures().isEmpty());

            Parser bare = Galley.load(fixtureLibraryPath());
            assertNotSame(packageParser, bare);
            assertTrue(bare.listProcedures().isEmpty());
            try (Session bareSession = bare.openSession()) {
                assertTrue(bareSession.listProcedures().isEmpty());
            }

            // The package import keeps its one parser with its bundled hooks.
            try (Session packageSession = packageParser.openSession()) {
                assertEquals(packageParser.listProcedures(), packageSession.listProcedures());
            }
            assertFalse(packageParser.listProcedures().isEmpty());
        }

        @Test
        void failedLoadLeavesExistingParsersUntouchedAndRetryWorks() throws Exception {
            Parser existing = Galley.load(fixtureLibraryPath());
            AtomicInteger calls = new AtomicInteger(0);
            existing.installProcedure("reduction_Pair", args -> calls.incrementAndGet());

            Path dir = Files.createTempDirectory("galley-java-failed-load");
            try {
                // A missing artifact hands out no parser.
                String missing = dir.resolve("no-such-dir")
                        .resolve(GalleyLibraryLoader.libFileName()).toString();
                assertThrows(MissingArtifactException.class, () -> Galley.load(missing));

                // A corrupt file at an existing path fails the load too.
                Path corrupt = dir.resolve(GalleyLibraryLoader.libFileName());
                Files.writeString(corrupt, "not a shared library");
                assertThrows(IllegalArgumentException.class, () -> Galley.load(corrupt.toString()));

                // The parser already handed out still answers and still has
                // its hook.
                assertNotNull(existing.version());
                assertNotNull(existing.lookupProcedure("reduction_Pair"));
                try (Session session = existing.openSession()) {
                    assertEquals(1, session.listProcedures().size());
                    session.parse("alpha:12,beta:3");
                    assertEquals(2, calls.get());
                }

                // With the cause fixed the retry is a fresh attempt that
                // hands out a new bare parser.
                Files.copy(Path.of(fixtureLibraryPath()), corrupt, StandardCopyOption.REPLACE_EXISTING);
                Parser retried = Galley.load(corrupt.toString());
                assertNotSame(existing, retried);
                assertTrue(retried.listProcedures().isEmpty());
                assertNotNull(existing.lookupProcedure("reduction_Pair"));
            } finally {
                Files.deleteIfExists(dir.resolve(GalleyLibraryLoader.libFileName()));
                Files.deleteIfExists(dir);
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
