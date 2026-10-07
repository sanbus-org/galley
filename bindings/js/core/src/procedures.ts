/**
 * Host-language procedure registry for the JavaScript bindings.
 *
 * Runtime-neutral: the registry, `ProcedureArguments`, and the hook
 * router live here. Every session owns its hooks: a registry copied from
 * the parser's defaults when the session opens, handed to the library as
 * an enabled set. An adapter's native trampoline forwards each enabled
 * hook to the port's `hookDispatch` with the handle its session
 * registered, and the {@link HookRouter} hands it to that session.
 *
 * Hooks receive a `ProcedureArguments` object: per-hook state (current
 * node, position, drop and replace) that is valid only while the hook
 * runs. While a hook runs, the session crosses node reads and tree edits
 * through the running parse's hook door over the galley_hook_* twins, so
 * `currentNode()` plus the ordinary `Node` methods reach the live parse
 * without touching the session door. The nodes carry the core's parse
 * generation: they stay usable for the rest of that parse and, when it
 * publishes its tree, until the session parses again.
 */

import { Status } from "./constants.ts";
import type { Handle, FfiPort, HookTicket } from "./port.ts";
import type { Node } from "./node.ts";
import { GalleyError, SessionClosedError } from "./errors.ts";
import type { Session } from "./session.ts";
import { checkMessageBytes } from "./sources.ts";

/**
 * Per-hook state: the current node and its redirect, the scanner position,
 * drop and replace, and semantic errors. Valid only while its hook runs: the
 * core refuses every call made with the ticket of a hook that has returned
 * (a `GalleyError` with status `Status.ErrorStaleHook`), and this object
 * keeps no expiry state of its own. What must outlive the hook — the tree —
 * is addressed through the session.
 */
export class ProcedureArguments {
  readonly #hook: HookTicket;
  readonly #handle: Handle;
  readonly #session: Session;
  readonly #port: FfiPort;
  /** The session's wrap of an address of the running parse; invalid is null. */
  readonly #wrap: (address: bigint) => Node | null;

  constructor(
    hook: HookTicket,
    handle: Handle,
    session: Session,
    port: FfiPort,
    wrap: (address: bigint) => Node | null,
  ) {
    this.#hook = hook;
    this.#handle = handle;
    this.#session = session;
    this.#port = port;
    this.#wrap = wrap;
  }

  /**
   * The session handle every call crosses with, refused once the session is
   * closed: its native storage is gone, which is a different failure from a
   * hook that has returned.
   */
  #live(): Handle {
    if (this.#session.isClosed) throw new SessionClosedError("session is closed");
    return this.#handle;
  }

  currentNode(): Node | null {
    const read = this.#port.procCurrentNode(this.#live(), this.#hook);
    if (typeof read === "number") throw this.#failure("currentNode", read);
    return this.#wrap(read);
  }

  setCurrentNode(node: Node): void {
    const handle = this.#live();
    const address = this.#session.admit(node);
    const status = this.#port.procSetCurrentNode(handle, this.#hook, node.generation, address);
    if (status < 0) throw this.#session.errorFromStatus(status);
  }

  dropSelf(): void {
    this.#throwOnFailure("dropSelf", this.#port.procDropSelf(this.#live(), this.#hook));
  }

  dropChildren(): void {
    this.#throwOnFailure("dropChildren", this.#port.procDropChildren(this.#live(), this.#hook));
  }

  dropIfEmpty(): void {
    this.#throwOnFailure("dropIfEmpty", this.#port.procDropIfEmpty(this.#live(), this.#hook));
  }

