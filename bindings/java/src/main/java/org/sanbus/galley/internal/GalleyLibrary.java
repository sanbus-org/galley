package org.sanbus.galley.internal;

import java.lang.foreign.*;
import java.lang.invoke.MethodHandle;
import java.nio.charset.StandardCharsets;
import java.util.Optional;

/**
 * Panama FFI over bindings/c/galley.h — replaces JNA.
 * Java 22+ (java.lang.foreign finalized). No third-party runtime.
 */
public final class GalleyLibrary {

    // GalleyCOptions layout (40 bytes, align 8) — mirrors galley.h:104
    // Do not use structLayout with automatic padding (fails alignment on JDK 26); write at fixed offsets.
    public static final long GALLEY_COPTIONS_SIZE = 40;
    public static final long OFF_MAX_ERRORS = 0;
    public static final long OFF_RECOVERY_WINDOW = 4;
    public static final long OFF_STACK_OVERFLOW_RECOVERY = 8;
    public static final long OFF_SYNTAX_ERROR_STACK_DEPTH = 12;
    public static final long OFF_VERBOSITY = 16;
    public static final long OFF_AST_PREALLOCATION_RATIO = 24; // 4 bytes padding after verbosity
    public static final long OFF_AST_PREALLOCATION_CAP = 32;

    private static final Linker LINKER = Linker.nativeLinker();

    private final SymbolLookup lookup;
    private final Arena libraryArena;

    // Downcall handles
    private final MethodHandle mh_galley_version;
    private final MethodHandle mh_galley_parser_type;
    private final MethodHandle mh_galley_error_recovery_mode;
    private final MethodHandle mh_galley_has_ast;
    private final MethodHandle mh_galley_has_procedures;
    private final MethodHandle mh_galley_allows_no_ast_tree_procedures;
    private final MethodHandle mh_galley_source_retention_enabled;
    private final MethodHandle mh_galley_has_position_tracking;
    private final MethodHandle mh_galley_has_input_streaming;
    private final MethodHandle mh_galley_uses_verbatim;
    private final MethodHandle mh_galley_stack_overflow_recovery_available;
    private final MethodHandle mh_galley_symbol_count;
    private final MethodHandle mh_galley_variable_count;
    private final MethodHandle mh_galley_status_string;
    private final MethodHandle mh_galley_symbol_name;
    private final MethodHandle mh_galley_symbol_is_terminal;
    private final MethodHandle mh_galley_variable_name;
    private final MethodHandle mh_galley_session_create;
    private final MethodHandle mh_galley_session_create_ex;
    private final MethodHandle mh_galley_session_destroy;
    private final MethodHandle mh_galley_session_set_message_override;
    private final MethodHandle mh_galley_parse;
    private final MethodHandle mh_galley_parse_sentinel;
    private final MethodHandle mh_galley_parse_file;
    private final MethodHandle mh_galley_last_position;
    private final MethodHandle mh_galley_node_count;
    private final MethodHandle mh_galley_reserve_nodes;
    private final MethodHandle mh_galley_node_capacity;
    private final MethodHandle mh_galley_root_node;
    private final MethodHandle mh_galley_node_is_valid;
    private final MethodHandle mh_galley_node_child_count;
    private final MethodHandle mh_galley_node_first_child;
    private final MethodHandle mh_galley_node_last_child;
    private final MethodHandle mh_galley_node_next_sibling;
    private final MethodHandle mh_galley_node_prior_sibling;
    private final MethodHandle mh_galley_node_parent;
    private final MethodHandle mh_galley_node_symbol_name;
    private final MethodHandle mh_galley_node_text;
    private final MethodHandle mh_galley_node_span;
    private final MethodHandle mh_galley_node_line_column;
    private final MethodHandle mh_galley_node_variable_index;
    private final MethodHandle mh_galley_has_diagnostic;
    private final MethodHandle mh_galley_diagnostic_kind;
    private final MethodHandle mh_galley_diagnostic_message;
    private final MethodHandle mh_galley_diagnostic_message_ansi;
    private final MethodHandle mh_galley_diagnostic_position;
    private final MethodHandle mh_galley_diagnostic_unexpected_token;
    private final MethodHandle mh_galley_diagnostic_expected_count;
    private final MethodHandle mh_galley_diagnostic_expected_at;
    private final MethodHandle mh_galley_diagnostic_context_count;
    private final MethodHandle mh_galley_diagnostic_context_at;
    private final MethodHandle mh_galley_diagnostic_indentation;
    private final MethodHandle mh_galley_syntax_error_count;
    private final MethodHandle mh_galley_diagnostic_recovery_kind;
    private final MethodHandle mh_galley_diagnostic_recovery_terminal;
    private final MethodHandle mh_galley_diagnostic_recovery_resume;
    private final MethodHandle mh_galley_diagnostic_recovery_lhs_variable;
    private final MethodHandle mh_galley_diagnostic_recovery_production;
    private final MethodHandle mh_galley_diagnostic_recovery_occurrence;
    private final MethodHandle mh_galley_recorded_diagnostic_count;
    private final MethodHandle mh_galley_recorded_diagnostic_kind;
    private final MethodHandle mh_galley_recorded_diagnostic_position;
    private final MethodHandle mh_galley_recorded_unexpected_token;
    private final MethodHandle mh_galley_recorded_diagnostic_message;
    private final MethodHandle mh_galley_recorded_indentation;
    private final MethodHandle mh_galley_recorded_expected_count;
    private final MethodHandle mh_galley_recorded_expected_token;
    private final MethodHandle mh_galley_recorded_context_count;
    private final MethodHandle mh_galley_recorded_context_name;
    private final MethodHandle mh_galley_recorded_diagnostic_recovery_kind;
    private final MethodHandle mh_galley_recorded_recovery_terminal;
    private final MethodHandle mh_galley_recorded_recovery_resume;
    private final MethodHandle mh_galley_recorded_recovery_lhs_variable;
    private final MethodHandle mh_galley_recorded_recovery_production;
    private final MethodHandle mh_galley_recorded_recovery_occurrence;
    private final MethodHandle mh_galley_tree_append_children;
    private final MethodHandle mh_galley_tree_insert_before;
    private final MethodHandle mh_galley_tree_insert_after;
    private final MethodHandle mh_galley_tree_remove_siblings;
    private final MethodHandle mh_galley_tree_remove_self;
    private final MethodHandle mh_galley_tree_promote_children_over_wrapper;
    private final MethodHandle mh_galley_tree_clean_children;
    private final MethodHandle mh_galley_tree_unlink_wrapper;
    private final MethodHandle mh_galley_tree_insert_children_at;
    private final MethodHandle mh_galley_tree_remove_children_at;
    private final MethodHandle mh_galley_procedure_session;
    private final MethodHandle mh_galley_procedure_current_node;
    private final MethodHandle mh_galley_procedure_set_current_node;
    private final MethodHandle mh_galley_procedure_drop_self;
    private final MethodHandle mh_galley_procedure_drop_children;
    private final MethodHandle mh_galley_procedure_drop_if_empty;
    private final MethodHandle mh_galley_procedure_replace_with_children;
    private final MethodHandle mh_galley_procedure_context_line;
    private final MethodHandle mh_galley_procedure_context_column;
    private final MethodHandle mh_galley_install_java_dispatch; // may be null if symbol missing

