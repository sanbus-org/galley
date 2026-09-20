/**
 * Enumerations mirroring `bindings/c/galley.h` status and kind families.
 * These are the single source for JavaScript consumers; they must stay
 * in sync with the C header.
 */

export const INVALID_NODE = 0xffffffffffffffffn; // 2^64-1

/** Status codes (negative = failure). */
export enum Status {
  Ok = 0,
  ErrorNullArgument = -1,
  ErrorSyntax = -2,
  ErrorIndentation = -3,
  ErrorStackOverflow = -4,
  ErrorAstCapacityExceeded = -5,
  ErrorUnterminatedRawString = -6,
  ErrorOutOfMemory = -7,
  ErrorInternal = -8,
  ErrorNoDiagnostic = -9,
  ErrorInvalidNode = -10,
  ErrorIo = -11,
  ErrorSemantic = -12,
}

/** Parser families. */
export enum ParserType {
  Ll = 0,
  Lr = 1,
}

/** Recovery modes. */
export enum RecoveryMode {
  Disabled = 0,
  Automatic = 1,
  Explicit = 2,
}

/** Diagnostic kinds. */
export enum Kind {
  None = 0,
  Syntax = 1,
  Indentation = 2,
  Semantic = 3,
}

/** Recovery targets. */
export enum RecoveryTarget {
  None = 0,
  LhsVariable = 1,
  Production = 2,
  Occurrence = 3,
}

/** Resume sides. */
export enum Resume {
  Before = 0,
  After = 1,
}
