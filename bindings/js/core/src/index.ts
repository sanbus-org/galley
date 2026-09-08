/**
 * Galley JavaScript core — runtime-neutral public surface.
 *
 * Each adapter package (`@sanbus/galley-node`, `@sanbus/galley-bun`, `@sanbus/galley-deno`)
 * binds these classes to its {@link FfiPort} and re-exports them.
 */

import { Session, Walker } from "./session.ts";
import type { SessionOptions, WalkStep } from "./session.ts";
import { Node } from "./node.ts";
import { GalleyError, MissingArtifactError } from "./errors.ts";
import { resolveArtifact, artifactFileName, wasmArtifactFileName } from "./artifact.ts";
import type { ArtifactHost } from "./artifact.ts";
import type { Diagnostic } from "./diagnostic.ts";
import { displayTokenName } from "./diagnostic.ts";
import type { FfiPort, Handle, SessionCOptions, TreeSnapshot, WalkedStep, DispatchHandler } from "./port.ts";
import {
  installProcedure,
  installProcedures,
  clearProcedures,
  listProcedures,
  ProcedureArguments,
  dispatchProcedure,
  setParsingSession,
  getParsingSession,
} from "./procedures.ts";
import type { HookFn } from "./procedures.ts";
import { encodeUtf8, decodeUtf8, byteLengthUtf8 } from "./text.ts";

export {
  Session,
  Walker,
  Node,
  GalleyError,
  MissingArtifactError,
  resolveArtifact,
  artifactFileName,
  wasmArtifactFileName,
  displayTokenName,
  ProcedureArguments,
  installProcedure,
  installProcedures,
  clearProcedures,
  listProcedures,
  dispatchProcedure,
  setParsingSession,
  getParsingSession,
  encodeUtf8,
  decodeUtf8,
  byteLengthUtf8,
};
export type { Diagnostic, WalkStep, SessionOptions, FfiPort, Handle, SessionCOptions, TreeSnapshot, WalkedStep, DispatchHandler, HookFn, ArtifactHost };
export * from "./constants.ts";
