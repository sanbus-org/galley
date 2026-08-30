import type { Diagnostic } from "./diagnostic.js";

/**
 * Failure reported by a Galley operation.
 * Mirrors Python's `galley.Error` (code + diagnostic snapshot).
 */
export class GalleyError extends Error {
  readonly code: number;
  readonly diagnostic: Diagnostic | null;

  constructor(
    message: string,
    code: number,
    diagnostic: Diagnostic | null = null,
  ) {
    super(message);
    this.name = "GalleyError";
    this.code = code;
    this.diagnostic = diagnostic;
  }
}
