package org.sanbus.galley;

import static org.junit.jupiter.api.Assertions.*;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import org.junit.jupiter.api.Test;

/**
 * Two parsers, two sessions each, four threads parsing at the same time.
 *
 * The first hook of every parse waits at a four-way barrier, so the test
 * passes only if all four parses are in flight at once. Each session carries
 * its own hook set, and every hook checks that it runs on its own session's
 * thread, so a hook routed to the wrong session, a gate set by a neighbour,
 * or a skipped hook shows up as a count mismatch.
 *
 * Needs both fixture libraries: test-fixture (keyvalue grammar) and
 * test-fixture-second (second shared grammar), each located by the suite
 * itself.
 */
class ConcurrencyTest {
    private static final int ITEMS = 150;
    private static final int STRESS_ROUNDS = 200;
    private static final int BARRIER_TIMEOUT_SECONDS = 20;

    private static Parser load(String fixtureName) throws MissingArtifactException {
        Parser parser = Galley.load(FixtureLibrary.path(fixtureName));
        parser.clearProcedures();
        return parser;
    }

    /** One session's configuration and what its hooks saw. */
    private static final class Worker {
        final Parser parser;
        final String input;
        final List<String> hooks;
        final Map<String, AtomicInteger> calls = new java.util.concurrent.ConcurrentHashMap<>();
        final AtomicInteger wrongThread = new AtomicInteger();
        final AtomicInteger arrivals = new AtomicInteger();
        volatile CyclicBarrier barrier;
        volatile Thread thread;
        volatile Session session;
        volatile Throwable barrierFailure;
        volatile Throwable refusal;
        volatile int parsed;

        Worker(Parser parser, String input, String... hooks) {
            this.parser = parser;
            this.input = input;
            this.hooks = List.of(hooks);
        }

        int callsTo(String hook) {
            AtomicInteger count = calls.get(hook);
            return count == null ? 0 : count.get();
        }

        void reset() {
            calls.clear();
            wrongThread.set(0);
            arrivals.set(0);
            barrierFailure = null;
            refusal = null;
        }

        /** Opens this worker's session on the calling thread and installs its hooks. */
        Session open() {
            Session opened = parser.openSession();
            session = opened;
            for (String hook : hooks) {
                opened.installProcedure(hook, args -> onHook(hook));
            }
            return opened;
        }

        private void onHook(String hook) {
            if (Thread.currentThread() != thread) wrongThread.incrementAndGet();
            calls.computeIfAbsent(hook, key -> new AtomicInteger()).incrementAndGet();
            CyclicBarrier gate = barrier;
            if (gate != null && arrivals.getAndIncrement() == 0) {
                try {
                    gate.await(BARRIER_TIMEOUT_SECONDS, TimeUnit.SECONDS);
                } catch (Throwable failure) {
                    barrierFailure = failure;
                }
                // Still inside the parse: changing hooks must be refused.
                try {
                    session.clearProcedures();
                } catch (Throwable failure) {
                    refusal = failure;
                }
            }
        }

        /** One parse on the calling thread, which becomes this worker's hook thread. */
        int parseOnThisThread() {
            thread = Thread.currentThread();
            parsed = session.parse(input);
            return parsed;
        }
    }

    private static String keyvalueInput() {
        StringBuilder builder = new StringBuilder();
        for (int i = 0; i < ITEMS; i++) builder.append(i == 0 ? "" : ",").append('k').append(i).append(':').append(i % 97);
        return builder.toString();
    }

    private static String wordInput() {
        StringBuilder builder = new StringBuilder();
        for (int i = 0; i < ITEMS; i++) builder.append(i == 0 ? "" : "+").append("word");
        return builder.toString();
    }

    private static void assertExpectedCalls(Worker worker, Worker[] workers) {
        boolean first = worker == workers[0] || worker == workers[1];
        String specific = first ? "hook_print" : "hook_tally";
        String reduction = first ? "reduction_Pair" : "reduction_Word";
        assertEquals(worker.hooks.contains(specific) ? ITEMS : 0, worker.callsTo(specific));
        assertEquals(worker.hooks.contains(reduction) ? ITEMS : 0, worker.callsTo(reduction));
        assertEquals(0, worker.wrongThread.get());
    }

    @Test
    void twoParsersTwoSessionsEachFourThreadsAtOnce() throws Exception {
        Parser first = load("test-fixture");
        Parser second = load("test-fixture-second");
        assertNotSame(first, second);
        Worker[] workers = {
            new Worker(first, keyvalueInput(), "reduction_Pair", "hook_print"),
            new Worker(first, keyvalueInput(), "hook_print"),
            new Worker(second, wordInput(), "reduction_Word", "hook_tally"),
            new Worker(second, wordInput(), "reduction_Word"),
        };
        ExecutorService pool = Executors.newFixedThreadPool(workers.length);
        try {
            CyclicBarrier barrier = new CyclicBarrier(workers.length);
            for (Worker worker : workers) worker.barrier = barrier;

            // Four parses held at one barrier: all four in flight at once.
            List<Future<Integer>> parses = new ArrayList<>();
            for (Worker worker : workers) {
                Callable<Integer> task = () -> {
                    worker.thread = Thread.currentThread();
                    worker.open();
                    return worker.parseOnThisThread();
                };
                parses.add(pool.submit(task));
            }
            for (Future<Integer> parse : parses) assertTrue(parse.get(60, TimeUnit.SECONDS) > 0);
            for (Worker worker : workers) {
                assertNull(worker.barrierFailure, "the four parses did not overlap");
                assertExpectedCalls(worker, workers);
                assertTrue(worker.refusal instanceof GalleyException);
                assertEquals(StatusCode.ERROR_SESSION_IN_USE, ((GalleyException) worker.refusal).getCode());
                assertEquals(worker.hooks.size(), worker.session.listProcedures().size());
            }

            // Stress: the same four sessions parse again and again without
            // the barrier; every round reproduces the expected counts.
            for (Worker worker : workers) worker.barrier = null;
            for (int round = 0; round < STRESS_ROUNDS; round++) {
                for (Worker worker : workers) worker.reset();
                List<Future<Integer>> rounds = new ArrayList<>();
                for (Worker worker : workers) rounds.add(pool.submit(worker::parseOnThisThread));
                for (Future<Integer> parse : rounds) assertTrue(parse.get(60, TimeUnit.SECONDS) > 0);
                for (Worker worker : workers) assertExpectedCalls(worker, workers);
            }
        } finally {
            pool.shutdownNow();
            for (Worker worker : workers) if (worker.session != null) worker.session.close();
            first.clearProcedures();
            second.clearProcedures();
        }
    }
}
