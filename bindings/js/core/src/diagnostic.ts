/**
 * Read-only snapshot of a parse diagnostic: every field is readonly
 * and the whole snapshot — array fields included — freezes when it
 * rides on a thrown `GalleyError`; byte contents are read-only by
 * convention (the language cannot freeze typed-array elements).
 * All `Uint8Array` fields are copies that remain valid after the next parse.
 */

import type { Kind, RecoveryTarget, Resume } from "./constants.ts";

/**
 * Display name for the synthetic control-byte terminals (end of input and
 * the indentation pair), which never occur as user-typable input. Exact
 * full-token match only; anything else returns null and the caller keeps
 * its existing rendering.
 *
 * Mirrors `tokenDisplayName` in `src/runtime/string.zig` until the general
 * per-grammar mechanism arrives; keep the two tables in sync.
 */
export function displayTokenName(token: Uint8Array): string | null {
  if (token.length !== 1) return null;
  switch (token[0]) {
    case 0x00:
      return "End of input";
    case 0x01:
      return "Indent";
    case 0x02:
      return "Dedent";
    default:
      return null;
  }
}

export interface Diagnostic {
  readonly kind: Kind;
  readonly line: number; // 1-based
  readonly column: number;
  readonly message: string; // plain text
  readonly messageAnsi: string; // with ANSI
  readonly unexpectedToken: Uint8Array | null; // syntax only
  readonly expectedTokens: Uint8Array[]; // syntax only
  readonly context: string[]; // innermost-first variable names, syntax only
  readonly syntaxErrorCount: number;
  readonly semanticErrorCount: number;
  readonly semantic: [string, string] | null; // (variable, message) for semantic errors
  readonly indentation: [number, number] | null; // (spaces, width) for indentation errors
  readonly recoveryKind: RecoveryTarget | null;
  readonly recoveryTerminal: Uint8Array | null;
  readonly recoveryResume: Resume | null;
  readonly recoveryLhsVariable: string | null;
  readonly recoveryProduction: [string, number] | null; // (variable, rhs_index)
  readonly recoveryOccurrence: [string, number, number, string] | null; // (parent, rhs, symbol, variable)
}
