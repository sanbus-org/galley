/**
 * Galley JavaScript core — runtime-neutral public surface.
 *
 * Each adapter package (`galley-js-node`, `galley-js-bun`, `galley-js-deno`)
 * binds these classes to its {@link FfiPort} and re-exports them.
 */

import { Session, Walker } from "./session.js";
import type { SessionOptions, WalkStep } from "./session.js";
import { Node } from "./node.js";
import { GalleyError } from "./errors.js";
import type { Diagnostic } from "./diagnostic.js";
import type { FfiPort, Handle, SessionCOptions, WalkedStep, DispatchHandler } from "./port.js";
import {
  installProcedure,
  installProcedures,
  clearProcedures,
  listProcedures,
  ProcedureArguments,
  dispatchProcedure,
  setParsingSession,
  getParsingSession,
} from "./procedures.js";
import type { HookFn } from "./procedures.js";
import { encodeUtf8, decodeUtf8, byteLengthUtf8 } from "./text.js";

export {
  Session,
  Walker,
  Node,
  GalleyError,
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
export type { Diagnostic, WalkStep, SessionOptions, FfiPort, Handle, SessionCOptions, WalkedStep, DispatchHandler, HookFn };
export * from "./constants.js";
