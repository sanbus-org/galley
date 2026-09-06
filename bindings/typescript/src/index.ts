/**
 * Galley TypeScript bindings — public surface.
 *
 * Mirrors the layout of `bindings/python/galley.pyi` and the C header
 * `bindings/c/galley.h`. The FFI boundary lives in `ffi.ts`; everything
 * else is typed, idiomatic TypeScript.
 */

import { loadLibrary, findLibrary } from "./ffi.js";
import { Session, Walker } from "./session.js";
import type { WalkStep } from "./session.js";
import { Node } from "./node.js";
import { GalleyError } from "./errors.js";
import type { Diagnostic } from "./diagnostic.js";
import * as constants from "./constants.js";
import {
  installProcedure,
  installProcedures,
  clearProcedures,
  listProcedures,
  ProcedureArguments,
} from "./procedures.js";

// Re-exports
export { Session, Walker, Node, GalleyError, ProcedureArguments, installProcedure, installProcedures, clearProcedures, listProcedures };
export type { Diagnostic, WalkStep };
export * from "./constants.js";

// Module-level queries (mirror galley.h)
export function version(): string {
  return loadLibrary().galley_version();
}

export function parserType(): number {
  const v = loadLibrary().galley_parser_type();
  return typeof v === "bigint" ? Number(v) : (v as number);
}

export function errorRecoveryMode(): number {
  const v = loadLibrary().galley_error_recovery_mode();
  return typeof v === "bigint" ? Number(v) : (v as number);
}

export function hasAst(): boolean {
  return loadLibrary().galley_has_ast() !== 0;
}

export function hasProcedures(): boolean {
  return loadLibrary().galley_has_procedures() !== 0;
}

export function allowsNoAstTreeProcedures(): boolean {
  return loadLibrary().galley_allows_no_ast_tree_procedures() !== 0;
}

export function sourceRetentionEnabled(): boolean {
  return loadLibrary().galley_source_retention_enabled() !== 0;
}

export function hasPositionTracking(): boolean {
  return loadLibrary().galley_has_position_tracking() !== 0;
}

export function hasInputStreaming(): boolean {
  return loadLibrary().galley_has_input_streaming() !== 0;
}

export function usesVerbatim(): boolean {
  return loadLibrary().galley_uses_verbatim() !== 0;
}

export function stackOverflowRecoveryAvailable(): boolean {
  return loadLibrary().galley_stack_overflow_recovery_available() !== 0;
}

export function symbolCount(): number {
  const v = loadLibrary().galley_symbol_count();
  return typeof v === "bigint" ? Number(v) : (v as number);
}

export function variableCount(): number {
  const v = loadLibrary().galley_variable_count();
  return typeof v === "bigint" ? Number(v) : (v as number);
}

export function statusString(status: number): string | null {
  return loadLibrary().galley_status_string(status);
}

// Preserve original Python naming aliases for docs parity
export const has_ast = hasAst;
export const has_procedures = hasProcedures;
export const has_position_tracking = hasPositionTracking;
