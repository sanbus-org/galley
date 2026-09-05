package org.sanbus.galley;

import java.io.File;
import java.lang.foreign.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.sanbus.galley.internal.GalleyLibrary;
import org.sanbus.galley.internal.GalleyLibraryLoader;

/**
 * Parsing session bound to this library's parser. Mirrors Python/Go/Rust/TypeScript Sessions
 * over bindings/c/galley.h. Not thread-safe. Panama FFI (Java 22+, no JNA).
 */
public final class Session implements AutoCloseable {

    private static final long INVALID_NODE = 0xFFFFFFFFFFFFFFFFL;

    private static final ConcurrentHashMap<Long, Session> LIVE_SESSIONS = new ConcurrentHashMap<>();

    private MemorySegment handle;
    private final GalleyLibrary lib;
    private boolean closed = false;
    private final String libraryPath;

    private static final ThreadLocal<Session> PARSING_SESSION = new ThreadLocal<>();

    public Session() {
        this(SessionOptions.defaults());
    }

    public Session(SessionOptions options) {
        if (options == null) options = SessionOptions.defaults();
        this.libraryPath = options.getLibraryPath();
        this.lib = GalleyLibraryLoader.load(libraryPath);
        try { Procedures.ensureForLibrary(lib); } catch (Exception ignored) {}

        MemorySegment h;
        boolean hasNonDefault = options.getMaxErrors() != 10 ||
                options.getRecoveryWindow() != 500 ||
                options.isStackOverflowRecovery() ||
                options.getSyntaxErrorStackDepth() != 0 ||
                options.getVerbosity() != 0 ||
                options.getAstPreallocationRatio() != -1.0 ||
                options.getAstPreallocationCap() != 0;

        if (hasNonDefault) {
            try (Arena arena = Arena.ofConfined()) {
                MemorySegment opts = arena.allocate(GalleyLibrary.GALLEY_COPTIONS_SIZE);
                opts.set(ValueLayout.JAVA_INT, GalleyLibrary.OFF_MAX_ERRORS, options.getMaxErrors());
                opts.set(ValueLayout.JAVA_INT, GalleyLibrary.OFF_RECOVERY_WINDOW, options.getRecoveryWindow());
                opts.set(ValueLayout.JAVA_INT, GalleyLibrary.OFF_STACK_OVERFLOW_RECOVERY, options.isStackOverflowRecovery() ? 1 : 0);
                opts.set(ValueLayout.JAVA_INT, GalleyLibrary.OFF_SYNTAX_ERROR_STACK_DEPTH, options.getSyntaxErrorStackDepth());
                opts.set(ValueLayout.JAVA_INT, GalleyLibrary.OFF_VERBOSITY, options.getVerbosity());
                opts.set(ValueLayout.JAVA_DOUBLE, GalleyLibrary.OFF_AST_PREALLOCATION_RATIO, options.getAstPreallocationRatio());
                opts.set(ValueLayout.JAVA_LONG, GalleyLibrary.OFF_AST_PREALLOCATION_CAP, options.getAstPreallocationCap());
                h = lib.galley_session_create_ex(opts);
            }
        } else {
            h = lib.galley_session_create();
        }
        if (h == null || h.equals(MemorySegment.NULL) || h.address() == 0) {
            throw new GalleyException("out of memory", -7);
        }
        this.handle = h;
        LIVE_SESSIONS.put(h.address(), this);
        Procedures.registerSession(h.address(), this);

        for (Map.Entry<String, String> e : options.getMessageOverrides().entrySet()) {
            setMessageOverride(e.getKey(), e.getValue());
        }
    }

    static Session fromNativePointer(MemorySegment seg, GalleyLibrary lib) {
        if (seg == null || seg.equals(MemorySegment.NULL) || seg.address() == 0) return null;
        long val = seg.address();
        Session s = LIVE_SESSIONS.get(val);
        if (s != null) return s;
        s = Procedures.findSession(seg);
        if (s != null) return s;
        Session tl = PARSING_SESSION.get();
        if (tl != null && tl.handle != null && tl.handle.address() == val) return tl;
        return null;
    }

    // For ProcedureArguments via long address
    static Session fromNativeSegment(MemorySegment seg, GalleyLibrary lib) {
        return fromNativePointer(seg, lib);
    }

    static Session fromNativeAddress(long address, GalleyLibrary lib) {
        if (address == 0) return null;
        Session s = LIVE_SESSIONS.get(address);
        if (s != null) return s;
        s = Procedures.findSessionByAddress(address);
        if (s != null) return s;
        Session tl = PARSING_SESSION.get();
        if (tl != null && tl.handle != null && tl.handle.address() == address) return tl;
        return null;
    }

    private void requireOpen() {
        if (closed || handle == null || handle.equals(MemorySegment.NULL)) throw new IllegalStateException("session is closed");
    }

