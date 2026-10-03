/**
 * Galley JavaScript core — runtime-neutral public surface.
 *
 * Each adapter package (`@sanbus/galley-node`, `@sanbus/galley-bun`, `@sanbus/galley-deno`)
 * binds these classes to its {@link FfiPort} and re-exports them.
 */

import { Session, Walker } from "./session.ts";
import type { SessionOptions, TreeSnapshot, WalkStep } from "./session.ts";
import { Parser } from "./parser.ts";
import { Node } from "./node.ts";
import { GalleyError, MissingArtifactError, SessionClosedError, StaleTreeError } from "./errors.ts";
import type { ArtifactHost } from "./artifact.ts";
import type { Diagnostic } from "./diagnostic.ts";
import type { FfiPort, Handle, SessionCOptions, SnapshotColumns, DispatchHandler } from "./port.ts";
import { NATIVE_LITTLE_ENDIAN } from "./port.ts";
import { ProcedureArguments } from "./procedures.ts";
import type { ProcedureRegistry } from "./procedures.ts";
import type { HookFn, ProceduresOption } from "./procedures.ts";

export {
  Session,
  Walker,
  Node,
  Parser,
  GalleyError,
  MissingArtifactError,
  SessionClosedError,
  StaleTreeError,
  ProcedureArguments,
  NATIVE_LITTLE_ENDIAN,
};
export type { Diagnostic, WalkStep, TreeSnapshot, SessionOptions, FfiPort, Handle, SessionCOptions, SnapshotColumns, DispatchHandler, HookFn, ProceduresOption, ArtifactHost, ProcedureRegistry };
export * from "./constants.ts";