  replaceWithChildren(): void {
    this.#throwOnFailure(
      "replaceWithChildren",
      this.#port.procReplaceWithChildren(this.#live(), this.#hook),
    );
  }

  currentLine(): number {
    const line = this.#port.procContextLine(this.#live(), this.#hook);
    this.#throwOnFailure("currentLine", line);
    return line;
  }

  currentColumn(): number {
    const column = this.#port.procContextColumn(this.#live(), this.#hook);
    this.#throwOnFailure("currentColumn", column);
    return column;
  }

  /**
   * Record a semantic error on the current node and return the running
   * total. Parsing continues; a syntax-clean parse with any semantic
   * error fails with status -12.
   */
  reportSemanticError(message: string | Uint8Array): number {
    const status = this.#port.procReportSemanticError(
      this.#live(),
      this.#hook,
      checkMessageBytes(message, "galley: reportSemanticError"),
    );
    this.#throwOnFailure("reportSemanticError", status);
    return status;
  }

  /**
   * The host failure type for a negative native status: a `GalleyError`
   * carrying the status as its named code. Procedure operations attach no
   * diagnostic, so the snapshot is null.
   */
  #failure(operation: string, status: number): GalleyError {
    return new GalleyError(
      `galley: ${operation} failed: ${this.#port.statusString(status) ?? "unknown galley error"}`,
      status as Status,
      null,
    );
  }

  #throwOnFailure(operation: string, status: number): void {
    if (status >= 0) return;
    throw this.#failure(operation, status);
  }
}

export type HookFn = (args: ProcedureArguments) => void;

/** Hook modules for a session: one module, nested arrays, nullish entries skipped. */
export type ProceduresOption = Record<string, unknown> | null | undefined | ProceduresOption[];

export function isProcedureName(name: string): boolean {
  return name === "reduction" || name.startsWith("reduction_") || name.startsWith("hook_");
}

/**
 * The one wire rule: a hook-named function export. The scan, the
 * default-export cover check, and the zero-wiring guard's "exports a
 * hook" test all ask this, so the install rule cannot drift from them.
 */
function isWireableHook(name: string, value: unknown): value is HookFn {
  return typeof value === "function" && isProcedureName(name);
}

/**
 * One artifact's procedure hooks. Parsers build one from the entry's
 * bundled namespace; hooks never cross artifacts.
 */
export class ProcedureRegistry {
  readonly #hooks = new Map<string, HookFn>();
  /**
   * Installs a single procedure hook. `fn` may be
   * `(args: ProcedureArguments)=>void` or `()=>void`.
   * Overwrites any existing entry for `name`.
   */
  install(name: string, fn: HookFn | (() => void)): void {
    if (typeof name !== "string" || name.length === 0) throw new TypeError("procedure name must be non-empty string");
    if (typeof fn !== "function") throw new TypeError("procedure must be a function");
    this.#hooks.set(name, fn as HookFn);
  }

  /**
   * Installs bundled scan hooks from one module, an array of modules,
   * or nested arrays; nullish entries are skipped. Only names with no
   * existing hook install, so explicit installs win over bundled scans
   * regardless of order. Returns the number installed.
   *
   * `proceduresEnabled` is the build's config flag (`config.zig
   * procedures = true`) supplied by the parser: with it set, a
   * non-empty module holding no hook-named function exports prints
   * one notice per module — the misnaming the installed count cannot
   * report, since a healthy re-scan also installs zero. A module the
   * default-export diagnostic already reported stays at that one line:
   * it names the same mistake and the same fix.
   */
  installBundled(value: unknown, proceduresEnabled = false): number {
    if (value === null || value === undefined) return 0;
    if (Array.isArray(value)) {
      let total = 0;
      for (const entry of value) total += this.installBundled(entry, proceduresEnabled);
      return total;
    }
    const module = value as Record<string, unknown>;
    const wired = this.#scanModule(module, false);
    if (
      proceduresEnabled &&
      Object.keys(module).length > 0 &&
      !exportsHookName(module) &&
      !warnedDefaultExports.has(module)
    ) {
      warnOnZeroHookWiring(module);
    }
    return wired;
  }

  /**
   * Scans `module` for exported procedure hooks (`reduction`,
   * `reduction_*`, `hook_*`) and registers each function, later
   * entries winning per hook name. Returns the number installed.
   */
  installModule(module: Record<string, unknown>): number {
    return this.#scanModule(module, true);
  }

