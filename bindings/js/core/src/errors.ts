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
