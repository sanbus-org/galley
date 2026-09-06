/**
 * Read-only snapshot of a parse diagnostic.
 * All `Uint8Array` fields are copies that remain valid after the next parse.
 */

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
