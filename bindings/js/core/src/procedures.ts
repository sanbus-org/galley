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
 * runs. Node reads and tree edits go through the parse's `HookDoor`, one
 * per parse and shared by every hook of it, over the galley_hook_*
 * twins, so `currentNode()` plus the ordinary `Node` methods cross into
 * the live parse without touching the session door and stay usable for
 * the rest of that parse.
 */

import { INVALID_NODE, Status } from "./constants.ts";
import type { Handle, FfiPort } from "./port.ts";
import { Node, nodeAddress, type NodeDoor } from "./node.ts";
import { GalleyError, SessionClosedError } from "./errors.ts";
import type { Session } from "./session.ts";
import { checkMessageBytes } from "./sources.ts";

/**
 * The parse-time door over one parse's node storage. One per parse, so
 * every hook of that parse hands out nodes on the same door and two nodes
 * share a door exactly when they belong to the same parse. Reads and edits
 * cross the galley_hook_* twins on the native door, which stays valid for
 * the whole parse; the session's parse generation, stamped here, shows
 * when that parse has ended.
 */
export class HookDoor implements NodeDoor {
  readonly #door: Handle;
  readonly #session: Session;
  readonly #port: FfiPort;
  /** The parse generation this door belongs to, stamped at creation. */
  readonly #generation: number;

  constructor(door: Handle, session: Session, port: FfiPort) {
    this.#door = door;
    this.#session = session;
    this.#port = port;
    this.#generation = session.parseGeneration;
  }

  /**
   * The single gate for this door: a closed session or a door left over
   * from an earlier parse generation throws instead of reading dead
   * storage, and a node argument must be live and belong to this door.
   * Every crossing takes its address from here and nowhere else.
   * @internal
   */
  address(node: Node | bigint | number): bigint {
    if (this.#session.isClosed) {
      throw new SessionClosedError("session is closed");
    }
    if (this.#generation !== this.#session.parseGeneration) {
      throw new SessionClosedError("hook door is invalidated");
    }
    return nodeAddress(node, this);
  }

