import type { Diagnostic } from "./diagnostic.ts";
import type { Status } from "./constants.ts";

/**
 * Freeze the snapshot when the failure is created, one level deep:
 * the diagnostic object plus every array field it holds
 * (`expectedTokens`, `context`, and the recovery tuples), so no holder
 * can push into or reshape them. Byte fields stay `Uint8Array`s
 * because `Object.freeze` throws on non-empty typed arrays; their
 * contents are read-only by convention, and each failure builds fresh
 * copies, so a write can only ever corrupt the holder's own snapshot —
 * never session state.
 */
function freezeSnapshot(diagnostic: Diagnostic): Diagnostic {
  for (const value of Object.values(diagnostic)) {
    if (Array.isArray(value)) Object.freeze(value);
  }
  return Object.freeze(diagnostic);
}

/**
 * Failure reported by a Galley operation.
 * Mirrors Python's `galley.Error` (code + diagnostic snapshot).
 * `code` is the named status, never a bare integer: status codes cross
 * as named values in every host.
 */
export class GalleyError extends Error {
  readonly code: Status;
  /** Frozen when the failure is created: object and array fields frozen, text never changes. */
  readonly diagnostic: Diagnostic | null;

  constructor(
    message: string,
    code: Status,
    diagnostic: Diagnostic | null = null,
  ) {
    super(message);
    this.name = "GalleyError";
    this.code = code;
    this.diagnostic = diagnostic === null ? null : freezeSnapshot(diagnostic);
  }
}

/**
 * Use after close: the session, or a node bound to it, is already
 * closed. Thrown instead of a generic error so catch sites can name
 * the failure instead of matching message text.
 */
export class SessionClosedError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SessionClosedError";
  }

  /** True for closed-session failures even across duplicated installs. */
  static is(error: unknown): error is SessionClosedError {
    if (error instanceof SessionClosedError) return true;
    return (
      typeof error === "object" &&
      error !== null &&
      (error as { name?: unknown }).name === "SessionClosedError"
    );
  }
}

const MISSING_ARTIFACT_CODE = "galley:missing-artifact";

/**
 * The parser artifact a binding was told to load is not where it was told.
 * Thrown by every adapter's artifact resolution instead of searching
 * elsewhere. The universal loader catches exactly this class to try the
 * next engine; anything else propagates loudly.
 */
export class MissingArtifactError extends Error {
  readonly code = MISSING_ARTIFACT_CODE;

  constructor(detail: string, buildHint: string) {
    super(`galley: parser artifact not found: ${detail}.\n${buildHint}`);
    this.name = "MissingArtifactError";
  }

  /** True for missing-artifact failures even across duplicated installs. */
  static is(error: unknown): error is MissingArtifactError {
    if (error instanceof MissingArtifactError) return true;
    return (
      typeof error === "object" &&
      error !== null &&
      (error as { name?: unknown }).name === "MissingArtifactError" &&
      (error as { code?: unknown }).code === MISSING_ARTIFACT_CODE
    );
  }
}
