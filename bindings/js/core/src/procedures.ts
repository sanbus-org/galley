/**
 * Host-language procedure registry for the JavaScript bindings.
 *
 * Runtime-neutral: the registry, `ProcedureArguments`, and the dispatcher
 * live here. Each adapter installs a forwarder into its shared library
 * through its own native callback (`galley_install_*_dispatch`); the
 * forwarder decodes the hook name and calls the port's `activeDispatch`
 * slot, which the parsing session set around its parse.
 *
 * Registries live on the language handle: every `Language` owns one
 * table shared by all of its sessions, and publishes per-parse dispatch
 * through the session's gate brackets. There is no per-session table.
 *
 * Hooks receive a `ProcedureArguments` object. Tree queries use
 * `currentNode()` plus the ordinary `Node` methods (which call the port's
 * node accessors on the parsing session).
 */

import { INVALID_NODE } from "./constants.ts";
import type { Handle, FfiPort } from "./port.ts";
import { Node } from "./node.ts";
import type { Session } from "./session.ts";
import { checkMessageBytes } from "./sources.ts";

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
  reportSemanticError(message: string | Uint8Array): number {
    const status = this.#port.procReportSemanticError(
      this.#args,
      checkMessageBytes(message, "galley: reportSemanticError"),
    );
    if (status < 0) throw new Error("galley_procedure_report_semantic_error failed");
    return status;
  }
}

export type HookFn = (args: ProcedureArguments) => void;

/** Hook modules for a session: one module, nested arrays, nullish entries skipped. */
export type ProceduresOption = Record<string, unknown> | null | undefined | ProceduresOption[];

export function isProcedureName(name: string): boolean {
  return name === "reduction" || name.startsWith("reduction_") || name.startsWith("hook_");
}

/**
 * One artifact's procedure hooks. Languages build one from the
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
   * Installs hooks from one module, an array of modules, or nested
   * arrays; nullish entries are skipped. Later entries win per hook
   * name, so factories pass scanned defaults ahead of explicit user
   * modules.
   */
  installAll(value: unknown): void {
    if (value === null || value === undefined) return;
    if (Array.isArray(value)) {
      for (const entry of value) this.installAll(entry);
      return;
    }
    this.installModule(value as Record<string, unknown>);
  }

  /**
   * Scans `module` for exported procedure hooks (`reduction`,
   * `reduction_*`, `hook_*`) and registers each function. Returns the
   * number installed. Mirrors `bindings/python/_galley.c:2339`
   * `install_procedures`.
   */
  installModule(module: Record<string, unknown>): number {
    if (module === null || typeof module !== "object") throw new TypeError("module must be an object");
    let count = 0;
    for (const [name, value] of Object.entries(module)) {
      if (typeof value !== "function") continue;
      if (!isProcedureName(name)) {
        warnOnNearMissHook(name);
        continue;
      }
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