  /**
   * Shared module scan: name filter, near-miss warning, overwrite
   * policy; the default-export diagnostic runs at scan end, once every
   * top-level name is known.
   */
  #scanModule(module: Record<string, unknown>, overwrite: boolean): number {
    if (module === null || typeof module !== "object") throw new TypeError("module must be an object");
    let count = 0;
    for (const [name, value] of Object.entries(module)) {
      if (name === "default") continue;
      if (!isWireableHook(name, value)) {
        if (typeof value === "function") warnOnNearMissHook(name);
        continue;
      }
      if (!overwrite && this.#hooks.has(name)) continue;
      this.#hooks.set(name, value);
      count++;
    }
    if (Object.hasOwn(module, "default")) {
      warnOnIgnoredDefault(module, module["default"]);
    }
    return count;
  }

  /** An independent registry holding the same hooks. */
  copy(): ProcedureRegistry {
    const copied = new ProcedureRegistry();
    for (const [name, fn] of this.#hooks) copied.#hooks.set(name, fn);
    return copied;
  }

  /** Removes all registered hooks; subsequent parses will be no-ops. */
  clear(): void {
    this.#hooks.clear();
  }

  /** Returns currently registered procedure names. */
  names(): string[] {
    return [...this.#hooks.keys()];
  }

  /** The hook for `name`, if registered. Used by the dispatcher. */
  get(name: string): HookFn | undefined {
    return this.#hooks.get(name);
  }
}

let sharedRegistries = new WeakMap<object, ProcedureRegistry>();

/**
 * The one default hook table for a port: every parser handle built on the
 * port shares it, so separately constructed objects can never diverge onto
 * two default tables for one artifact. Sessions copy it when they open.
 */
export function registryFor(port: FfiPort): ProcedureRegistry {
  let registry = sharedRegistries.get(port);
  if (registry === undefined) {
    registry = new ProcedureRegistry();
    sharedRegistries.set(port, registry);
  }
  return registry;
}

/** What the router hands a hook to: the session that owns the handle. */
export interface HookOwner {
  /**
   * Runs hook `index` of the owner's running parse, on the parsing thread.
   * Answers zero, or nonzero when the hook failed: the owner keeps what it
   * threw, and nothing escapes into the core.
   */
  dispatchHook(index: number, hook: HookTicket): number;
}

/**
 * Routes one port's hooks to the sessions that own them. The adapter's
 * native trampoline forwards every enabled hook to `port.hookDispatch`
 * with the handle its session registered here, so concurrent sessions of
 * one library never share hook state. Anchored on the port under a
 * registered symbol — not in module state — so duplicated core installs
 * in one process share one router per port.
 */
export class HookRouter {
  /** Hook names in hook-index order, from the library's own list. */
  readonly names: readonly string[];
  readonly #indexes = new Map<string, number>();
  readonly #owners = new Map<number, HookOwner>();
  #next = 1;

  constructor(port: FfiPort) {
    this.names = port.hookNames();
    this.names.forEach((name, index) => this.#indexes.set(name, index));
    port.hookDispatch = (hookHandle, hookIndex, hook) => {
      return this.#owners.get(hookHandle)?.dispatchHook(hookIndex, hook) ?? 1;
    };
  }

  /** Registers an owner and returns the handle the library hands back with its hooks. */
  register(owner: HookOwner): number {
    const hookHandle = this.#next++;
    this.#owners.set(hookHandle, owner);
    return hookHandle;
  }

  unregister(hookHandle: number): void {
    this.#owners.delete(hookHandle);
  }

  /**
   * The registry's hooks by hook index. A name the grammar has no hook
   * for stays in the registry but never fires.
   */
  resolve(registry: ProcedureRegistry): (HookFn | undefined)[] {
    const byIndex = new Array<HookFn | undefined>(this.names.length).fill(undefined);
    for (const name of registry.names()) {
      const index = this.#indexes.get(name);
      if (index !== undefined) byIndex[index] = registry.get(name);
    }
    return byIndex;
  }
}

const HOOK_ROUTER = Symbol.for("@sanbus/galley/hookRouter");

/**
 * Routers of ports that refuse extension (never ours, but `FfiPort` is
 * public), in a module map instead of an assignment that would throw.
 */
const unextensiblePortRouters = new WeakMap<FfiPort, HookRouter>();

/** The one router of a port, created with the first session opened on it. */
export function routerFor(port: FfiPort): HookRouter {
  if (!Object.isExtensible(port)) {
    let router = unextensiblePortRouters.get(port);
    if (router === undefined) {
      router = new HookRouter(port);
      unextensiblePortRouters.set(port, router);
    }
    return router;
  }
  const holder = port as unknown as Record<symbol, HookRouter | undefined>;
  let router = holder[HOOK_ROUTER];
  if (router === undefined) {
    router = new HookRouter(port);
    holder[HOOK_ROUTER] = router;
  }
  return router;
}

/** Test-only: drop shared tables so suites isolate hook state. */
export function __resetSharedRegistries(): void {
  sharedRegistries = new WeakMap<object, ProcedureRegistry>();
}

/**
 * True for export names that look like mistyped hooks (`reductionPair`,
 * `hookPrint`, `Reduction_X`): a warning, not an install. Anything else
 * (helpers, data) stays silent.
 */
function isNearMissHookName(name: string): boolean {
  const lower = name.toLowerCase();
  return lower.startsWith("reduct") || lower.startsWith("hook");
}

/** Names already reported as mistyped hooks: one report per name per process. */
const warnedNearMissNames = new Set<string>();

/** Warns once per name on a skipped export that looks like a mistyped hook. */
function warnOnNearMissHook(name: string): void {
  if (!isNearMissHookName(name) || warnedNearMissNames.has(name)) return;
  warnedNearMissNames.add(name);
  console.warn(
    `galley: ignoring export "${name}": ` +
      `procedure hooks must be named reduction, reduction_*, or hook_*.`,
  );
}

/** Modules already reported for a hidden default export: one report per module. */
const warnedDefaultExports = new WeakSet<object>();

/**
 * The default spelling never wires: the scan installs top-level named
 * exports only. Warn when the default carries hook content no
 * function-valued top-level export covers (an interop namespace
 * exposing the same hooks under both spellings wires them and stays
 * quiet), or when it is itself a function, which no scan can ever
 * install. Presence of a top-level function of that name decides —
 * not installation — so a re-scan over an already-installed name does
 * not re-trigger. Keyed per module: wasm's double scan shares the
 * namespace and prints once; a second broken module still reports.
 */
function warnOnIgnoredDefault(module: Record<string, unknown>, defaultExport: unknown): void {
  if (defaultExport === null) return;
  const kind = typeof defaultExport;
  if (kind !== "object" && kind !== "function") return;
  let holdsHookContent = false;
  let heldNames = 0;
  for (const [name, value] of Object.entries(defaultExport as object)) {
    if (!isWireableHook(name, value)) continue;
    heldNames++;
    if (Object.hasOwn(module, name) && isWireableHook(name, module[name])) continue;
    holdsHookContent = true;
    break;
  }
  const bareFunction = kind === "function" && heldNames === 0;
  if ((!holdsHookContent && !bareFunction) || warnedDefaultExports.has(module)) return;
  warnedDefaultExports.add(module);
  console.warn(
    `galley: ignoring default export: ` +
      `procedure hooks must be named exports (reduction_*, hook_*).`,
  );
}

/** True when the module has at least one hook-named function export. */
function exportsHookName(module: Record<string, unknown>): boolean {
  for (const [name, value] of Object.entries(module)) {
    if (isWireableHook(name, value)) return true;
  }
  return false;
}

/** Modules already reported for zero hook wiring: one report per module. */
const warnedZeroHookWiring = new WeakSet<object>();

/**
 * The build has procedures enabled (config.zig `procedures = true`)
 * but this module — non-empty, since the build's own empty stub says
 * "no hooks" legitimately — has no hook-named function export at all:
 * the bundled scan wired nothing and no other diagnostic fires. Keyed
 * per module: wasm's double scan shares the namespace and prints once;
 * a second broken language still reports.
 */
function warnOnZeroHookWiring(module: Record<string, unknown>): void {
  if (warnedZeroHookWiring.has(module)) return;
  warnedZeroHookWiring.add(module);
  console.warn(
    `galley: no hooks wired from the procedures module, but this build has procedures enabled ` +
      `(config.zig procedures = true): hooks must be named reduction, reduction_*, or hook_*.`,
  );
}


