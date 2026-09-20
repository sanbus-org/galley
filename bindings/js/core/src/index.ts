/**
 * Galley JavaScript core — runtime-neutral public surface.
 *
 * Each adapter package (`@sanbus/galley-node`, `@sanbus/galley-bun`, `@sanbus/galley-deno`)
 * binds these classes to its {@link FfiPort} and re-exports them.
 */

import { Session, Walker } from "./session.ts";
import type { SessionOptions, WalkStep } from "./session.ts";
import { Language } from "./language.ts";
import { Node } from "./node.ts";
import { GalleyError, MissingArtifactError, SessionClosedError } from "./errors.ts";
import type { ArtifactHost } from "./artifact.ts";
import type { Diagnostic } from "./diagnostic.ts";
import type { FfiPort, Handle, SessionCOptions, TreeSnapshot, WalkedStep, DispatchHandler } from "./port.ts";
import { ProcedureArguments } from "./procedures.ts";
import type { ProcedureRegistry } from "./procedures.ts";
import type { HookFn, ProceduresOption } from "./procedures.ts";

export {
  Session,
  Walker,
  Node,
  Language,
  GalleyError,
  MissingArtifactError,
  SessionClosedError,
  ProcedureArguments,
};
export type { Diagnostic, WalkStep, SessionOptions, FfiPort, Handle, SessionCOptions, TreeSnapshot, WalkedStep, DispatchHandler, HookFn, ProceduresOption, ArtifactHost, ProcedureRegistry };
export * from "./constants.ts";