  /** Wraps an address on this door; invalid becomes null. @internal */
  node(address: bigint): Node | null {
    if (address === INVALID_NODE) return null;
    return new Node(this.#session, address, this);
  }

  childCount(node: Node | bigint | number): number {
    return this.#port.hookNodeChildCount(this.#door, this.address(node));
  }

  firstChild(node: Node | bigint | number): Node | null {
    return this.node(this.#port.hookNodeFirstChild(this.#door, this.address(node)));
  }

  lastChild(node: Node | bigint | number): Node | null {
    return this.node(this.#port.hookNodeLastChild(this.#door, this.address(node)));
  }

  nextSibling(node: Node | bigint | number): Node | null {
    return this.node(this.#port.hookNodeNextSibling(this.#door, this.address(node)));
  }

  priorSibling(node: Node | bigint | number): Node | null {
    return this.node(this.#port.hookNodePriorSibling(this.#door, this.address(node)));
  }

  parent(node: Node | bigint | number): Node | null {
    return this.node(this.#port.hookNodeParent(this.#door, this.address(node)));
  }

  text(node: Node | bigint | number): Uint8Array | null {
    return this.#port.hookNodeText(this.#door, this.address(node));
  }

  symbolNameBytes(node: Node | bigint | number): Uint8Array | null {
    return this.#port.hookNodeSymbolName(this.#door, this.address(node));
  }

  span(node: Node | bigint | number): [bigint, bigint] | null {
    return this.#port.hookNodeSpan(this.#door, this.address(node));
  }

  lineColumn(node: Node | bigint | number): [number, number] | null {
    return this.#port.hookNodeLineColumn(this.#door, this.address(node));
  }

  cleanChildren(node: Node | bigint | number): Node | null {
    const { status, head } = this.#port.hookTreeCleanChildren(this.#door, this.address(node));
    this.#throwOnFailure("cleanChildren", status);
    return this.node(head);
  }

  appendChildren(parent: Node | bigint | number, chain: Node | bigint | number): void {
    this.#throwOnFailure(
      "appendChildren",
      this.#port.hookTreeAppendChildren(this.#door, this.address(parent), this.address(chain)),
    );
  }

  /**
   * Throws the host failure type for a negative native status: a
   * `GalleyError` carrying the status as its named code. Tree operations
   * attach no diagnostic, so the snapshot is null.
   */
  #throwOnFailure(operation: string, status: number): void {
    if (status >= 0) return;
    throw new GalleyError(
      `galley: ${operation} failed: ${this.#port.statusString(status) ?? "unknown galley error"}`,
      status as Status,
      null,
    );
  }
}

/**
 * Per-hook state: the current node and its redirect, the scanner position,
 * drop and replace, and semantic errors. Valid only while its hook runs;
 * the dispatcher expires it when the hook returns, so a reference kept
 * past that throws instead of reading a frame that is gone. What must
 * outlive the hook — the tree — lives on the parse's `HookDoor`.
 */
export class ProcedureArguments {
  readonly #args: Handle;
  readonly #door: HookDoor;
  readonly #port: FfiPort;
  #expired = false;

  constructor(args: Handle, door: HookDoor, port: FfiPort) {
    this.#args = args;
    this.#door = door;
    this.#port = port;
  }

  /** Dispatcher hook: the native arguments no longer exist past this call. @internal */
  expire(): void {
    this.#expired = true;
  }

  /**
   * The single gate for per-hook state: every accessor takes the native
   * arguments from here and nowhere else.
   */
  #live(): Handle {
    if (this.#expired) throw new SessionClosedError("procedure arguments are invalidated");
    return this.#args;
  }

  currentNode(): Node | null {
    return this.#door.node(this.#port.procCurrentNode(this.#live()));
  }

  setCurrentNode(node: Node | bigint | number): void {
    const args = this.#live();
    this.#port.procSetCurrentNode(args, this.#door.address(node));
  }

  dropSelf(): void {
    this.#throwOnFailure("dropSelf", this.#port.procDropSelf(this.#live()));
  }

  dropChildren(): void {
    this.#throwOnFailure("dropChildren", this.#port.procDropChildren(this.#live()));
  }

  dropIfEmpty(): void {
    this.#throwOnFailure("dropIfEmpty", this.#port.procDropIfEmpty(this.#live()));
  }

  replaceWithChildren(): void {
    this.#throwOnFailure("replaceWithChildren", this.#port.procReplaceWithChildren(this.#live()));
  }

  currentLine(): number {
    return this.#port.procContextLine(this.#live());
  }

  currentColumn(): number {
    return this.#port.procContextColumn(this.#live());
  }

  /**
   * Record a semantic error on the current node and return the running
   * total. Parsing continues; a syntax-clean parse with any semantic
   * error fails with status -12.
   */
  reportSemanticError(message: string | Uint8Array): number {
    const status = this.#port.procReportSemanticError(
      this.#live(),
      checkMessageBytes(message, "galley: reportSemanticError"),
    );
    this.#throwOnFailure("reportSemanticError", status);
    return status;
  }

  /**
   * Throws the host failure type for a negative native status: a
   * `GalleyError` carrying the status as its named code. Procedure
   * operations attach no diagnostic, so the snapshot is null.
   */
  #throwOnFailure(operation: string, status: number): void {
    if (status >= 0) return;
    throw new GalleyError(
      `galley: ${operation} failed: ${this.#port.statusString(status) ?? "unknown galley error"}`,
      status as Status,
      null,
    );
  }
}

export type HookFn = (args: ProcedureArguments) => void;

/** Hook modules for a session: one module, nested arrays, nullish entries skipped. */
export type ProceduresOption = Record<string, unknown> | null | undefined | ProceduresOption[];

export function isProcedureName(name: string): boolean {
  return name === "reduction" || name.startsWith("reduction_") || name.startsWith("hook_");
}

/**
 * One artifact's procedure hooks. Parsers build one from the
 * directory scan; hooks never cross artifacts.
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
   */
  installBundled(value: unknown): number {
    if (value === null || value === undefined) return 0;
    if (Array.isArray(value)) {
      let total = 0;
      for (const entry of value) total += this.installBundled(entry);
      return total;
    }
    return this.#scanModule(value as Record<string, unknown>, false);
  }

  /**
   * Scans `module` for exported procedure hooks (`reduction`,
   * `reduction_*`, `hook_*`) and registers each function, later
   * entries winning per hook name. Returns the number installed.
   */
  installModule(module: Record<string, unknown>): number {
    return this.#scanModule(module, true);
  }

  /** Shared module scan: name filter, near-miss warning, overwrite policy. */
  #scanModule(module: Record<string, unknown>, overwrite: boolean): number {
    if (module === null || typeof module !== "object") throw new TypeError("module must be an object");
    let count = 0;
    for (const [name, value] of Object.entries(module)) {
      if (typeof value !== "function") continue;
      if (!isProcedureName(name)) {
        warnOnNearMissHook(name);
        continue;
      }
      if (!overwrite && this.#hooks.has(name)) continue;
      this.#hooks.set(name, value as HookFn);
      count++;
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
  /** Runs hook `index` of the owner's running parse, on the parsing thread. */
  dispatchHook(index: number, args: Handle): void;
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
    port.hookDispatch = (hookHandle, hookIndex, args) => {
      this.#owners.get(hookHandle)?.dispatchHook(hookIndex, args);
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

/** Warns on a skipped export that looks like a mistyped hook name. */
function warnOnNearMissHook(name: string): void {
  if (!isNearMissHookName(name)) return;
  console.warn(
    `galley: ignoring export "${name}": ` +
      `procedure hooks must be named reduction, reduction_*, or hook_*.`,
  );
}

/**
 * Synchronously loads a `procedures` module from a language directory:
 * tries `procedures`, `procedures.ts` in order and returns the first
 * that loads as an object. Bare `procedures` covers `.js` under
 * `require` resolution (mirrored by the build gate's explicit
 * `procedures.ts`/`procedures.js` existence probe, which cannot rely
 * on resolution). Only named exports
 * (`reduction`, `reduction_*`, `hook_*`) install as hooks — a `default`
 * export is never read, and a loud warning names the file when it looks
 * like hooks were left there. Returns null when nothing loadable is
 * there. `requireModule` and `joinPath` are injected so this stays
 * runtime-neutral; runtimes without a synchronous loader (browsers,
 * Deno) pass no loader and register hooks explicitly through the
 * session instead.
 */
export function loadProceduresModule(
  requireModule: ((specifier: string) => unknown) | undefined,
  joinPath: (...parts: string[]) => string,
  directory: string,
): Record<string, unknown> | null {
  if (!requireModule) return null;
  // Bare `procedures` covers `.js` under `require` resolution; the
  // explicit `.ts` spelling is the only one that reaches TypeScript
  // hook files. (ESM `import()` would need every spelling explicit —
  // revisit if any leg leaves `require`.)
  for (const file of ["procedures", "procedures.ts"]) {
    const specifier = joinPath(directory, file);
    let loaded: unknown;
    try {
      loaded = requireModule(specifier);
    } catch (error) {
      // A missing file means "try the next name". Anything else — a
      // throw inside the module, an unloadable extension — is the
      // user's bug, not a miss: rethrow instead of silently running
      // hookless. A missing nested dependency names its own specifier,
      // so it rethrows too.
      if (isMissingSpecifier(error, specifier)) continue;
      throw error;
    }
    if (loaded === null || typeof loaded !== "object") continue;
    const module = loaded as Record<string, unknown>;
    warnOnIgnoredDefault(specifier, module.default);
    return module;
  }
  return null;
}

/** True when `error` reports `specifier` itself as not found. */
function isMissingSpecifier(error: unknown, specifier: string): boolean {
  if (typeof error !== "object" || error === null) return false;
  const code = (error as { code?: unknown }).code;
  if (code !== "MODULE_NOT_FOUND" && code !== "ERR_MODULE_NOT_FOUND") return false;
  const message = (error as { message?: unknown }).message;
  return typeof message === "string" && message.includes(specifier);
}

/** Warns when a `default` export holds hooks that will never run. */
function warnOnIgnoredDefault(specifier: string, defaultExport: unknown): void {
  if (defaultExport === null || typeof defaultExport !== "object") return;
  for (const [name, value] of Object.entries(defaultExport)) {
    if (typeof value !== "function" || !isProcedureName(name)) continue;
    console.warn(
      `galley: ignoring default export in ${specifier}: ` +
        `procedure hooks must be named exports (reduction_*, hook_*).`,
    );
    return;
  }
}
