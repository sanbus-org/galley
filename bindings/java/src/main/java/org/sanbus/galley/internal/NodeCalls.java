package org.sanbus.galley.internal;

import java.lang.foreign.FunctionDescriptor;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.ValueLayout;
import java.lang.invoke.MethodHandle;
import java.util.function.BiFunction;

/**
 * One door's node, tree and walk downcalls: the {@code galley_node_*} /
 * {@code galley_tree_*} / {@code galley_walk_next} family over a session
 * handle, or its {@code galley_hook_*} twin over a parse's native door. The
 * two families take the same arguments after the handle and answer the same
 * way, so each capability is declared here once and the class is
 * instantiated for both prefixes: two sets of downcall handles with
 * identical types. Every call takes the generation of the tree it addresses
 * and the core refuses one that is not the door's live tree's with a
 * negative status.
 */
public final class NodeCalls {
    private static final ValueLayout.OfLong LONG = ValueLayout.JAVA_LONG;
    private static final ValueLayout ADDRESS = ValueLayout.ADDRESS;

    private final MethodHandle childCount;
    private final MethodHandle firstChild;
    private final MethodHandle lastChild;
    private final MethodHandle nextSibling;
    private final MethodHandle priorSibling;
    private final MethodHandle parent;
    private final MethodHandle symbolName;
    private final MethodHandle text;
    private final MethodHandle span;
    private final MethodHandle lineColumn;
    private final MethodHandle variableIndex;
    private final MethodHandle walkNext;
    private final MethodHandle appendChildren;
    private final MethodHandle insertBefore;
    private final MethodHandle insertAfter;
    private final MethodHandle removeSiblings;
    private final MethodHandle removeSelf;
    private final MethodHandle cleanChildren;
    private final MethodHandle insertChildrenAt;
    private final MethodHandle removeChildrenAt;

    /**
     * @param downcall binds a symbol name to a downcall handle of a descriptor
     * @param door     {@code ""} for the session family, {@code "hook_"} for its twin
     */
    NodeCalls(BiFunction<String, FunctionDescriptor, MethodHandle> downcall, String door) {
        FunctionDescriptor link = FunctionDescriptor.of(LONG, ADDRESS, LONG, LONG);
        FunctionDescriptor pair = FunctionDescriptor.of(LONG, ADDRESS, LONG, LONG, ADDRESS, ADDRESS);
        FunctionDescriptor edit = FunctionDescriptor.of(LONG, ADDRESS, LONG, LONG, LONG);
        FunctionDescriptor detach = FunctionDescriptor.of(LONG, ADDRESS, LONG, LONG, ADDRESS);
        childCount = downcall.apply("galley_" + door + "node_child_count", link);
        firstChild = downcall.apply("galley_" + door + "node_first_child", link);
        lastChild = downcall.apply("galley_" + door + "node_last_child", link);
        nextSibling = downcall.apply("galley_" + door + "node_next_sibling", link);
        priorSibling = downcall.apply("galley_" + door + "node_prior_sibling", link);
        parent = downcall.apply("galley_" + door + "node_parent", link);
        symbolName = downcall.apply("galley_" + door + "node_symbol_name", pair);
        text = downcall.apply("galley_" + door + "node_text", pair);
        span = downcall.apply("galley_" + door + "node_span", pair);
        lineColumn = downcall.apply("galley_" + door + "node_line_column", pair);
        variableIndex = downcall.apply("galley_" + door + "node_variable_index", link);
        walkNext = downcall.apply("galley_" + door + "walk_next", FunctionDescriptor.of(LONG, ADDRESS, ADDRESS));
        appendChildren = downcall.apply("galley_" + door + "tree_append_children", edit);
        insertBefore = downcall.apply("galley_" + door + "tree_insert_before", edit);
        insertAfter = downcall.apply("galley_" + door + "tree_insert_after", edit);
        removeSiblings = downcall.apply("galley_" + door + "tree_remove_siblings",
                FunctionDescriptor.of(LONG, ADDRESS, LONG, LONG, LONG, ADDRESS));
        removeSelf = downcall.apply("galley_" + door + "tree_remove_self", detach);
        cleanChildren = downcall.apply("galley_" + door + "tree_clean_children", detach);
        insertChildrenAt = downcall.apply("galley_" + door + "tree_insert_children_at",
                FunctionDescriptor.of(LONG, ADDRESS, LONG, LONG, LONG, LONG));
        removeChildrenAt = downcall.apply("galley_" + door + "tree_remove_children_at",
                FunctionDescriptor.of(LONG, ADDRESS, LONG, LONG, LONG, LONG, ADDRESS));
    }

    public long childCount(MemorySegment handle, long generation, long node) { try { return (long) childCount.invoke(handle, generation, node); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long firstChild(MemorySegment handle, long generation, long node) { try { return (long) firstChild.invoke(handle, generation, node); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long lastChild(MemorySegment handle, long generation, long node) { try { return (long) lastChild.invoke(handle, generation, node); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long nextSibling(MemorySegment handle, long generation, long node) { try { return (long) nextSibling.invoke(handle, generation, node); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long priorSibling(MemorySegment handle, long generation, long node) { try { return (long) priorSibling.invoke(handle, generation, node); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long parent(MemorySegment handle, long generation, long node) { try { return (long) parent.invoke(handle, generation, node); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long symbolName(MemorySegment handle, long generation, long node, MemorySegment outData, MemorySegment outLen) { try { return (long) symbolName.invoke(handle, generation, node, outData, outLen); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long text(MemorySegment handle, long generation, long node, MemorySegment outData, MemorySegment outLen) { try { return (long) text.invoke(handle, generation, node, outData, outLen); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long span(MemorySegment handle, long generation, long node, MemorySegment outStart, MemorySegment outLen) { try { return (long) span.invoke(handle, generation, node, outStart, outLen); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long lineColumn(MemorySegment handle, long generation, long node, MemorySegment outLine, MemorySegment outColumn) { try { return (long) lineColumn.invoke(handle, generation, node, outLine, outColumn); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long variableIndex(MemorySegment handle, long generation, long node) { try { return (long) variableIndex.invoke(handle, generation, node); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long walkNext(MemorySegment handle, MemorySegment cursor) { try { return (long) walkNext.invoke(handle, cursor); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long appendChildren(MemorySegment handle, long generation, long parent, long first) { try { return (long) appendChildren.invoke(handle, generation, parent, first); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long insertBefore(MemorySegment handle, long generation, long target, long first) { try { return (long) insertBefore.invoke(handle, generation, target, first); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long insertAfter(MemorySegment handle, long generation, long target, long first) { try { return (long) insertAfter.invoke(handle, generation, target, first); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long removeSiblings(MemorySegment handle, long generation, long node, long count, MemorySegment outHead) { try { return (long) removeSiblings.invoke(handle, generation, node, count, outHead); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long removeSelf(MemorySegment handle, long generation, long node, MemorySegment outHead) { try { return (long) removeSelf.invoke(handle, generation, node, outHead); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long cleanChildren(MemorySegment handle, long generation, long node, MemorySegment outHead) { try { return (long) cleanChildren.invoke(handle, generation, node, outHead); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long insertChildrenAt(MemorySegment handle, long generation, long parent, long index, long first) { try { return (long) insertChildrenAt.invoke(handle, generation, parent, index, first); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long removeChildrenAt(MemorySegment handle, long generation, long parent, long index, long count, MemorySegment outHead) { try { return (long) removeChildrenAt.invoke(handle, generation, parent, index, count, outHead); } catch (Throwable t) { throw new RuntimeException(t); } }
}
