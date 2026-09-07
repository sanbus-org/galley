/**
 * Read-only snapshot of a parse diagnostic.
 * All `Uint8Array` fields are copies that remain valid after the next parse.
 */

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
  kind: number; // KIND_*
  line: number; // 1-based
  column: number;
  message: string; // plain text
  messageAnsi: string; // with ANSI
  unexpectedToken: Uint8Array | null; // syntax only
  expectedTokens: Uint8Array[]; // syntax only
  context: string[]; // innermost-first variable names, syntax only
  syntaxErrorCount: number;
  semanticErrorCount: number;
  semantic: [string, string] | null; // (variable, message) for semantic errors
  indentation: [number, number] | null; // (spaces, width) for indentation errors
  recoveryKind: number | null; // RECOVERY_TARGET_*
  recoveryTerminal: Uint8Array | null;
  recoveryResume: number | null; // RESUME_*
  recoveryLhsVariable: string | null;
  recoveryProduction: [string, number] | null; // (variable, rhs_index)
  recoveryOccurrence: [string, number, number, string] | null; // (parent, rhs, symbol, variable)
}
