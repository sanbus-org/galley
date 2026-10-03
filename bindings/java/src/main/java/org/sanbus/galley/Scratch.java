package org.sanbus.galley;

import java.lang.foreign.Arena;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.ValueLayout;

/**
 * Two 8-byte out-value slots a native node crossing writes into, one pair per
 * thread. Session-door reads run on several threads at once (readers share
 * the core's guard), so a pair shared per session would be a data race; a
 * pair per thread is race-free and removes the allocation each crossing
 * would otherwise pay. A crossing copies its results out before it returns,
 * and no native node call re-enters Java, so one pair per thread is never
 * live twice. The segments come from an automatic arena and are freed with
 * their thread.
 */
final class Scratch {
    private static final ThreadLocal<Scratch> LOCAL = ThreadLocal.withInitial(Scratch::new);

    /** First out-value: an out-pointer, count, address, start or line. */
    final MemorySegment first;
    /** Second out-value: an out-length, generation or column. */
    final MemorySegment second;

    private Scratch() {
        MemorySegment both = Arena.ofAuto().allocate(2L * Long.BYTES, Long.BYTES);
        this.first = both.asSlice(0, Long.BYTES);
        this.second = both.asSlice(Long.BYTES, Long.BYTES);
    }

    static Scratch local() {
        return LOCAL.get();
    }

    long firstLong() {
        return first.get(ValueLayout.JAVA_LONG, 0);
    }

    long secondLong() {
        return second.get(ValueLayout.JAVA_LONG, 0);
    }

    int firstInt() {
        return first.get(ValueLayout.JAVA_INT, 0);
    }

    int secondInt() {
        return second.get(ValueLayout.JAVA_INT, 0);
    }
}
