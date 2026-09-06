/**
 * Constants mirroring `bindings/c/galley.h` status and kind enumerations.
 * These are the single source for JavaScript consumers; they must stay
 * in sync with the C header.
 */

export const INVALID_NODE = 0xffffffffffffffffn; // 2^64-1

// Status codes (negative = failure)
export const STATUS_OK = 0;
export const STATUS_ERROR_NULL_ARGUMENT = -1;
export const STATUS_ERROR_SYNTAX = -2;
export const STATUS_ERROR_INDENTATION = -3;
export const STATUS_ERROR_STACK_OVERFLOW = -4;
export const STATUS_ERROR_AST_CAPACITY_EXCEEDED = -5;
export const STATUS_ERROR_UNTERMINATED_RAW_STRING = -6;
export const STATUS_ERROR_OUT_OF_MEMORY = -7;
export const STATUS_ERROR_INTERNAL = -8;
export const STATUS_ERROR_NO_DIAGNOSTIC = -9;
export const STATUS_ERROR_INVALID_NODE = -10;
export const STATUS_ERROR_IO = -11;
export const STATUS_ERROR_SEMANTIC = -12;

// Parser families
export const PARSER_TYPE_LL = 0;
export const PARSER_TYPE_LR = 1;

// Recovery modes
export const RECOVERY_MODE_DISABLED = 0;
export const RECOVERY_MODE_AUTOMATIC = 1;
export const RECOVERY_MODE_EXPLICIT = 2;

// Diagnostic kinds
export const KIND_NONE = 0;
export const KIND_SYNTAX = 1;
export const KIND_INDENTATION = 2;
export const KIND_SEMANTIC = 3;

// Recovery targets
export const RECOVERY_TARGET_NONE = 0;
export const RECOVERY_TARGET_LHS_VARIABLE = 1;
export const RECOVERY_TARGET_PRODUCTION = 2;
export const RECOVERY_TARGET_OCCURRENCE = 3;

// Resume sides
export const RESUME_BEFORE = 0;
export const RESUME_AFTER = 1;
