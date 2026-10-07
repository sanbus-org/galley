/**
 * Loaded parser: the artifact-level namespace sessions open from.
 *
 * Owns the artifact's default hook table, answers every grammar query,
 * and opens sessions. Every session starts with a copy of the defaults
 * and owns that copy from then on, so an install here reaches sessions
 * opened later, never sessions already open. Acquiring the artifact and
 * opening sessions on it are separate steps, so callers always have a
 * moment to install hooks between them.
 */

import type { FfiPort } from "./port.ts";
import type { ParserType, RecoveryMode } from "./constants.ts";
import { Session } from "./session.ts";
import type { SessionOptions } from "./session.ts";
import { ProcedureRegistry } from "./procedures.ts";
import type { HookFn } from "./procedures.ts";

export class Parser {
  readonly #port: FfiPort;
  readonly #registry: ProcedureRegistry;

  /**
   * Takes a bound port: factories resolve the backend first, so a
   * constructed parser is always usable. There is no unready state.
   * Each parser owns its default hook table — two loads of one
   * artifact never share one — and `bundledProcedures` carries the
   * entry's statically imported hook namespace (or null for bare
   * loads); it fills only hook names never installed, so explicit
   * installs win regardless of order. The table lives here and nowhere
   * else: a subclass that constructs sessions itself receives it
   * through `openSessionWith`.
   */
  constructor(port: FfiPort, bundledProcedures: unknown = null) {
    if (!port) throw new TypeError("galley: Parser needs a bound port");
    this.#port = port;
    this.#registry = new ProcedureRegistry();
    this.installBundledProcedures(bundledProcedures);
  }

  /**
   * Wires the bundled namespace in bulk for names not yet installed.
   * Explicit installs win per hook name regardless of order.
   */
  installBundledProcedures(value: unknown): void {
    this.#registry.installBundled(value, this.hasProcedures());
  }

  /** The bound port. Sessions opened here share it. */
  protected get port(): FfiPort {
    return this.#port;
  }

  // -- parser metadata (mirror galley.h; bound to this artifact) --

  version(): string {
    return this.#port.version();
  }

  parserType(): ParserType {
    return this.#port.parserType() as ParserType;
  }

  errorRecoveryMode(): RecoveryMode {
    return this.#port.errorRecoveryMode() as RecoveryMode;
  }

  hasAst(): boolean {
    return this.#port.hasAst();
  }

  hasProcedures(): boolean {
    return this.#port.hasProcedures();
  }

  allowsNoAstTreeProcedures(): boolean {
    return this.#port.allowsNoAstTreeProcedures();
  }

  sourceRetentionEnabled(): boolean {
    return this.#port.sourceRetentionEnabled();
  }

  hasPositionTracking(): boolean {
    return this.#port.hasPositionTracking();
  }

  hasInputStreaming(): boolean {
    return this.#port.hasInputStreaming();
  }

  usesVerbatim(): boolean {
    return this.#port.usesVerbatim();
  }

  stackOverflowRecoveryAvailable(): boolean {
    return this.#port.stackOverflowRecoveryAvailable();
  }

  symbolCount(): number {
    return this.#port.symbolCount();
  }

  variableCount(): number {
    return this.#port.variableCount();
  }

  statusString(status: number): string | null {
    return this.#port.statusString(status);
  }

  // -- procedures (this artifact's defaults; sessions copy them at open) --

  /**
   * Installs a single default procedure hook into this artifact.
   * Overwrites any existing entry for `name`.
   */
  installProcedure(name: string, fn: HookFn | (() => void)): void {
    this.#registry.install(name, fn);
  }

  /**
   * Scans `module` for exported procedure hooks (`reduction`,
   * `reduction_*`, `hook_*`) and registers each function as a default of
   * this artifact. Returns the number installed.
   */
  installProcedures(module: Record<string, unknown>): number {
    return this.#registry.installModule(module);
  }

  /** Removes all default hooks; sessions already open keep theirs. */
  clearProcedures(): void {
    this.#registry.clear();
  }

  /** Returns a copy of this artifact's default hooks (name -> callable). */
  listProcedures(): Record<string, HookFn> {
    const table: Record<string, HookFn> = {};
    for (const name of this.#registry.names()) {
      const hook = this.#registry.get(name);
      if (hook !== undefined) table[name] = hook;
    }
    return table;
  }

  /** The default hook for `name`, if this artifact registered one. */
  procedureHook(name: string): HookFn | undefined {
    return this.#registry.get(name);
  }

  /**
   * Opens a session on this artifact. Takes only parser tunables;
   * the session's hooks start as a copy of this parser's defaults.
   */
  openSession(options: SessionOptions = {}): Session {
    return this.openSessionWith((defaults) => new Session(this.#port, options, defaults));
  }

  /**
   * Hands this parser's default table to `create`, which builds the
   * session that will copy it. The one way a subclass constructs its own
   * session type, so no subclass keeps a reference to the table.
   */
  protected openSessionWith<S extends Session>(create: (defaults: ProcedureRegistry) => S): S {
    return create(this.#registry);
  }
}
