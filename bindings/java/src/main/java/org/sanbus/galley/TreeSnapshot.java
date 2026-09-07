package org.sanbus.galley;

/**
 * Flat bulk read of the most recent successful parse (see
 * {@link Session#snapshot()}): one entry per node address. Missing links
 * read as {@code -1L} (the {@code GALLEY_INVALID_NODE} bits), missing
 * variables as {@code -1L}, and spans index {@link Session#lastInput()}.
 */
public record TreeSnapshot(
        long count,
        long[] parent,
        long[] firstChild,
        long[] next,
        int[] childCount,
        long[] variable,
        long[] spanStart,
        long[] spanLen) {}