    private GalleyException errorFromStatus(long status) {
        String msg = lib.galley_status_string(status);
        if (msg == null) msg = "unknown galley error";
        Diagnostic diag = null;
        try {
            if (handle != null && !handle.equals(MemorySegment.NULL) && lib.galley_has_diagnostic(handle) != 0) {
                diag = buildDiagnosticSingular();
                if (diag.getMessage() != null && !diag.getMessage().isEmpty()) msg = diag.getMessage();
            }
        } catch (Exception ignored) {}
        return new GalleyException(msg, (int) status, diag);
    }

    private void checkStatus(long status) {
        if (status < 0) throw errorFromStatus(status);
    }

    public boolean isClosed() { return closed || handle == null || handle.equals(MemorySegment.NULL); }

    @Override
    public void close() {
        if (handle != null && !handle.equals(MemorySegment.NULL)) {
            long val = handle.address();
            LIVE_SESSIONS.remove(val);
            Procedures.unregisterSession(val);
            try { lib.galley_session_destroy(handle); } catch (Exception ignored) {}
            handle = MemorySegment.NULL;
        }
        closed = true;
    }

    // -- parsing --

    public int parse(byte[] input) {
        requireOpen();
        if (input == null) input = new byte[0];
        long len = input.length;
        if (len == 0) {
            Session prev = PARSING_SESSION.get();
            PARSING_SESSION.set(this);
            long status;
            try {
                status = lib.galley_parse(handle, MemorySegment.NULL, len);
            } finally {
                if (prev != null) PARSING_SESSION.set(prev); else PARSING_SESSION.remove();
            }
            if (status < 0) throw errorFromStatus(status);
            return (int) status;
        }
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment dataSeg = arena.allocateFrom(ValueLayout.JAVA_BYTE, input);
            Session prev = PARSING_SESSION.get();
            PARSING_SESSION.set(this);
            long status;
            try {
                status = lib.galley_parse(handle, dataSeg, len);
            } finally {
                if (prev != null) PARSING_SESSION.set(prev); else PARSING_SESSION.remove();
            }
            if (status < 0) throw errorFromStatus(status);
            return (int) status;
        }
    }

    public int parse(ByteBuffer buffer) {
        requireOpen();
        if (buffer == null) throw new IllegalArgumentException("buffer is null");
        int len = buffer.remaining();
        if (len == 0) {
            Session prev = PARSING_SESSION.get();
            PARSING_SESSION.set(this);
            long status;
            try {
                status = lib.galley_parse(handle, MemorySegment.NULL, len);
            } finally {
                if (prev != null) PARSING_SESSION.set(prev); else PARSING_SESSION.remove();
            }
            if (status < 0) throw errorFromStatus(status);
            return (int) status;
        }
        if (buffer.isDirect()) {
            MemorySegment dataSeg = MemorySegment.ofBuffer(buffer);
            Session prev = PARSING_SESSION.get();
            PARSING_SESSION.set(this);
            long status;
            try {
                status = lib.galley_parse(handle, dataSeg, len);
            } finally {
                if (prev != null) PARSING_SESSION.set(prev); else PARSING_SESSION.remove();
            }
            if (status < 0) throw errorFromStatus(status);
            return (int) status;
        } else {
            // Heap ByteBuffer: copy to native via arena
            byte[] tmp;
            if (buffer.hasArray()) {
                // Avoid modifying buffer position; copy slice
                int pos = buffer.position();
                int lim = buffer.limit();
                tmp = new byte[len];
                if (buffer.hasArray()) {
                    System.arraycopy(buffer.array(), buffer.arrayOffset() + pos, tmp, 0, len);
                } else {
                    ByteBuffer dup = buffer.duplicate();
                    dup.get(tmp);
                }
            } else {
                tmp = new byte[len];
                ByteBuffer dup = buffer.duplicate();
                dup.get(tmp);
            }
            try (Arena arena = Arena.ofConfined()) {
                MemorySegment dataSeg = arena.allocateFrom(ValueLayout.JAVA_BYTE, tmp);
                Session prev = PARSING_SESSION.get();
                PARSING_SESSION.set(this);
                long status;
                try {
                    status = lib.galley_parse(handle, dataSeg, len);
                } finally {
                    if (prev != null) PARSING_SESSION.set(prev); else PARSING_SESSION.remove();
                }
                if (status < 0) throw errorFromStatus(status);
                return (int) status;
            }
        }
    }

    public int parse(String input) {
        if (input == null) input = "";
        byte[] bytes = input.getBytes(StandardCharsets.UTF_8);
        return parse(bytes);
    }

    public int parseSentinel(String input) {
        return parse(input);
    }

    public int parseSentinel(byte[] input) {
        return parse(input);
    }

    public int parseSentinel(ByteBuffer buffer) {
        return parse(buffer);
    }

    public int parseFile(String path) {
        requireOpen();
        if (path == null) throw new IllegalArgumentException("path is null");
        Session prev = PARSING_SESSION.get();
        PARSING_SESSION.set(this);
        long status;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment cPath = arena.allocateFrom(path, StandardCharsets.UTF_8);
            status = lib.galley_parse_file(handle, cPath);
        } finally {
            if (prev != null) PARSING_SESSION.set(prev); else PARSING_SESSION.remove();
        }
        if (status < 0) throw errorFromStatus(status);
        return (int) status;
    }

    public int parseFile(File file) { return parseFile(file.getAbsolutePath()); }

    // -- arena --

    public long nodeCount() {
        requireOpen();
        return lib.galley_node_count(handle);
    }

    public void reserveNodes(long capacity) {
        requireOpen();
        long st = lib.galley_reserve_nodes(handle, capacity);
        checkStatus(st);
    }

    public long nodeCapacity() {
        requireOpen();
        return lib.galley_node_capacity(handle);
    }

    // -- navigation --

    public Node rootNode() {
        requireOpen();
        long addr = lib.galley_root_node(handle);
        if (addr == INVALID_NODE) return null;
        return new Node(this, addr);
    }

    public boolean nodeValid(long address) {
        requireOpen();
        return lib.galley_node_is_valid(handle, address) != 0;
    }

    public boolean nodeValid(Node node) {
        if (node == null) return false;
        if (node.getSession() != this) throw new IllegalArgumentException("node belongs to different session");
        return nodeValid(node.getAddress());
    }

    public int childCount(long address) {
        requireOpen();
        return lib.galley_node_child_count(handle, address);
    }

    public int childCount(Node node) {
        requireOpen();
        if (node == null) return 0;
        return childCount(node.getAddress());
    }

    public List<Node> children(Node node) {
        requireOpen();
        if (node == null) return new ArrayList<>();
        long addr = node.getAddress();
        int count = childCount(addr);
        List<Node> out = new ArrayList<>(count);
        long child = lib.galley_node_first_child(handle, addr);
        for (int i = 0; i < count; i++) {
            if (child == INVALID_NODE) throw new IllegalStateException("child count changed during iteration");
            out.add(new Node(this, child));
            child = lib.galley_node_next_sibling(handle, child);
        }
        return out;
    }

    public List<Node> children(long address) {
        requireOpen();
        int count = childCount(address);
        List<Node> out = new ArrayList<>(count);
        long child = lib.galley_node_first_child(handle, address);
        for (int i = 0; i < count; i++) {
            if (child == INVALID_NODE) throw new IllegalStateException("child count changed during iteration");
            out.add(new Node(this, child));
            child = lib.galley_node_next_sibling(handle, child);
        }
        return out;
    }

    private Node optNode(long addr) {
        if (addr == INVALID_NODE) return null;
        return new Node(this, addr);
    }

    public Node firstChild(Node node) {
        requireOpen();
        return optNode(lib.galley_node_first_child(handle, node.getAddress()));
    }

    public Node firstChild(long address) {
        requireOpen();
        return optNode(lib.galley_node_first_child(handle, address));
    }

    public Node lastChild(Node node) {
        requireOpen();
        return optNode(lib.galley_node_last_child(handle, node.getAddress()));
    }

    public Node lastChild(long address) {
        requireOpen();
        return optNode(lib.galley_node_last_child(handle, address));
    }

    public Node nextSibling(Node node) {
        requireOpen();
        return optNode(lib.galley_node_next_sibling(handle, node.getAddress()));
    }

    public Node nextSibling(long address) {
        requireOpen();
        return optNode(lib.galley_node_next_sibling(handle, address));
    }

    public Node priorSibling(Node node) {
        requireOpen();
        return optNode(lib.galley_node_prior_sibling(handle, node.getAddress()));
    }

    public Node priorSibling(long address) {
        requireOpen();
        return optNode(lib.galley_node_prior_sibling(handle, address));
    }

    public Node parent(Node node) {
        requireOpen();
        return optNode(lib.galley_node_parent(handle, node.getAddress()));
    }

    public Node parent(long address) {
        requireOpen();
        return optNode(lib.galley_node_parent(handle, address));
    }

    public byte[] symbolName(Node node) {
        requireOpen();
        if (node == null) return null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = lib.galley_node_symbol_name(handle, node.getAddress(), outData, outLen);
            if (st < 0) return null;
            MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
            long len = outLen.get(ValueLayout.JAVA_LONG, 0);
            if (ptr.equals(MemorySegment.NULL) || len == 0) return new byte[0];
            return ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
        }
    }

    public byte[] symbolName(long address) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = lib.galley_node_symbol_name(handle, address, outData, outLen);
            if (st < 0) return null;
            MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
            long len = outLen.get(ValueLayout.JAVA_LONG, 0);
            if (ptr.equals(MemorySegment.NULL) || len == 0) return new byte[0];
            return ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
        }
    }

    public byte[] text(Node node) {
        requireOpen();
        if (node == null) return null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = lib.galley_node_text(handle, node.getAddress(), outData, outLen);
            if (st < 0) return null;
            MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
            long len = outLen.get(ValueLayout.JAVA_LONG, 0);
            if (ptr.equals(MemorySegment.NULL) || len == 0) return new byte[0];
            return ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
        }
    }

    public byte[] text(long address) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = lib.galley_node_text(handle, address, outData, outLen);
            if (st < 0) return null;
            MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
            long len = outLen.get(ValueLayout.JAVA_LONG, 0);
            if (ptr.equals(MemorySegment.NULL) || len == 0) return new byte[0];
            return ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
        }
    }

    public long[] span(Node node) {
        requireOpen();
        if (node == null) return null;
        return span(node.getAddress());
    }

    public long[] span(long address) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outStart = arena.allocate(ValueLayout.JAVA_LONG);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = lib.galley_node_span(handle, address, outStart, outLen);
            if (st < 0) return null;
            return new long[]{outStart.get(ValueLayout.JAVA_LONG, 0), outLen.get(ValueLayout.JAVA_LONG, 0)};
        }
    }

    public int[] lineColumn(Node node) {
        requireOpen();
        if (node == null) return null;
        return lineColumn(node.getAddress());
    }

    public int[] lineColumn(long address) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outLine = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outCol = arena.allocate(ValueLayout.JAVA_INT);
            long st = lib.galley_node_line_column(handle, address, outLine, outCol);
            if (st < 0) return null;
            return new int[]{outLine.get(ValueLayout.JAVA_INT, 0), outCol.get(ValueLayout.JAVA_INT, 0)};
        }
    }

    public Integer variableIndex(Node node) {
        requireOpen();
        if (node == null) return null;
        long idx = lib.galley_node_variable_index(handle, node.getAddress());
        if (idx == -1) return null;
        if (idx < 0) throw errorFromStatus(idx);
        return (int) idx;
    }

    public Integer variableIndex(long address) {
        requireOpen();
        long idx = lib.galley_node_variable_index(handle, address);
        if (idx == -1) return null;
        if (idx < 0) throw errorFromStatus(idx);
        return (int) idx;
    }

    public int[] lastPosition() {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outLine = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outCol = arena.allocate(ValueLayout.JAVA_INT);
            long st = lib.galley_last_position(handle, outLine, outCol);
            if (st < 0) return null;
            return new int[]{outLine.get(ValueLayout.JAVA_INT, 0), outCol.get(ValueLayout.JAVA_INT, 0)};
        }
    }

    public boolean hasDiagnostic() {
        requireOpen();
        return lib.galley_has_diagnostic(handle) != 0;
    }

    public void setMessageOverride(String name, String message) {
        requireOpen();
        if (name == null || message == null) throw new IllegalArgumentException("name and message required");
        try (Arena arena = Arena.ofConfined()) {
            byte[] nameBytes = name.getBytes(StandardCharsets.UTF_8);
            byte[] msgBytes = message.getBytes(StandardCharsets.UTF_8);
            MemorySegment nameSeg = nameBytes.length == 0 ? MemorySegment.NULL : arena.allocateFrom(ValueLayout.JAVA_BYTE, nameBytes);
            MemorySegment msgSeg = msgBytes.length == 0 ? MemorySegment.NULL : arena.allocateFrom(ValueLayout.JAVA_BYTE, msgBytes);
            long st = lib.galley_session_set_message_override(handle,
                    nameSeg, nameBytes.length,
                    msgSeg, msgBytes.length);
            checkStatus(st);
        }
    }

    // -- diagnostics helpers --

    private Diagnostic buildDiagnosticSingular() {
        long kind = lib.galley_diagnostic_kind(handle);
        int line, col;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outLine = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outCol = arena.allocate(ValueLayout.JAVA_INT);
            lib.galley_diagnostic_position(handle, outLine, outCol);
            line = outLine.get(ValueLayout.JAVA_INT, 0);
            col = outCol.get(ValueLayout.JAVA_INT, 0);
        }

        String message = "";
        String messageAnsi = "";
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outMsg = arena.allocate(ValueLayout.ADDRESS);
            if (lib.galley_diagnostic_message(handle, outMsg) == 0) {
                MemorySegment p = outMsg.get(ValueLayout.ADDRESS, 0);
                if (!p.equals(MemorySegment.NULL)) message = p.reinterpret(Long.MAX_VALUE).getString(0);
            }
        }
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outMsg = arena.allocate(ValueLayout.ADDRESS);
            if (lib.galley_diagnostic_message_ansi(handle, outMsg) == 0) {
                MemorySegment p = outMsg.get(ValueLayout.ADDRESS, 0);
                if (!p.equals(MemorySegment.NULL)) messageAnsi = p.reinterpret(Long.MAX_VALUE).getString(0);
            }
        }

        byte[] unexpected = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            if (lib.galley_diagnostic_unexpected_token(handle, outData, outLen) == 0) {
                MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                if (!ptr.equals(MemorySegment.NULL) && len > 0) unexpected = ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
            }
        }

        List<byte[]> expected = new ArrayList<>();
        long expCount = lib.galley_diagnostic_expected_count(handle);
        if (expCount > 0) {
            for (long i = 0; i < expCount; i++) {
                try (Arena arena = Arena.ofConfined()) {
                    MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
                    MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
                    if (lib.galley_diagnostic_expected_at(handle, i, outData, outLen) == 0) {
                        MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                        long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                        if (!ptr.equals(MemorySegment.NULL)) {
                            byte[] b = len == 0 ? new byte[0] : ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
                            expected.add(b);
                        }
                    }
                }
            }
        }

        List<String> context = new ArrayList<>();
        long ctxCount = lib.galley_diagnostic_context_count(handle);
        if (ctxCount > 0) {
            for (long i = 0; i < ctxCount; i++) {
                try (Arena arena = Arena.ofConfined()) {
                    MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
                    MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
                    if (lib.galley_diagnostic_context_at(handle, i, outData, outLen) == 0) {
                        MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                        long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                        if (!ptr.equals(MemorySegment.NULL)) {
                            byte[] b = len == 0 ? new byte[0] : ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
                            context.add(new String(b, StandardCharsets.UTF_8));
                        }
                    }
                }
            }
        }

        long sec = lib.galley_syntax_error_count(handle);
        int syntaxErrorCount = sec < 0 ? 0 : (int) sec;

        long semc = lib.galley_semantic_error_count(handle);
        int semanticErrorCount = semc < 0 ? 0 : (int) semc;

        String[] semantic = readSemantic(-1, false);

        int[] indentation = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outSpaces = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outWidth = arena.allocate(ValueLayout.JAVA_INT);
            if (lib.galley_diagnostic_indentation(handle, outSpaces, outWidth) == 0) {
                indentation = new int[]{outSpaces.get(ValueLayout.JAVA_INT, 0), outWidth.get(ValueLayout.JAVA_INT, 0)};
            }
        }

        Integer recoveryKind = null;
        long rk = lib.galley_diagnostic_recovery_kind(handle);
        if (rk != 0) recoveryKind = (int) rk;

        byte[] recoveryTerminal = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            if (lib.galley_diagnostic_recovery_terminal(handle, outData, outLen) == 0) {
                MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                if (!ptr.equals(MemorySegment.NULL) && len > 0) recoveryTerminal = ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
                else if (ptr.equals(MemorySegment.NULL) || len == 0) recoveryTerminal = new byte[0];
                else recoveryTerminal = ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
            }
        }

        Integer recoveryResume = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outResume = arena.allocate(ValueLayout.JAVA_LONG);
            if (lib.galley_diagnostic_recovery_resume(handle, outResume) == 0) {
                recoveryResume = (int) outResume.get(ValueLayout.JAVA_LONG, 0);
            }
        }

        String recoveryLhs = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            if (lib.galley_diagnostic_recovery_lhs_variable(handle, outData, outLen) == 0) {
                MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                if (!ptr.equals(MemorySegment.NULL)) {
                    byte[] b = len == 0 ? new byte[0] : ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
                    recoveryLhs = new String(b, StandardCharsets.UTF_8);
                }
            }
        }

        Diagnostic.RecoveryProduction recoveryProd = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outVar = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outVarLen = arena.allocate(ValueLayout.JAVA_LONG);
            MemorySegment outIdx = arena.allocate(ValueLayout.JAVA_INT);
            if (lib.galley_diagnostic_recovery_production(handle, outVar, outVarLen, outIdx) == 0) {
                MemorySegment ptr = outVar.get(ValueLayout.ADDRESS, 0);
                long len = outVarLen.get(ValueLayout.JAVA_LONG, 0);
                int idx = outIdx.get(ValueLayout.JAVA_INT, 0);
                if (!ptr.equals(MemorySegment.NULL)) {
                    byte[] b = len == 0 ? new byte[0] : ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
                    recoveryProd = new Diagnostic.RecoveryProduction(new String(b, StandardCharsets.UTF_8), idx);
                }
            }
        }

        Diagnostic.RecoveryOccurrence recoveryOcc = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outParent = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outParentLen = arena.allocate(ValueLayout.JAVA_LONG);
            MemorySegment outRhs = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outSym = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outVar = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outVarLen = arena.allocate(ValueLayout.JAVA_LONG);
            if (lib.galley_diagnostic_recovery_occurrence(handle, outParent, outParentLen, outRhs, outSym, outVar, outVarLen) == 0) {
                MemorySegment pb = outParent.get(ValueLayout.ADDRESS, 0);
                long pl = outParentLen.get(ValueLayout.JAVA_LONG, 0);
                MemorySegment vb = outVar.get(ValueLayout.ADDRESS, 0);
                long vl = outVarLen.get(ValueLayout.JAVA_LONG, 0);
                byte[] pbytes = pb.equals(MemorySegment.NULL) || pl == 0 ? new byte[0] : pb.reinterpret(pl).toArray(ValueLayout.JAVA_BYTE);
                byte[] vbytes = vb.equals(MemorySegment.NULL) || vl == 0 ? new byte[0] : vb.reinterpret(vl).toArray(ValueLayout.JAVA_BYTE);
                recoveryOcc = new Diagnostic.RecoveryOccurrence(
                        new String(pbytes, StandardCharsets.UTF_8), outRhs.get(ValueLayout.JAVA_INT, 0), outSym.get(ValueLayout.JAVA_INT, 0), new String(vbytes, StandardCharsets.UTF_8));
            }
        }

        return new Diagnostic((int) kind, line, col, message, messageAnsi, unexpected, expected, context,
                syntaxErrorCount, semanticErrorCount, semantic, indentation, recoveryKind, recoveryTerminal, recoveryResume,
                recoveryLhs, recoveryProd, recoveryOcc);
    }

    private Diagnostic buildRecordedDiagnostic(long diagIndex) {
        int line, col;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outLine = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outCol = arena.allocate(ValueLayout.JAVA_INT);
            long st = lib.galley_recorded_diagnostic_position(handle, diagIndex, outLine, outCol);
            if (st < 0) return null;
            line = outLine.get(ValueLayout.JAVA_INT, 0);
            col = outCol.get(ValueLayout.JAVA_INT, 0);
        }

        long kind = lib.galley_recorded_diagnostic_kind(handle, diagIndex);

        String message = "";
        String messageAnsi = "";
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outMsg = arena.allocate(ValueLayout.ADDRESS);
            if (lib.galley_recorded_diagnostic_message(handle, diagIndex, outMsg) == 0) {
                MemorySegment p = outMsg.get(ValueLayout.ADDRESS, 0);
                if (!p.equals(MemorySegment.NULL)) message = p.reinterpret(Long.MAX_VALUE).getString(0);
                messageAnsi = message;
            }
        }

        byte[] unexpected = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            if (lib.galley_recorded_unexpected_token(handle, diagIndex, outData, outLen) == 0) {
                MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                if (!ptr.equals(MemorySegment.NULL) && len > 0) unexpected = ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
            }
        }

        List<byte[]> expected = new ArrayList<>();
        long expCount = lib.galley_recorded_expected_count(handle, diagIndex);
        if (expCount > 0) {
            for (long i = 0; i < expCount; i++) {
                try (Arena arena = Arena.ofConfined()) {
                    MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
                    MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
                    if (lib.galley_recorded_expected_token(handle, diagIndex, i, outData, outLen) == 0) {
                        MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                        long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                        if (!ptr.equals(MemorySegment.NULL)) {
                            byte[] b = len == 0 ? new byte[0] : ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
                            expected.add(b);
                        }
                    }
                }
            }
        }

        List<String> context = new ArrayList<>();
        long ctxCount = lib.galley_recorded_context_count(handle, diagIndex);
        if (ctxCount > 0) {
            for (long i = 0; i < ctxCount; i++) {
                try (Arena arena = Arena.ofConfined()) {
                    MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
                    MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
                    if (lib.galley_recorded_context_name(handle, diagIndex, i, outData, outLen) == 0) {
                        MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                        long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                        if (!ptr.equals(MemorySegment.NULL)) {
                            byte[] b = len == 0 ? new byte[0] : ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
                            context.add(new String(b, StandardCharsets.UTF_8));
                        }
                    }
                }
            }
        }

        int[] indentation = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outSpaces = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outWidth = arena.allocate(ValueLayout.JAVA_INT);
            if (lib.galley_recorded_indentation(handle, diagIndex, outSpaces, outWidth) == 0) {
                indentation = new int[]{outSpaces.get(ValueLayout.JAVA_INT, 0), outWidth.get(ValueLayout.JAVA_INT, 0)};
            }
        }

        Integer recoveryKind = null;
        long rk = lib.galley_recorded_diagnostic_recovery_kind(handle, diagIndex);
        if (rk != 0) recoveryKind = (int) rk;

        byte[] recoveryTerminal = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            if (lib.galley_recorded_recovery_terminal(handle, diagIndex, outData, outLen) == 0) {
                MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                if (!ptr.equals(MemorySegment.NULL) && len > 0) recoveryTerminal = ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
            }
        }

        Integer recoveryResume = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outResume = arena.allocate(ValueLayout.JAVA_LONG);
            if (lib.galley_recorded_recovery_resume(handle, diagIndex, outResume) == 0) {
                recoveryResume = (int) outResume.get(ValueLayout.JAVA_LONG, 0);
            }
        }

        String recoveryLhs = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            if (lib.galley_recorded_recovery_lhs_variable(handle, diagIndex, outData, outLen) == 0) {
                MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                if (!ptr.equals(MemorySegment.NULL)) {
                    byte[] b = len == 0 ? new byte[0] : ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
                    recoveryLhs = new String(b, StandardCharsets.UTF_8);
                }
            }
        }

        Diagnostic.RecoveryProduction recoveryProd = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outVar = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outVarLen = arena.allocate(ValueLayout.JAVA_LONG);
            MemorySegment outIdx = arena.allocate(ValueLayout.JAVA_INT);
            if (lib.galley_recorded_recovery_production(handle, diagIndex, outVar, outVarLen, outIdx) == 0) {
                MemorySegment ptr = outVar.get(ValueLayout.ADDRESS, 0);
                long len = outVarLen.get(ValueLayout.JAVA_LONG, 0);
                int idx = outIdx.get(ValueLayout.JAVA_INT, 0);
                if (!ptr.equals(MemorySegment.NULL)) {
                    byte[] b = len == 0 ? new byte[0] : ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
                    recoveryProd = new Diagnostic.RecoveryProduction(new String(b, StandardCharsets.UTF_8), idx);
                }
            }
        }

        Diagnostic.RecoveryOccurrence recoveryOcc = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outParent = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outParentLen = arena.allocate(ValueLayout.JAVA_LONG);
            MemorySegment outRhs = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outSym = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outVar = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outVarLen = arena.allocate(ValueLayout.JAVA_LONG);
            if (lib.galley_recorded_recovery_occurrence(handle, diagIndex, outParent, outParentLen, outRhs, outSym, outVar, outVarLen) == 0) {
                MemorySegment pb = outParent.get(ValueLayout.ADDRESS, 0);
                long pl = outParentLen.get(ValueLayout.JAVA_LONG, 0);
                MemorySegment vb = outVar.get(ValueLayout.ADDRESS, 0);
                long vl = outVarLen.get(ValueLayout.JAVA_LONG, 0);
                byte[] pbytes = pb.equals(MemorySegment.NULL) || pl == 0 ? new byte[0] : pb.reinterpret(pl).toArray(ValueLayout.JAVA_BYTE);
                byte[] vbytes = vb.equals(MemorySegment.NULL) || vl == 0 ? new byte[0] : vb.reinterpret(vl).toArray(ValueLayout.JAVA_BYTE);
                recoveryOcc = new Diagnostic.RecoveryOccurrence(
                        new String(pbytes, StandardCharsets.UTF_8), outRhs.get(ValueLayout.JAVA_INT, 0), outSym.get(ValueLayout.JAVA_INT, 0), new String(vbytes, StandardCharsets.UTF_8));
            }
        }

        return new Diagnostic((int) kind, line, col, message, messageAnsi, unexpected, expected, context,
                0, 0, readSemantic(diagIndex, true), indentation, recoveryKind, recoveryTerminal, recoveryResume,
                recoveryLhs, recoveryProd, recoveryOcc);
    }

    private String[] readSemantic(long diagIndex, boolean recorded) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outVar = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outVarLen = arena.allocate(ValueLayout.JAVA_LONG);
            MemorySegment outMsg = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outMsgLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = recorded
                    ? lib.galley_recorded_semantic(handle, diagIndex, outVar, outVarLen, outMsg, outMsgLen)
                    : lib.galley_diagnostic_semantic(handle, outVar, outVarLen, outMsg, outMsgLen);
            if (st != 0) return null;
            MemorySegment vb = outVar.get(ValueLayout.ADDRESS, 0);
            long vl = outVarLen.get(ValueLayout.JAVA_LONG, 0);
            MemorySegment mb = outMsg.get(ValueLayout.ADDRESS, 0);
            long ml = outMsgLen.get(ValueLayout.JAVA_LONG, 0);
            if (vb.equals(MemorySegment.NULL) || mb.equals(MemorySegment.NULL)) return null;
            return new String[]{
                    new String(vb.reinterpret(vl).toArray(ValueLayout.JAVA_BYTE), StandardCharsets.UTF_8),
                    new String(mb.reinterpret(ml).toArray(ValueLayout.JAVA_BYTE), StandardCharsets.UTF_8)};
        }
    }

    public Diagnostic diagnostic() {
        requireOpen();
        if (lib.galley_has_diagnostic(handle) == 0) return null;
        return buildDiagnosticSingular();
    }

    public List<Diagnostic> diagnostics() {
        requireOpen();
        long count = lib.galley_recorded_diagnostic_count(handle);
        if (count <= 0) return new ArrayList<>();
        List<Diagnostic> out = new ArrayList<>((int) count);
        for (long i = 0; i < count; i++) {
            Diagnostic d = buildRecordedDiagnostic(i);
            if (d != null) out.add(d);
        }
        return out;
    }

    // -- tree editing --

    public void appendChildren(Node parent, Node chain) {
        requireOpen();
        checkStatus(lib.galley_tree_append_children(handle, parent.getAddress(), chain.getAddress()));
    }

    public void appendChildren(long parentAddr, long chainAddr) {
        requireOpen();
        checkStatus(lib.galley_tree_append_children(handle, parentAddr, chainAddr));
    }

    public void insertBefore(Node target, Node chain) {
        requireOpen();
        checkStatus(lib.galley_tree_insert_before(handle, target.getAddress(), chain.getAddress()));
    }

    public void insertAfter(Node target, Node chain) {
        requireOpen();
        checkStatus(lib.galley_tree_insert_after(handle, target.getAddress(), chain.getAddress()));
    }

    public Node removeSiblings(Node node, int count) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outHead = arena.allocate(ValueLayout.JAVA_LONG);
            outHead.set(ValueLayout.JAVA_LONG, 0, INVALID_NODE);
            long st = lib.galley_tree_remove_siblings(handle, node.getAddress(), count, outHead);
            checkStatus(st);
            long head = outHead.get(ValueLayout.JAVA_LONG, 0);
            if (head == INVALID_NODE) return null;
            return new Node(this, head);
        }
    }

    public Node removeSelf(Node node) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outHead = arena.allocate(ValueLayout.JAVA_LONG);
            outHead.set(ValueLayout.JAVA_LONG, 0, INVALID_NODE);
            long st = lib.galley_tree_remove_self(handle, node.getAddress(), outHead);
            checkStatus(st);
            long head = outHead.get(ValueLayout.JAVA_LONG, 0);
            if (head == INVALID_NODE) return null;
            return new Node(this, head);
        }
    }

    public Node promoteChildrenOverWrapper(Node wrapper) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outHead = arena.allocate(ValueLayout.JAVA_LONG);
            outHead.set(ValueLayout.JAVA_LONG, 0, INVALID_NODE);
            long st = lib.galley_tree_promote_children_over_wrapper(handle, wrapper.getAddress(), outHead);
            checkStatus(st);
            long head = outHead.get(ValueLayout.JAVA_LONG, 0);
            if (head == INVALID_NODE) return null;
            return new Node(this, head);
        }
    }

    public Node cleanChildren(Node node) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outHead = arena.allocate(ValueLayout.JAVA_LONG);
            outHead.set(ValueLayout.JAVA_LONG, 0, INVALID_NODE);
            long st = lib.galley_tree_clean_children(handle, node.getAddress(), outHead);
            checkStatus(st);
            long head = outHead.get(ValueLayout.JAVA_LONG, 0);
            if (head == INVALID_NODE) return null;
            return new Node(this, head);
        }
    }

    public void unlinkWrapper(Node wrapper) {
        requireOpen();
        checkStatus(lib.galley_tree_unlink_wrapper(handle, wrapper.getAddress()));
    }

    public void insertChildrenAt(Node parent, int index, Node chain) {
        requireOpen();
        checkStatus(lib.galley_tree_insert_children_at(handle, parent.getAddress(), index, chain.getAddress()));
    }

    public Node removeChildrenAt(Node parent, int index, int count) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outHead = arena.allocate(ValueLayout.JAVA_LONG);
            outHead.set(ValueLayout.JAVA_LONG, 0, INVALID_NODE);
            long st = lib.galley_tree_remove_children_at(handle, parent.getAddress(), index, count, outHead);
            checkStatus(st);
            long head = outHead.get(ValueLayout.JAVA_LONG, 0);
            if (head == INVALID_NODE) return null;
            return new Node(this, head);
        }
    }

    // -- symbol table --

    public byte[] symbolNameAt(long index) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = lib.galley_symbol_name(handle, index, outData, outLen);
            if (st < 0) return null;
            MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
            long len = outLen.get(ValueLayout.JAVA_LONG, 0);
            if (ptr.equals(MemorySegment.NULL) || len == 0) return new byte[0];
            return ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
        }
    }

    public boolean symbolIsTerminal(long index) {
        requireOpen();
        return lib.galley_symbol_is_terminal(handle, index) != 0;
    }

    public byte[] variableNameAt(long index) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = lib.galley_variable_name(handle, index, outData, outLen);
            if (st < 0) return null;
            MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
            long len = outLen.get(ValueLayout.JAVA_LONG, 0);
            if (ptr.equals(MemorySegment.NULL) || len == 0) return new byte[0];
            return ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
        }
    }

    // Expose handle for internal use
    MemorySegment getHandle() { return handle; }
    GalleyLibrary getLibrary() { return lib; }
}
