/**
 * Loaded language handle: the artifact-level namespace sessions open from.
 *
 * Owns exactly one hook table shared by every session of the artifact,
 * answers every grammar query, and opens sessions. Acquiring the
 * artifact and opening sessions on it are separate steps, so callers
 * always have a moment to install hooks between them.
 */

import type { FfiPort } from "./port.ts";
import { Session } from "./session.ts";
import type { SessionOptions } from "./session.ts";
import { registryFor } from "./procedures.ts";
import type { ProcedureRegistry } from "./procedures.ts";
import type { HookFn } from "./procedures.ts";

export class Language {
  readonly #port: FfiPort;
  readonly #registry: ProcedureRegistry;

  /**
   * Takes a bound port: factories resolve the backend first, so a
   * constructed language is always usable. There is no unready state.
   * `scannedProcedures` carries the factory's language-directory scan
   * (or null where the runtime has none); it installs ahead of any
   * explicit install, so later explicit installs win per hook name.
   */
  constructor(port: FfiPort, scannedProcedures: unknown = null) {
    if (!port) throw new TypeError("galley: Language needs a bound port");
    this.#port = port;
    this.#registry = registryFor(port);
    this.#registry.installAll(scannedProcedures);
  }

  /** The bound port. Sessions opened here share it. */
  protected get port(): FfiPort {
    return this.#port;
  }

  // -- parser metadata (mirror galley.h; bound to this artifact) --

  version(): string {
    return this.#port.version();
  }

  parserType(): number {
    return this.#port.parserType();
  }

  errorRecoveryMode(): number {
    return this.#port.errorRecoveryMode();
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

  // -- procedures (this artifact's registry; shared by its sessions) --

  /**
   * Installs a single procedure hook into this artifact.
   * Overwrites any existing entry for `name`.
   */
  installProcedure(name: string, fn: HookFn | (() => void)): void {
    this.#registry.install(name, fn);
  }

  /**
   * Scans `module` for exported procedure hooks (`reduction`,
   * `reduction_*`, `hook_*`) and registers each function into this
   * artifact. Returns the number installed.
   */
  installProcedures(module: Record<string, unknown>): number {
    return this.#registry.installModule(module);
  }

  /** Removes all hooks from this artifact; subsequent parses are no-ops. */
  clearProcedures(): void {
    this.#registry.clear();
  }

  /** Returns a copy of this artifact's registered hooks (name -> callable). */
  listProcedures(): Record<string, HookFn> {
    const table: Record<string, HookFn> = {};
    for (const name of this.#registry.names()) {
      const hook = this.#registry.get(name);
      if (hook !== undefined) table[name] = hook;
    }
    return table;
  }

  /** The hook for `name`, if this artifact registered one. */
  procedureHook(name: string): HookFn | undefined {
    return this.#registry.get(name);
  }

  /**
   * Opens a session on this artifact. Takes only parser tunables;
   * hooks come from this handle's shared table.
   */
  openSession(options: SessionOptions = {}): Session {
    return new Session(this.#port, options);
  }
}
