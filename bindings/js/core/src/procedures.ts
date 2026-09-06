/**
 * Host-language procedure registry for the JavaScript bindings.
 *
 * Runtime-neutral: the registry, `ProcedureArguments`, and the dispatcher
 * live here. Each adapter installs the dispatcher into its shared library
 * through its own native callback (`galley_install_*_dispatch`) and calls
 * {@link dispatchProcedure} with the decoded hook name.
 *
 * Hooks receive a `ProcedureArguments` object. Tree queries use
 * `currentNode()` plus the ordinary `Node` methods (which call the port's
 * node accessors on the parsing session).
 */

import { INVALID_NODE } from "./constants.js";
import type { Handle, FfiPort } from "./port.js";
import { encodeUtf8 } from "./text.js";
import { Node } from "./node.js";
import type { Session } from "./session.js";

export class ProcedureArguments {
  readonly #args: Handle;
  readonly #session: Session | null;
  readonly #port: FfiPort;

  constructor(args: Handle, session: Session | null, port: FfiPort) {
    this.#args = args;
    this.#session = session;
    this.#port = port;
  }

  get session(): Session | null {
    return this.#session;
  }

  currentNode(): Node | null {
    if (this.#session === null || this.#session.isClosed) return null;
    const address = this.#port.procCurrentNode(this.#args);
    if (address === INVALID_NODE) return null;
    return new Node(this.#session, address);
  }

  setCurrentNode(node: Node | bigint): void {
    const address = typeof node === "bigint" ? node : node.address;
    this.#port.procSetCurrentNode(this.#args, address);
  }

  dropSelf(): void {
    if (this.#port.procDropSelf(this.#args) < 0) {
      throw new Error("galley_procedure_drop_self failed");
    }
  }

  dropChildren(): void {
    if (this.#port.procDropChildren(this.#args) < 0) {
      throw new Error("galley_procedure_drop_children failed");
    }
  }

  dropIfEmpty(): void {
    if (this.#port.procDropIfEmpty(this.#args) < 0) {
      throw new Error("galley_procedure_drop_if_empty failed");
    }
  }

  replaceWithChildren(): void {
    if (this.#port.procReplaceWithChildren(this.#args) < 0) {
      throw new Error("galley_procedure_replace_with_children failed");
    }
  }

  currentLine(): number {
    return this.#port.procContextLine(this.#args);
  }

  currentColumn(): number {
    return this.#port.procContextColumn(this.#args);
  }

  /**
   * Record a semantic error on the current node and return the running
   * total. Parsing continues; a syntax-clean parse with any semantic
   * error fails with status -12.
   */
  reportSemanticError(message: string): number {
    const status = this.#port.procReportSemanticError(this.#args, encodeUtf8(message));
    if (status < 0) throw new Error("galley_procedure_report_semantic_error failed");
    return status;
  }
}

export type HookFn = (args: ProcedureArguments) => void;

let currentSession: Session | null = null;

/** Records the Session whose parse is in flight so hooks can wrap Nodes. */
export function setParsingSession(session: Session | null): Session | null {
  const previous = currentSession;
  currentSession = session;
  return previous;
}

/** Session of the parse currently in flight, if any. */
export function getParsingSession(): Session | null {
  return currentSession;
}

const registry = new Map<string, HookFn>();

function isProcedureName(name: string): boolean {
  return name === "reduction" || name.startsWith("reduction_") || name.startsWith("hook_");
}

/**
 * Runs the registered hook for `name` (silent no-op when unregistered).
 * Called by each adapter's native dispatch callback. Hook exceptions are
 * logged and swallowed so a throwing hook never aborts the parse (mirrors
 * Python's PyErr_Print behavior).
 */
export function dispatchProcedure(name: string, args: Handle, port: FfiPort): void {
  const fn = registry.get(name);
  if (!fn) return;
  try {
    if (fn.length === 0) {
      (fn as () => void)();
    } else {
      (fn as HookFn)(new ProcedureArguments(args, currentSession, port));
    }
  } catch (err) {
    console.error(`galley procedure ${name} threw:`, err);
  }
}

/**
 * Installs a single procedure hook. `fn` may be
 * `(args: ProcedureArguments)=>void` or `()=>void`.
 * Overwrites any existing entry for `name`.
 */
export function installProcedure(name: string, fn: HookFn | (() => void)): void {
  if (typeof name !== "string" || name.length === 0) throw new TypeError("procedure name must be non-empty string");
  if (typeof fn !== "function") throw new TypeError("procedure must be a function");
  registry.set(name, fn as HookFn);
}

/**
 * Scans `module` for exported procedure hooks (`reduction`, `reduction_*`,
 * `hook_*`) and registers each function. Returns the number installed.
 * Mirrors `bindings/python/_galley.c:2339` `install_procedures`.
 */
export function installProcedures(module: Record<string, unknown>): number {
  if (module === null || typeof module !== "object") throw new TypeError("module must be an object");
  let count = 0;
  for (const [name, value] of Object.entries(module)) {
    if (typeof value !== "function") continue;
    if (!isProcedureName(name)) continue;
    registry.set(name, value as HookFn);
    count++;
  }
  return count;
}

/** Removes all registered hooks; subsequent parses will be no-ops. */
export function clearProcedures(): void {
  registry.clear();
}

/** Returns currently registered procedure names. */
export function listProcedures(): string[] {
  return [...registry.keys()];
}
