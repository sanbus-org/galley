package org.sanbus.galley;

import java.lang.foreign.MemorySegment;
import java.lang.foreign.ValueLayout;

/**
 * The layout of {@code GalleyWalkCursor} from galley.h — the single
 * definition {@link Walker} (initialization, skip) and
 * {@link Session#walkerStep} (read-back) share. 40 bytes, offsets as
 * longs, 8-byte aligned:
 * generation u64 @0, root u64 @8, current u64 @16, depth u32 @24,
 * state u16 @28, options u8 @30, flags u8 @31, and
 * structure_version u64 @32 — stamped by the core on every step, never
 * read host-side.
 */
final class WalkCursor {
    static final long BYTES = 40;
    static final long ALIGNMENT = 8;

    static final long GENERATION_OFFSET = 0;
    static final long ROOT_OFFSET = 8;
    static final long CURRENT_OFFSET = 16;
    static final long DEPTH_OFFSET = 24;
    static final long STATE_OFFSET = 28;
    static final long OPTIONS_OFFSET = 30;
    static final long FLAG_OFFSET = 31;
    static final long STRUCTURE_VERSION_OFFSET = 32;

    static final short STATE_NOT_STARTED = 0;
    static final short STATE_YIELDED = 1;
    static final short STATE_YIELDED_SKIP_CHILDREN = 2;
    static final short STATE_DONE = 3;
    static final byte OPTION_SKIP_SEMANTIC_ERRORS = 1;
    static final byte OPTION_SKIP_RECOVERED = 2;
    static final byte FLAG_SEMANTIC_ERROR = 1;
    static final byte FLAG_RECOVERED = 2;

    /** The node of a completed step: its address in the parse storage. */
    static long current(MemorySegment cursor) {
        return cursor.get(ValueLayout.JAVA_LONG, CURRENT_OFFSET);
    }

    /** The depth of a completed step below the walk's root. */
    static int depth(MemorySegment cursor) {
        return cursor.get(ValueLayout.JAVA_INT, DEPTH_OFFSET);
    }

    /** The semantic-error flag of a completed step. */
    static boolean isSemanticError(MemorySegment cursor) {
        return (cursor.get(ValueLayout.JAVA_BYTE, FLAG_OFFSET) & FLAG_SEMANTIC_ERROR) != 0;
    }

    /** The recovered flag of a completed step. */
    static boolean isRecovered(MemorySegment cursor) {
        return (cursor.get(ValueLayout.JAVA_BYTE, FLAG_OFFSET) & FLAG_RECOVERED) != 0;
    }

    private WalkCursor() {}
}
