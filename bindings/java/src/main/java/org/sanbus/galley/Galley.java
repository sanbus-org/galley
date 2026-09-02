package org.sanbus.galley;

import org.sanbus.galley.internal.GalleyLibrary;
import org.sanbus.galley.internal.GalleyLibraryLoader;

/**
 * Module-level queries mirroring galley.h and the Python/TypeScript bindings.
 */
public final class Galley {
    public static final int PARSER_TYPE_LL = 0;
    public static final int PARSER_TYPE_LR = 1;

    public static final int RECOVERY_MODE_DISABLED = 0;
    public static final int RECOVERY_MODE_AUTOMATIC = 1;
    public static final int RECOVERY_MODE_EXPLICIT = 2;

    public static final int KIND_NONE = 0;
    public static final int KIND_SYNTAX = 1;
    public static final int KIND_INDENTATION = 2;

    public static final int RECOVERY_TARGET_NONE = 0;
    public static final int RECOVERY_TARGET_LHS_VARIABLE = 1;
    public static final int RECOVERY_TARGET_PRODUCTION = 2;
    public static final int RECOVERY_TARGET_OCCURRENCE = 3;

    public static final int RESUME_BEFORE = 0;
    public static final int RESUME_AFTER = 1;

    public static final long INVALID_NODE = 0xFFFFFFFFFFFFFFFFL;

    private Galley() {}

    private static GalleyLibrary lib(String path) {
        return path != null ? GalleyLibraryLoader.load(path) : GalleyLibraryLoader.load();
    }

    public static String version() { return lib(null).galley_version(); }
    public static String version(String libraryPath) { return lib(libraryPath).galley_version(); }

    public static int parserType() { return (int) lib(null).galley_parser_type(); }
    public static int parserType(String libraryPath) { return (int) lib(libraryPath).galley_parser_type(); }

    public static int errorRecoveryMode() { return (int) lib(null).galley_error_recovery_mode(); }
    public static int errorRecoveryMode(String libraryPath) { return (int) lib(libraryPath).galley_error_recovery_mode(); }

    public static boolean hasAst() { return lib(null).galley_has_ast() != 0; }
    public static boolean hasAst(String libraryPath) { return lib(libraryPath).galley_has_ast() != 0; }

    public static boolean hasProcedures() { return lib(null).galley_has_procedures() != 0; }
    public static boolean hasProcedures(String libraryPath) { return lib(libraryPath).galley_has_procedures() != 0; }

    public static boolean allowsNoAstTreeProcedures() { return lib(null).galley_allows_no_ast_tree_procedures() != 0; }
    public static boolean sourceRetentionEnabled() { return lib(null).galley_source_retention_enabled() != 0; }
    public static boolean hasPositionTracking() { return lib(null).galley_has_position_tracking() != 0; }
    public static boolean hasInputStreaming() { return lib(null).galley_has_input_streaming() != 0; }
    public static boolean usesVerbatim() { return lib(null).galley_uses_verbatim() != 0; }
    public static boolean stackOverflowRecoveryAvailable() { return lib(null).galley_stack_overflow_recovery_available() != 0; }

    public static long symbolCount() { return lib(null).galley_symbol_count(); }
    public static long variableCount() { return lib(null).galley_variable_count(); }

    public static String statusString(long status) { return lib(null).galley_status_string(status); }

    // Legacy snake_case aliases for parity with Python docs
    public static boolean has_ast() { return hasAst(); }
    public static boolean has_procedures() { return hasProcedures(); }
    public static boolean has_position_tracking() { return hasPositionTracking(); }
}
