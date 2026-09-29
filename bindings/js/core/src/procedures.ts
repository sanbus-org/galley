/**
 * Host-language procedure registry for the JavaScript bindings.
 *
 * Runtime-neutral: the registry, `ProcedureArguments`, and the dispatcher
 * live here. Each adapter installs a forwarder into its shared library
 * through its own native callback (`galley_install_*_dispatch`); the
 * forwarder decodes the hook name and calls the port's `activeDispatch`
 * slot, which the parsing session set around its parse.
 *
 * Registries live on the parser: every `Parser` owns one
 * table shared by all of its sessions, and publishes per-parse dispatch
 * through the session's gate brackets. There is no per-session table.
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

  /** Copies the table for one parse's dispatch snapshot. */
  snapshot(): Map<string, HookFn> {
    return new Map(this.#hooks);
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
 * The one hook table for a port: every handle and session built on the
 * port shares it, so separately constructed objects can never diverge
 * onto two tables over one native gate set.
 */
export function registryFor(port: FfiPort): ProcedureRegistry {
  let registry = sharedRegistries.get(port);
  if (registry === undefined) {
    registry = new ProcedureRegistry();
    sharedRegistries.set(port, registry);
  }
  return registry;
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