    // Upcall stub for Java dispatch
    private MemorySegment dispatchStub = MemorySegment.NULL;
    private Arena dispatchArena = null;

    public GalleyLibrary(String libraryPath) {
        this.libraryArena = Arena.global();
        this.lookup = SymbolLookup.libraryLookup(libraryPath, libraryArena);
        // Helper to lookup
        this.mh_galley_version = downcall("galley_version", FunctionDescriptor.of(ValueLayout.ADDRESS));
        this.mh_galley_parser_type = downcall("galley_parser_type", FunctionDescriptor.of(ValueLayout.JAVA_LONG));
        this.mh_galley_error_recovery_mode = downcall("galley_error_recovery_mode", FunctionDescriptor.of(ValueLayout.JAVA_LONG));
        this.mh_galley_has_ast = downcall("galley_has_ast", FunctionDescriptor.of(ValueLayout.JAVA_INT));
        this.mh_galley_has_procedures = downcall("galley_has_procedures", FunctionDescriptor.of(ValueLayout.JAVA_INT));
        this.mh_galley_allows_no_ast_tree_procedures = downcall("galley_allows_no_ast_tree_procedures", FunctionDescriptor.of(ValueLayout.JAVA_INT));
        this.mh_galley_source_retention_enabled = downcall("galley_source_retention_enabled", FunctionDescriptor.of(ValueLayout.JAVA_INT));
        this.mh_galley_has_position_tracking = downcall("galley_has_position_tracking", FunctionDescriptor.of(ValueLayout.JAVA_INT));
        this.mh_galley_has_input_streaming = downcall("galley_has_input_streaming", FunctionDescriptor.of(ValueLayout.JAVA_INT));
        this.mh_galley_uses_verbatim = downcall("galley_uses_verbatim", FunctionDescriptor.of(ValueLayout.JAVA_INT));
        this.mh_galley_stack_overflow_recovery_available = downcall("galley_stack_overflow_recovery_available", FunctionDescriptor.of(ValueLayout.JAVA_INT));
        this.mh_galley_symbol_count = downcall("galley_symbol_count", FunctionDescriptor.of(ValueLayout.JAVA_LONG));
        this.mh_galley_variable_count = downcall("galley_variable_count", FunctionDescriptor.of(ValueLayout.JAVA_LONG));
        this.mh_galley_status_string = downcall("galley_status_string", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.mh_galley_symbol_name = downcall("galley_symbol_name", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_symbol_is_terminal = downcall("galley_symbol_is_terminal", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.mh_galley_variable_name = downcall("galley_variable_name", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_session_create = downcall("galley_session_create", FunctionDescriptor.of(ValueLayout.ADDRESS));
        this.mh_galley_session_create_ex = downcall("galley_session_create_ex", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_session_destroy = downcall("galley_session_destroy", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        this.mh_galley_session_set_message_override = downcall("galley_session_set_message_override", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.mh_galley_parse = downcall("galley_parse", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.mh_galley_parse_sentinel = downcall("galley_parse_sentinel", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_parse_file = downcall("galley_parse_file", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_last_position = downcall("galley_last_position", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_node_count = downcall("galley_node_count", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.mh_galley_reserve_nodes = downcall("galley_reserve_nodes", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.mh_galley_node_capacity = downcall("galley_node_capacity", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.mh_galley_root_node = downcall("galley_root_node", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.mh_galley_node_is_valid = downcall("galley_node_is_valid", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.mh_galley_node_child_count = downcall("galley_node_child_count", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.mh_galley_node_first_child = downcall("galley_node_first_child", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.mh_galley_node_last_child = downcall("galley_node_last_child", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.mh_galley_node_next_sibling = downcall("galley_node_next_sibling", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.mh_galley_node_prior_sibling = downcall("galley_node_prior_sibling", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.mh_galley_node_parent = downcall("galley_node_parent", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.mh_galley_node_symbol_name = downcall("galley_node_symbol_name", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_node_text = downcall("galley_node_text", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_node_span = downcall("galley_node_span", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_node_line_column = downcall("galley_node_line_column", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_node_variable_index = downcall("galley_node_variable_index", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.mh_galley_has_diagnostic = downcall("galley_has_diagnostic", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.mh_galley_diagnostic_kind = downcall("galley_diagnostic_kind", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.mh_galley_diagnostic_message = downcall("galley_diagnostic_message", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_diagnostic_message_ansi = downcall("galley_diagnostic_message_ansi", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_diagnostic_position = downcall("galley_diagnostic_position", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_diagnostic_unexpected_token = downcall("galley_diagnostic_unexpected_token", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_diagnostic_expected_count = downcall("galley_diagnostic_expected_count", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.mh_galley_diagnostic_expected_at = downcall("galley_diagnostic_expected_at", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_diagnostic_context_count = downcall("galley_diagnostic_context_count", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.mh_galley_diagnostic_context_at = downcall("galley_diagnostic_context_at", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_diagnostic_indentation = downcall("galley_diagnostic_indentation", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_syntax_error_count = downcall("galley_syntax_error_count", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.mh_galley_diagnostic_recovery_kind = downcall("galley_diagnostic_recovery_kind", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.mh_galley_diagnostic_recovery_terminal = downcall("galley_diagnostic_recovery_terminal", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_diagnostic_recovery_resume = downcall("galley_diagnostic_recovery_resume", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_diagnostic_recovery_lhs_variable = downcall("galley_diagnostic_recovery_lhs_variable", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_diagnostic_recovery_production = downcall("galley_diagnostic_recovery_production", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_diagnostic_recovery_occurrence = downcall("galley_diagnostic_recovery_occurrence", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_recorded_diagnostic_count = downcall("galley_recorded_diagnostic_count", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.mh_galley_recorded_diagnostic_kind = downcall("galley_recorded_diagnostic_kind", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.mh_galley_recorded_diagnostic_position = downcall("galley_recorded_diagnostic_position", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_recorded_unexpected_token = downcall("galley_recorded_unexpected_token", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_recorded_diagnostic_message = downcall("galley_recorded_diagnostic_message", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.mh_galley_recorded_indentation = downcall("galley_recorded_indentation", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_recorded_expected_count = downcall("galley_recorded_expected_count", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.mh_galley_recorded_expected_token = downcall("galley_recorded_expected_token", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_recorded_context_count = downcall("galley_recorded_context_count", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.mh_galley_recorded_context_name = downcall("galley_recorded_context_name", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_recorded_diagnostic_recovery_kind = downcall("galley_recorded_diagnostic_recovery_kind", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.mh_galley_recorded_recovery_terminal = downcall("galley_recorded_recovery_terminal", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_recorded_recovery_resume = downcall("galley_recorded_recovery_resume", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.mh_galley_recorded_recovery_lhs_variable = downcall("galley_recorded_recovery_lhs_variable", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_recorded_recovery_production = downcall("galley_recorded_recovery_production", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_recorded_recovery_occurrence = downcall("galley_recorded_recovery_occurrence", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_tree_append_children = downcall("galley_tree_append_children", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.JAVA_LONG));
        this.mh_galley_tree_insert_before = downcall("galley_tree_insert_before", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.JAVA_LONG));
        this.mh_galley_tree_insert_after = downcall("galley_tree_insert_after", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.JAVA_LONG));
        this.mh_galley_tree_remove_siblings = downcall("galley_tree_remove_siblings", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.mh_galley_tree_remove_self = downcall("galley_tree_remove_self", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.mh_galley_tree_promote_children_over_wrapper = downcall("galley_tree_promote_children_over_wrapper", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.mh_galley_tree_clean_children = downcall("galley_tree_clean_children", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.mh_galley_tree_unlink_wrapper = downcall("galley_tree_unlink_wrapper", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.mh_galley_tree_insert_children_at = downcall("galley_tree_insert_children_at", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.JAVA_LONG, ValueLayout.JAVA_LONG));
        this.mh_galley_tree_remove_children_at = downcall("galley_tree_remove_children_at", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.JAVA_LONG, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.mh_galley_procedure_session = downcall("galley_procedure_session", FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        this.mh_galley_procedure_current_node = downcall("galley_procedure_current_node", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.mh_galley_procedure_set_current_node = downcall("galley_procedure_set_current_node", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        this.mh_galley_procedure_drop_self = downcall("galley_procedure_drop_self", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.mh_galley_procedure_drop_children = downcall("galley_procedure_drop_children", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.mh_galley_procedure_drop_if_empty = downcall("galley_procedure_drop_if_empty", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.mh_galley_procedure_replace_with_children = downcall("galley_procedure_replace_with_children", FunctionDescriptor.of(ValueLayout.JAVA_LONG, ValueLayout.ADDRESS));
        this.mh_galley_procedure_context_line = downcall("galley_procedure_context_line", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.mh_galley_procedure_context_column = downcall("galley_procedure_context_column", FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        this.mh_galley_install_java_dispatch = downcallOptional("galley_install_java_dispatch", FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
    }

    private MethodHandle downcall(String name, FunctionDescriptor descriptor) {
        return LINKER.downcallHandle(lookup.find(name).orElseThrow(() -> new IllegalStateException("missing symbol: " + name)), descriptor);
    }

    private MethodHandle downcallOptional(String name, FunctionDescriptor descriptor) {
        Optional<MemorySegment> sym = lookup.find(name);
        if (sym.isEmpty()) return null;
        return LINKER.downcallHandle(sym.get(), descriptor);
    }

    // --- version / metadata ---
    public String galley_version() {
        try {
            MemorySegment addr = (MemorySegment) mh_galley_version.invoke();
            if (addr.equals(MemorySegment.NULL)) return null;
            return addr.reinterpret(Long.MAX_VALUE).getString(0);
        } catch (Throwable t) { throw new RuntimeException(t); }
    }

    public long galley_parser_type() {
        try { return (long) mh_galley_parser_type.invoke(); } catch (Throwable t) { throw new RuntimeException(t); }
    }
    public long galley_error_recovery_mode() {
        try { return (long) mh_galley_error_recovery_mode.invoke(); } catch (Throwable t) { throw new RuntimeException(t); }
    }
    public int galley_has_ast() { try { return (int) mh_galley_has_ast.invoke(); } catch (Throwable t) { throw new RuntimeException(t); } }
    public int galley_has_procedures() { try { return (int) mh_galley_has_procedures.invoke(); } catch (Throwable t) { throw new RuntimeException(t); } }
    public int galley_allows_no_ast_tree_procedures() { try { return (int) mh_galley_allows_no_ast_tree_procedures.invoke(); } catch (Throwable t) { throw new RuntimeException(t); } }
    public int galley_source_retention_enabled() { try { return (int) mh_galley_source_retention_enabled.invoke(); } catch (Throwable t) { throw new RuntimeException(t); } }
    public int galley_has_position_tracking() { try { return (int) mh_galley_has_position_tracking.invoke(); } catch (Throwable t) { throw new RuntimeException(t); } }
    public int galley_has_input_streaming() { try { return (int) mh_galley_has_input_streaming.invoke(); } catch (Throwable t) { throw new RuntimeException(t); } }
    public int galley_uses_verbatim() { try { return (int) mh_galley_uses_verbatim.invoke(); } catch (Throwable t) { throw new RuntimeException(t); } }
    public int galley_stack_overflow_recovery_available() { try { return (int) mh_galley_stack_overflow_recovery_available.invoke(); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_symbol_count() { try { return (long) mh_galley_symbol_count.invoke(); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_variable_count() { try { return (long) mh_galley_variable_count.invoke(); } catch (Throwable t) { throw new RuntimeException(t); } }
    public String galley_status_string(long status) {
        try {
            MemorySegment addr = (MemorySegment) mh_galley_status_string.invoke(status);
            if (addr.equals(MemorySegment.NULL)) return null;
            return addr.reinterpret(Long.MAX_VALUE).getString(0);
        } catch (Throwable t) { throw new RuntimeException(t); }
    }

    // symbol table
    public long galley_symbol_name(MemorySegment session, long index, MemorySegment outData, MemorySegment outLen) {
        try { return (long) mh_galley_symbol_name.invoke(session, index, outData, outLen); } catch (Throwable t) { throw new RuntimeException(t); }
    }
    public int galley_symbol_is_terminal(MemorySegment session, long index) {
        try { return (int) mh_galley_symbol_is_terminal.invoke(session, index); } catch (Throwable t) { throw new RuntimeException(t); }
    }
    public long galley_variable_name(MemorySegment session, long index, MemorySegment outData, MemorySegment outLen) {
        try { return (long) mh_galley_variable_name.invoke(session, index, outData, outLen); } catch (Throwable t) { throw new RuntimeException(t); }
    }

    // session
    public MemorySegment galley_session_create() {
        try { return (MemorySegment) mh_galley_session_create.invoke(); } catch (Throwable t) { throw new RuntimeException(t); }
    }
    public MemorySegment galley_session_create_ex(MemorySegment options) {
        try {
            if (options.equals(MemorySegment.NULL)) return (MemorySegment) mh_galley_session_create_ex.invoke(MemorySegment.NULL);
            return (MemorySegment) mh_galley_session_create_ex.invoke(options);
        } catch (Throwable t) { throw new RuntimeException(t); }
    }
    public void galley_session_destroy(MemorySegment session) {
        try { mh_galley_session_destroy.invoke(session); } catch (Throwable t) { throw new RuntimeException(t); }
    }
    public long galley_session_set_message_override(MemorySegment session, MemorySegment name, long nameLen, MemorySegment message, long messageLen) {
        try { return (long) mh_galley_session_set_message_override.invoke(session, name, nameLen, message, messageLen); } catch (Throwable t) { throw new RuntimeException(t); }
    }

    // parse
    public long galley_parse(MemorySegment session, MemorySegment data, long len) {
        try { return (long) mh_galley_parse.invoke(session, data, len); } catch (Throwable t) { throw new RuntimeException(t); }
    }
    public long galley_parse_sentinel(MemorySegment session, MemorySegment input) {
        try { return (long) mh_galley_parse_sentinel.invoke(session, input); } catch (Throwable t) { throw new RuntimeException(t); }
    }
    public long galley_parse_file(MemorySegment session, MemorySegment path) {
        try { return (long) mh_galley_parse_file.invoke(session, path); } catch (Throwable t) { throw new RuntimeException(t); }
    }
    public long galley_last_position(MemorySegment session, MemorySegment outLine, MemorySegment outColumn) {
        try { return (long) mh_galley_last_position.invoke(session, outLine, outColumn); } catch (Throwable t) { throw new RuntimeException(t); }
    }

    // node / tree
    public long galley_node_count(MemorySegment session) { try { return (long) mh_galley_node_count.invoke(session); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_reserve_nodes(MemorySegment session, long capacity) { try { return (long) mh_galley_reserve_nodes.invoke(session, capacity); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_node_capacity(MemorySegment session) { try { return (long) mh_galley_node_capacity.invoke(session); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_root_node(MemorySegment session) { try { return (long) mh_galley_root_node.invoke(session); } catch (Throwable t) { throw new RuntimeException(t); } }
    public int galley_node_is_valid(MemorySegment session, long node) { try { return (int) mh_galley_node_is_valid.invoke(session, node); } catch (Throwable t) { throw new RuntimeException(t); } }
    public int galley_node_child_count(MemorySegment session, long node) { try { return (int) mh_galley_node_child_count.invoke(session, node); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_node_first_child(MemorySegment session, long node) { try { return (long) mh_galley_node_first_child.invoke(session, node); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_node_last_child(MemorySegment session, long node) { try { return (long) mh_galley_node_last_child.invoke(session, node); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_node_next_sibling(MemorySegment session, long node) { try { return (long) mh_galley_node_next_sibling.invoke(session, node); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_node_prior_sibling(MemorySegment session, long node) { try { return (long) mh_galley_node_prior_sibling.invoke(session, node); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_node_parent(MemorySegment session, long node) { try { return (long) mh_galley_node_parent.invoke(session, node); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_node_symbol_name(MemorySegment session, long node, MemorySegment outData, MemorySegment outLen) { try { return (long) mh_galley_node_symbol_name.invoke(session, node, outData, outLen); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_node_text(MemorySegment session, long node, MemorySegment outData, MemorySegment outLen) { try { return (long) mh_galley_node_text.invoke(session, node, outData, outLen); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_node_span(MemorySegment session, long node, MemorySegment outStart, MemorySegment outLen) { try { return (long) mh_galley_node_span.invoke(session, node, outStart, outLen); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_node_line_column(MemorySegment session, long node, MemorySegment outLine, MemorySegment outColumn) { try { return (long) mh_galley_node_line_column.invoke(session, node, outLine, outColumn); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_node_variable_index(MemorySegment session, long node) { try { return (long) mh_galley_node_variable_index.invoke(session, node); } catch (Throwable t) { throw new RuntimeException(t); } }

    // diagnostics (singular)
    public int galley_has_diagnostic(MemorySegment session) { try { return (int) mh_galley_has_diagnostic.invoke(session); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_diagnostic_kind(MemorySegment session) { try { return (long) mh_galley_diagnostic_kind.invoke(session); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_diagnostic_message(MemorySegment session, MemorySegment out) { try { return (long) mh_galley_diagnostic_message.invoke(session, out); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_diagnostic_message_ansi(MemorySegment session, MemorySegment out) { try { return (long) mh_galley_diagnostic_message_ansi.invoke(session, out); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_diagnostic_position(MemorySegment session, MemorySegment outLine, MemorySegment outColumn) { try { return (long) mh_galley_diagnostic_position.invoke(session, outLine, outColumn); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_diagnostic_unexpected_token(MemorySegment session, MemorySegment outData, MemorySegment outLen) { try { return (long) mh_galley_diagnostic_unexpected_token.invoke(session, outData, outLen); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_diagnostic_expected_count(MemorySegment session) { try { return (long) mh_galley_diagnostic_expected_count.invoke(session); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_diagnostic_expected_at(MemorySegment session, long index, MemorySegment outData, MemorySegment outLen) { try { return (long) mh_galley_diagnostic_expected_at.invoke(session, index, outData, outLen); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_diagnostic_context_count(MemorySegment session) { try { return (long) mh_galley_diagnostic_context_count.invoke(session); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_diagnostic_context_at(MemorySegment session, long index, MemorySegment outData, MemorySegment outLen) { try { return (long) mh_galley_diagnostic_context_at.invoke(session, index, outData, outLen); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_diagnostic_indentation(MemorySegment session, MemorySegment outSpaces, MemorySegment outWidth) { try { return (long) mh_galley_diagnostic_indentation.invoke(session, outSpaces, outWidth); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_syntax_error_count(MemorySegment session) { try { return (long) mh_galley_syntax_error_count.invoke(session); } catch (Throwable t) { throw new RuntimeException(t); } }

    // recovery (singular)
    public long galley_diagnostic_recovery_kind(MemorySegment session) { try { return (long) mh_galley_diagnostic_recovery_kind.invoke(session); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_diagnostic_recovery_terminal(MemorySegment session, MemorySegment outData, MemorySegment outLen) { try { return (long) mh_galley_diagnostic_recovery_terminal.invoke(session, outData, outLen); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_diagnostic_recovery_resume(MemorySegment session, MemorySegment out) { try { return (long) mh_galley_diagnostic_recovery_resume.invoke(session, out); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_diagnostic_recovery_lhs_variable(MemorySegment session, MemorySegment outData, MemorySegment outLen) { try { return (long) mh_galley_diagnostic_recovery_lhs_variable.invoke(session, outData, outLen); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_diagnostic_recovery_production(MemorySegment session, MemorySegment outVar, MemorySegment outLen, MemorySegment outIndex) { try { return (long) mh_galley_diagnostic_recovery_production.invoke(session, outVar, outLen, outIndex); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_diagnostic_recovery_occurrence(MemorySegment session, MemorySegment outParent, MemorySegment outParentLen, MemorySegment outRhs, MemorySegment outSym, MemorySegment outVar, MemorySegment outVarLen) { try { return (long) mh_galley_diagnostic_recovery_occurrence.invoke(session, outParent, outParentLen, outRhs, outSym, outVar, outVarLen); } catch (Throwable t) { throw new RuntimeException(t); } }

    // recorded
    public long galley_recorded_diagnostic_count(MemorySegment session) { try { return (long) mh_galley_recorded_diagnostic_count.invoke(session); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_recorded_diagnostic_kind(MemorySegment session, long idx) { try { return (long) mh_galley_recorded_diagnostic_kind.invoke(session, idx); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_recorded_diagnostic_position(MemorySegment session, long idx, MemorySegment outLine, MemorySegment outColumn) { try { return (long) mh_galley_recorded_diagnostic_position.invoke(session, idx, outLine, outColumn); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_recorded_unexpected_token(MemorySegment session, long idx, MemorySegment outData, MemorySegment outLen) { try { return (long) mh_galley_recorded_unexpected_token.invoke(session, idx, outData, outLen); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_recorded_diagnostic_message(MemorySegment session, long idx, MemorySegment out) { try { return (long) mh_galley_recorded_diagnostic_message.invoke(session, idx, out); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_recorded_indentation(MemorySegment session, long idx, MemorySegment outSpaces, MemorySegment outWidth) { try { return (long) mh_galley_recorded_indentation.invoke(session, idx, outSpaces, outWidth); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_recorded_expected_count(MemorySegment session, long idx) { try { return (long) mh_galley_recorded_expected_count.invoke(session, idx); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_recorded_expected_token(MemorySegment session, long idx, long tokenIdx, MemorySegment outData, MemorySegment outLen) { try { return (long) mh_galley_recorded_expected_token.invoke(session, idx, tokenIdx, outData, outLen); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_recorded_context_count(MemorySegment session, long idx) { try { return (long) mh_galley_recorded_context_count.invoke(session, idx); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_recorded_context_name(MemorySegment session, long idx, long ctxIdx, MemorySegment outData, MemorySegment outLen) { try { return (long) mh_galley_recorded_context_name.invoke(session, idx, ctxIdx, outData, outLen); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_recorded_diagnostic_recovery_kind(MemorySegment session, long idx) { try { return (long) mh_galley_recorded_diagnostic_recovery_kind.invoke(session, idx); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_recorded_recovery_terminal(MemorySegment session, long idx, MemorySegment outData, MemorySegment outLen) { try { return (long) mh_galley_recorded_recovery_terminal.invoke(session, idx, outData, outLen); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_recorded_recovery_resume(MemorySegment session, long idx, MemorySegment out) { try { return (long) mh_galley_recorded_recovery_resume.invoke(session, idx, out); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_recorded_recovery_lhs_variable(MemorySegment session, long idx, MemorySegment outData, MemorySegment outLen) { try { return (long) mh_galley_recorded_recovery_lhs_variable.invoke(session, idx, outData, outLen); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_recorded_recovery_production(MemorySegment session, long idx, MemorySegment outVar, MemorySegment outLen, MemorySegment outIdx) { try { return (long) mh_galley_recorded_recovery_production.invoke(session, idx, outVar, outLen, outIdx); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_recorded_recovery_occurrence(MemorySegment session, long idx, MemorySegment outParent, MemorySegment outParentLen, MemorySegment outRhs, MemorySegment outSym, MemorySegment outVar, MemorySegment outVarLen) { try { return (long) mh_galley_recorded_recovery_occurrence.invoke(session, idx, outParent, outParentLen, outRhs, outSym, outVar, outVarLen); } catch (Throwable t) { throw new RuntimeException(t); } }

    // tree editing
    public long galley_tree_append_children(MemorySegment session, long parent, long first) { try { return (long) mh_galley_tree_append_children.invoke(session, parent, first); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_tree_insert_before(MemorySegment session, long target, long first) { try { return (long) mh_galley_tree_insert_before.invoke(session, target, first); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_tree_insert_after(MemorySegment session, long target, long first) { try { return (long) mh_galley_tree_insert_after.invoke(session, target, first); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_tree_remove_siblings(MemorySegment session, long node, long count, MemorySegment outHead) { try { return (long) mh_galley_tree_remove_siblings.invoke(session, node, count, outHead); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_tree_remove_self(MemorySegment session, long node, MemorySegment outHead) { try { return (long) mh_galley_tree_remove_self.invoke(session, node, outHead); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_tree_promote_children_over_wrapper(MemorySegment session, long wrapper, MemorySegment outHead) { try { return (long) mh_galley_tree_promote_children_over_wrapper.invoke(session, wrapper, outHead); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_tree_clean_children(MemorySegment session, long node, MemorySegment outHead) { try { return (long) mh_galley_tree_clean_children.invoke(session, node, outHead); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_tree_unlink_wrapper(MemorySegment session, long wrapper) { try { return (long) mh_galley_tree_unlink_wrapper.invoke(session, wrapper); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_tree_insert_children_at(MemorySegment session, long parent, long index, long first) { try { return (long) mh_galley_tree_insert_children_at.invoke(session, parent, index, first); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_tree_remove_children_at(MemorySegment session, long parent, long index, long count, MemorySegment outHead) { try { return (long) mh_galley_tree_remove_children_at.invoke(session, parent, index, count, outHead); } catch (Throwable t) { throw new RuntimeException(t); } }

    // procedure hook state
    public MemorySegment galley_procedure_session(MemorySegment args) { try { return (MemorySegment) mh_galley_procedure_session.invoke(args); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_procedure_current_node(MemorySegment args) { try { return (long) mh_galley_procedure_current_node.invoke(args); } catch (Throwable t) { throw new RuntimeException(t); } }
    public void galley_procedure_set_current_node(MemorySegment args, long node) { try { mh_galley_procedure_set_current_node.invoke(args, node); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_procedure_drop_self(MemorySegment args) { try { return (long) mh_galley_procedure_drop_self.invoke(args); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_procedure_drop_children(MemorySegment args) { try { return (long) mh_galley_procedure_drop_children.invoke(args); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_procedure_drop_if_empty(MemorySegment args) { try { return (long) mh_galley_procedure_drop_if_empty.invoke(args); } catch (Throwable t) { throw new RuntimeException(t); } }
    public long galley_procedure_replace_with_children(MemorySegment args) { try { return (long) mh_galley_procedure_replace_with_children.invoke(args); } catch (Throwable t) { throw new RuntimeException(t); } }
    public int galley_procedure_context_line(MemorySegment args) { try { return (int) mh_galley_procedure_context_line.invoke(args); } catch (Throwable t) { throw new RuntimeException(t); } }
    public int galley_procedure_context_column(MemorySegment args) { try { return (int) mh_galley_procedure_context_column.invoke(args); } catch (Throwable t) { throw new RuntimeException(t); } }

    // procedure dispatch
    public void galley_install_java_dispatch(MemorySegment target) {
        if (mh_galley_install_java_dispatch == null) return;
        try { mh_galley_install_java_dispatch.invoke(target); } catch (Throwable t) { throw new RuntimeException(t); }
    }

    // Upcall stub management
    public MemorySegment createJavaDispatchStub(java.lang.invoke.MethodHandle dispatchHandle, Arena arena) {
        FunctionDescriptor desc = FunctionDescriptor.ofVoid(ValueLayout.ADDRESS, ValueLayout.JAVA_LONG, ValueLayout.ADDRESS);
        return LINKER.upcallStub(dispatchHandle, desc, arena);
    }
}
