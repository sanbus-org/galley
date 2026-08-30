/**
 * Parsing session bound to this library's parser.
 * Mirrors Python/Rust/Go sessions over `bindings/c/galley.h`.
 */

import { INVALID_NODE } from "./constants.js";
import type { Diagnostic } from "./diagnostic.js";
import { GalleyError } from "./errors.js";
import { copyBytes, copyStringBytes, loadLibrary, toBigInt, type GalleyFFI } from "./ffi.js";
import { Node } from "./node.js";
import { ensureDispatchFor } from "./procedures.js";

export interface SessionOptions {
  maxErrors?: number; // default 10
  recoveryWindow?: number; // default 500
  stackOverflowRecovery?: boolean; // default false
  syntaxErrorStackDepth?: number; // default 0
  verbosity?: number; // default 0
  astPreallocationRatio?: number; // default -1.0 (selects library default)
  astPreallocationCap?: number | bigint; // default 0
  messageOverrides?: Record<string, string>; // name -> message
  libraryPath?: string; // override shared-library location
}

function defaultOptions(): Required<Omit<SessionOptions, "messageOverrides" | "libraryPath">> & {
  messageOverrides: Record<string, string>;
} {
  return {
    maxErrors: 10,
    recoveryWindow: 500,
    stackOverflowRecovery: false,
    syntaxErrorStackDepth: 0,
    verbosity: 0,
    astPreallocationRatio: -1.0,
    astPreallocationCap: 0,
    messageOverrides: {},
  };
}

function toNodeAddress(node: Node | bigint | number): bigint {
  if (typeof node === "bigint") return node;
  if (typeof node === "number") return BigInt(node);
  return (node as Node).address;
}

function isInvalid(addr: bigint | number): boolean {
  const v = typeof addr === "bigint" ? addr : BigInt(addr);
  return v === INVALID_NODE;
}

function optNode(session: Session, addr: bigint | number): Node | null {
  if (isInvalid(addr)) return null;
  return new Node(session, toBigInt(addr));
}

export class Session {
  #handle: bigint | null = null;
  #ffi: GalleyFFI;
  #closed = false;

  constructor(options: SessionOptions = {}) {
    const merged = { ...defaultOptions(), ...options };
    const overrides = options.messageOverrides ?? merged.messageOverrides;
    this.#ffi = loadLibrary(options.libraryPath);
    // Ensure host-procedure dispatch is installed for this library even if
    // the first Session is created before any installProcedure call (mirrors
    // Python's immer-shim + dlsym at import time).
    try {
      ensureDispatchFor(this.#ffi);
    } catch {
      // installer missing (C build) — ignore.
    }

    const hasNonDefault =
      options.maxErrors !== undefined ||
      options.recoveryWindow !== undefined ||
      options.stackOverflowRecovery !== undefined ||
      options.syntaxErrorStackDepth !== undefined ||
      options.verbosity !== undefined ||
      options.astPreallocationRatio !== undefined ||
      options.astPreallocationCap !== undefined;

    let handle: bigint;
    if (hasNonDefault) {
      const cOptions: Record<string, unknown> = {
        max_errors: merged.maxErrors,
        recovery_window: merged.recoveryWindow,
        stack_overflow_recovery: merged.stackOverflowRecovery ? 1 : 0,
        syntax_error_stack_depth: merged.syntaxErrorStackDepth,
        verbosity: merged.verbosity,
        ast_preallocation_ratio: merged.astPreallocationRatio,
        ast_preallocation_cap:
          typeof merged.astPreallocationCap === "bigint"
            ? merged.astPreallocationCap
            : BigInt(merged.astPreallocationCap),
      };
      // @ts-ignore koffi expects object for struct pointer
      handle = this.#ffi.galley_session_create_ex(cOptions as never) as bigint;
    } else {
      handle = this.#ffi.galley_session_create() as bigint;
    }

    if (handle === 0n || handle === null) {
      throw new GalleyError("out of memory", -7, null);
    }
    this.#handle = handle;

    for (const [name, message] of Object.entries(overrides)) {
      const st = this.#ffi.galley_session_set_message_override(
        this.#handle,
        name,
        Buffer.byteLength(name, "utf-8"),
        message,
        Buffer.byteLength(message, "utf-8"),
      );
      if ((typeof st === "bigint" ? st < 0n : (st as number) < 0)) {
        const err = this.#errorFromStatus(st, "failed to register message override");
        this.close();
        throw err;
      }
    }
  }

  get isClosed(): boolean {
    return this.#closed || this.#handle === null;
  }

  #requireHandle(): bigint {
    if (this.#closed || this.#handle === null) throw new Error("session is closed");
    return this.#handle;
  }

  #statusMessage(status: bigint | number): string {
    const s = this.#ffi.galley_status_string(status);
    return s ?? "unknown galley error";
  }

  #errorFromStatus(status: bigint | number, fallback?: string): GalleyError {
    const code = typeof status === "bigint" ? Number(status) : (status as number);
    const message = fallback ?? this.#statusMessage(status);
    let diag: Diagnostic | null = null;
    try {
      if (this.#handle !== null && this.#ffi.galley_has_diagnostic(this.#handle)) {
        diag = this.#buildDiagnosticSingular();
      }
    } catch {
      // ignore
    }
    return new GalleyError(message, code, diag);
  }

  #checkStatus(status: bigint | number, fallback?: string): void {
    const n = typeof status === "bigint" ? status : BigInt(status);
    if (n < 0n) throw this.#errorFromStatus(status, fallback);
  }

  // -- lifecycle -------------------------------------------------------

  close(): void {
    if (this.#handle !== null) {
      this.#ffi.galley_session_destroy(this.#handle);
      this.#handle = null;
    }
    this.#closed = true;
  }

  /** For `using session = new Session()` (Explicit Resource Management). */
  [Symbol.dispose](): void {
    this.close();
  }

  // -- parsing ---------------------------------------------------------

  parse(input: string | Uint8Array | Buffer): number {
    const handle = this.#requireHandle();
    let status: bigint | number;
    if (typeof input === "string") {
      const buf = Buffer.from(input, "utf-8");
      status = this.#ffi.galley_parse(handle, buf, buf.length);
    } else {
      const buf = Buffer.isBuffer(input) ? input : Buffer.from(input);
      status = this.#ffi.galley_parse(handle, buf, buf.length);
    }
    if (typeof status === "bigint" ? status < 0n : (status as number) < 0) {
      throw this.#errorFromStatus(status);
    }
    return typeof status === "bigint" ? Number(status) : (status as number);
  }

  parseSentinel(input: string): number {
    const handle = this.#requireHandle();
    const status = this.#ffi.galley_parse_sentinel(handle, input);
    if (typeof status === "bigint" ? status < 0n : (status as number) < 0) {
      throw this.#errorFromStatus(status);
    }
    return typeof status === "bigint" ? Number(status) : (status as number);
  }

  parseFile(filePath: string): number {
    const handle = this.#requireHandle();
    const status = this.#ffi.galley_parse_file(handle, filePath);
    if (typeof status === "bigint" ? status < 0n : (status as number) < 0) {
      throw this.#errorFromStatus(status);
    }
    return typeof status === "bigint" ? Number(status) : (status as number);
  }

  // -- arena -----------------------------------------------------------

  nodeCount(): number {
    const h = this.#requireHandle();
    const n = this.#ffi.galley_node_count(h);
    return typeof n === "bigint" ? Number(n) : (n as number);
  }

  reserveNodes(capacity: number | bigint): void {
    const h = this.#requireHandle();
    const st = this.#ffi.galley_reserve_nodes(h, capacity);
    this.#checkStatus(st);
  }

  nodeCapacity(): number {
    const h = this.#requireHandle();
    const n = this.#ffi.galley_node_capacity(h);
    return typeof n === "bigint" ? Number(n) : (n as number);
  }

  // -- navigation ------------------------------------------------------

  rootNode(): Node | null {
    const h = this.#requireHandle();
    const addr = this.#ffi.galley_root_node(h);
    return optNode(this, addr as bigint);
  }

  nodeValid(node: Node | bigint | number): boolean {
    const h = this.#requireHandle();
    return this.#ffi.galley_node_is_valid(h, toNodeAddress(node)) !== 0;
  }

  childCount(node: Node | bigint | number): number {
    const h = this.#requireHandle();
    return this.#ffi.galley_node_child_count(h, toNodeAddress(node));
  }

  children(node: Node | bigint | number): Node[] {
    const h = this.#requireHandle();
    const addr = toNodeAddress(node);
    const count = this.childCount(addr);
    const out: Node[] = [];
    let child = this.#ffi.galley_node_first_child(h, addr);
    for (let i = 0; i < count; i++) {
      if (isInvalid(child as bigint)) throw new Error("child count changed during iteration");
      out.push(new Node(this, toBigInt(child as bigint)));
      child = this.#ffi.galley_node_next_sibling(h, child as bigint);
    }
    return out;
  }

  firstChild(node: Node | bigint | number): Node | null {
    const h = this.#requireHandle();
    return optNode(this, this.#ffi.galley_node_first_child(h, toNodeAddress(node)) as bigint);
  }

  lastChild(node: Node | bigint | number): Node | null {
    const h = this.#requireHandle();
    return optNode(this, this.#ffi.galley_node_last_child(h, toNodeAddress(node)) as bigint);
  }

  nextSibling(node: Node | bigint | number): Node | null {
    const h = this.#requireHandle();
    return optNode(this, this.#ffi.galley_node_next_sibling(h, toNodeAddress(node)) as bigint);
  }

  priorSibling(node: Node | bigint | number): Node | null {
    const h = this.#requireHandle();
    return optNode(this, this.#ffi.galley_node_prior_sibling(h, toNodeAddress(node)) as bigint);
  }

  parent(node: Node | bigint | number): Node | null {
    const h = this.#requireHandle();
    return optNode(this, this.#ffi.galley_node_parent(h, toNodeAddress(node)) as bigint);
  }

  symbolNameBytes(node: Node | bigint | number): Uint8Array | null {
    const h = this.#requireHandle();
    const outData: unknown[] = [null];
    const outLen: unknown[] = [0];
    const st = this.#ffi.galley_node_symbol_name(h, toNodeAddress(node), outData, outLen);
    if ((typeof st === "bigint" ? st < 0n : (st as number) < 0)) return null;
    const ptr = outData[0] as bigint | null;
    const len = outLen[0] as bigint | number;
    if (ptr === null || ptr === 0n) return new Uint8Array(0);
    return copyBytes(ptr as bigint, len);
  }

  symbolName(node: Node | bigint | number): string | null {
    const bytes = this.symbolNameBytes(node);
    if (bytes === null) return null;
    return Buffer.from(bytes).toString("utf-8");
  }

  text(node: Node | bigint | number): Uint8Array | null {
    const h = this.#requireHandle();
    const outData: unknown[] = [null];
    const outLen: unknown[] = [0];
    const st = this.#ffi.galley_node_text(h, toNodeAddress(node), outData, outLen);
    if ((typeof st === "bigint" ? st < 0n : (st as number) < 0)) return null;
    const ptr = outData[0] as bigint | null;
    const len = outLen[0] as bigint | number;
    if (ptr === null || ptr === 0n) return new Uint8Array(0);
    return copyBytes(ptr as bigint, len);
  }

  span(node: Node | bigint | number): [bigint, bigint] | null {
    const h = this.#requireHandle();
    const outStart: unknown[] = [0n];
    const outLen: unknown[] = [0n];
    const st = this.#ffi.galley_node_span(h, toNodeAddress(node), outStart, outLen);
    if ((typeof st === "bigint" ? st < 0n : (st as number) < 0)) return null;
    return [toBigInt(outStart[0] as bigint), toBigInt(outLen[0] as bigint)];
  }

  lineColumn(node: Node | bigint | number): [number, number] | null {
    const h = this.#requireHandle();
    const outLine: unknown[] = [0];
    const outCol: unknown[] = [0];
    const st = this.#ffi.galley_node_line_column(h, toNodeAddress(node), outLine, outCol);
    if ((typeof st === "bigint" ? st < 0n : (st as number) < 0)) return null;
    return [outLine[0] as number, outCol[0] as number];
  }

  variableIndex(node: Node | bigint | number): number | null {
    const h = this.#requireHandle();
    const idx = this.#ffi.galley_node_variable_index(h, toNodeAddress(node));
    const n = typeof idx === "bigint" ? idx : BigInt(idx);
    if (n === -1n) return null;
    if (n < 0n) throw this.#errorFromStatus(idx);
    return Number(n);
  }

  lastPosition(): [number, number] | null {
    const h = this.#requireHandle();
    const outLine: unknown[] = [0];
    const outCol: unknown[] = [0];
    const st = this.#ffi.galley_last_position(h, outLine, outCol);
    if ((typeof st === "bigint" ? st < 0n : (st as number) < 0)) return null;
    return [outLine[0] as number, outCol[0] as number];
  }

  hasDiagnostic(): boolean {
    const h = this.#requireHandle();
    return this.#ffi.galley_has_diagnostic(h) !== 0;
  }

  setMessageOverride(name: string, message: string): void {
    const h = this.#requireHandle();
    const st = this.#ffi.galley_session_set_message_override(
      h,
      name,
      Buffer.byteLength(name, "utf-8"),
      message,
      Buffer.byteLength(message, "utf-8"),
    );
    this.#checkStatus(st);
  }

  // -- helpers for diagnostic byte copying -----------------------------

  #tryCopyBytes(
    fn: (outData: unknown[], outLen: unknown[]) => bigint | number,
  ): Uint8Array | null {
    const outData: unknown[] = [null];
    const outLen: unknown[] = [0];
    const st = fn(outData, outLen);
    if ((typeof st === "bigint" ? st < 0n : (st as number) < 0)) return null;
    const ptr = outData[0] as bigint | null;
    if (ptr === null || ptr === 0n) return null;
    return copyBytes(ptr as bigint, outLen[0] as bigint);
  }

  #tryCopyString(
    fn: (outData: unknown[], outLen: unknown[]) => bigint | number,
  ): string | null {
    const bytes = this.#tryCopyBytes(fn);
    if (bytes === null) return null;
    return Buffer.from(bytes).toString("utf-8");
  }

  // -- diagnostics -----------------------------------------------------

  #buildDiagnosticSingular(): Diagnostic {
    const h = this.#requireHandle();
    const kind = Number(toBigInt(this.#ffi.galley_diagnostic_kind(h) as bigint));
    const outLine: unknown[] = [0];
    const outCol: unknown[] = [0];
    this.#ffi.galley_diagnostic_position(h, outLine, outCol);
    const line = outLine[0] as number;
    const col = outCol[0] as number;

    const outMsg: unknown[] = [null];
    const outMsgAnsi: unknown[] = [null];
    let message = "";
    let messageAnsi = "";
    if ((this.#ffi.galley_diagnostic_message(h, outMsg) as number) === 0) message = outMsg[0] as string;
    if ((this.#ffi.galley_diagnostic_message_ansi(h, outMsgAnsi) as number) === 0)
      messageAnsi = outMsgAnsi[0] as string;

    const unexpected = this.#tryCopyBytes((od, ol) =>
      this.#ffi.galley_diagnostic_unexpected_token(h, od, ol),
    );

    const expectedTokens: Uint8Array[] = [];
    const expCount = Number(toBigInt(this.#ffi.galley_diagnostic_expected_count(h) as bigint));
    if (expCount > 0) {
      for (let i = 0; i < expCount; i++) {
        const b = this.#tryCopyBytes((od, ol) => this.#ffi.galley_diagnostic_expected_at(h, i, od, ol));
        if (b) expectedTokens.push(b);
      }
    }

    const context: string[] = [];
    const ctxCount = Number(toBigInt(this.#ffi.galley_diagnostic_context_count(h) as bigint));
    if (ctxCount > 0) {
      for (let i = 0; i < ctxCount; i++) {
        const b = this.#tryCopyBytes((od, ol) => this.#ffi.galley_diagnostic_context_at(h, i, od, ol));
        if (b) context.push(Buffer.from(b).toString("utf-8"));
      }
    }

    const syntaxErrorCount = Number(toBigInt(this.#ffi.galley_syntax_error_count(h) as bigint));

    let indentation: [number, number] | null = null;
    {
      const outSpaces: unknown[] = [0];
      const outWidth: unknown[] = [0];
      if ((this.#ffi.galley_diagnostic_indentation(h, outSpaces, outWidth) as number) === 0) {
        indentation = [outSpaces[0] as number, outWidth[0] as number];
      }
    }

    const recovery = this.#readRecoverySingular(h);

    return {
      kind,
      line,
      column: col,
      message,
      messageAnsi,
      unexpectedToken: unexpected,
      expectedTokens,
      context,
      syntaxErrorCount: syntaxErrorCount < 0 ? 0 : syntaxErrorCount,
      indentation,
      ...recovery,
    };
  }

  diagnostic(): Diagnostic | null {
    const h = this.#requireHandle();
    if (!this.#ffi.galley_has_diagnostic(h)) return null;
    return this.#buildDiagnosticSingular();
  }

  diagnostics(): Diagnostic[] {
    const h = this.#requireHandle();
    const count = Number(toBigInt(this.#ffi.galley_recorded_diagnostic_count(h) as bigint));
    if (count <= 0) return [];
    const out: Diagnostic[] = [];
    for (let i = 0; i < count; i++) {
      const d = this.#buildRecordedDiagnostic(i);
      if (d) out.push(d);
    }
    return out;
  }

  #buildRecordedDiagnostic(index: number): Diagnostic | null {
    const h = this.#requireHandle();
    const outLine: unknown[] = [0];
    const outCol: unknown[] = [0];
    const st = this.#ffi.galley_recorded_diagnostic_position(h, index, outLine, outCol);
    if ((typeof st === "bigint" ? st < 0n : (st as number) < 0)) return null;

    const kind = Number(toBigInt(this.#ffi.galley_recorded_diagnostic_kind(h, index) as bigint));
    const line = outLine[0] as number;
    const col = outCol[0] as number;

    const outMsg: unknown[] = [null];
    let message = "";
    let messageAnsi = "";
    if ((this.#ffi.galley_recorded_diagnostic_message(h, index, outMsg) as number) === 0) {
      message = outMsg[0] as string;
      messageAnsi = message;
    }

    const unexpected = this.#tryCopyBytes((od, ol) =>
      this.#ffi.galley_recorded_unexpected_token(h, index, od, ol),
    );

    const expectedTokens: Uint8Array[] = [];
    const expCount = Number(
      toBigInt(this.#ffi.galley_recorded_expected_count(h, index) as bigint),
    );
    if (expCount > 0) {
      for (let j = 0; j < expCount; j++) {
        const b = this.#tryCopyBytes((od, ol) =>
          this.#ffi.galley_recorded_expected_token(h, index, j, od, ol),
        );
        if (b) expectedTokens.push(b);
      }
    }

    const context: string[] = [];
    const ctxCount = Number(
      toBigInt(this.#ffi.galley_recorded_context_count(h, index) as bigint),
    );
    if (ctxCount > 0) {
      for (let j = 0; j < ctxCount; j++) {
        const b = this.#tryCopyBytes((od, ol) =>
          this.#ffi.galley_recorded_context_name(h, index, j, od, ol),
        );
        if (b) context.push(Buffer.from(b).toString("utf-8"));
      }
    }

    let indentation: [number, number] | null = null;
    {
      const outSpaces: unknown[] = [0];
      const outWidth: unknown[] = [0];
      if (
        (this.#ffi.galley_recorded_indentation(h, index, outSpaces, outWidth) as number) === 0
      ) {
        indentation = [outSpaces[0] as number, outWidth[0] as number];
      }
    }

    const recovery = this.#readRecoveryRecorded(h, index);

    return {
      kind,
      line,
      column: col,
      message,
      messageAnsi,
      unexpectedToken: unexpected,
      expectedTokens,
      context,
      syntaxErrorCount: 0,
      indentation,
      ...recovery,
    };
  }

  // -- recovery ---------------------------------------------------------

  #readRecoverySingular(handle: bigint): Omit<
    Diagnostic,
    | "kind"
    | "line"
    | "column"
    | "message"
    | "messageAnsi"
    | "unexpectedToken"
    | "expectedTokens"
    | "context"
    | "syntaxErrorCount"
    | "indentation"
  > {
    const h = handle;
    const kindVal = Number(toBigInt(this.#ffi.galley_diagnostic_recovery_kind(h) as bigint));
    const recoveryKind = kindVal === 0 ? null : kindVal;

    const terminal = this.#tryCopyBytes((od, ol) =>
      this.#ffi.galley_diagnostic_recovery_terminal(h, od, ol),
    );

    let resume: number | null = null;
    {
      const out: unknown[] = [0n];
      if ((this.#ffi.galley_diagnostic_recovery_resume(h, out) as number) === 0) {
        resume = Number(toBigInt(out[0] as bigint));
      }
    }

    const lhs = this.#tryCopyString((od, ol) =>
      this.#ffi.galley_diagnostic_recovery_lhs_variable(h, od, ol),
    );

    let production: [string, number] | null = null;
    {
      const outVar: unknown[] = [null];
      const outLen: unknown[] = [0];
      const outIdx: unknown[] = [0];
      if (
        (this.#ffi.galley_diagnostic_recovery_production(h, outVar, outLen, outIdx) as number) === 0
      ) {
        production = [copyStringBytes(outVar[0] as bigint, outLen[0] as bigint), outIdx[0] as number];
      }
    }

    let occurrence: [string, number, number, string] | null = null;
    {
      const outParent: unknown[] = [null];
      const outParentLen: unknown[] = [0];
      const outRhs: unknown[] = [0];
      const outSym: unknown[] = [0];
      const outVar: unknown[] = [null];
      const outVarLen: unknown[] = [0];
      if (
        (this.#ffi.galley_diagnostic_recovery_occurrence(
          h,
          outParent,
          outParentLen,
          outRhs,
          outSym,
          outVar,
          outVarLen,
        ) as number) === 0
      ) {
        occurrence = [
          copyStringBytes(outParent[0] as bigint, outParentLen[0] as bigint),
          outRhs[0] as number,
          outSym[0] as number,
          copyStringBytes(outVar[0] as bigint, outVarLen[0] as bigint),
        ];
      }
    }

    return {
      recoveryKind,
      recoveryTerminal: terminal,
      recoveryResume: resume,
      recoveryLhsVariable: lhs,
      recoveryProduction: production,
      recoveryOccurrence: occurrence,
    };
  }

  #readRecoveryRecorded(
    handle: bigint,
    idx: number,
  ): Omit<
    Diagnostic,
    | "kind"
    | "line"
    | "column"
    | "message"
    | "messageAnsi"
    | "unexpectedToken"
    | "expectedTokens"
    | "context"
    | "syntaxErrorCount"
    | "indentation"
  > {
    const h = handle;
    const kindVal = Number(
      toBigInt(this.#ffi.galley_recorded_recovery_kind(h, idx) as bigint),
    );
    const recoveryKind = kindVal === 0 ? null : kindVal;

    const terminal = this.#tryCopyBytes((od, ol) =>
      this.#ffi.galley_recorded_recovery_terminal(h, idx, od, ol),
    );

    let resume: number | null = null;
    {
      const out: unknown[] = [0n];
      if ((this.#ffi.galley_recorded_recovery_resume(h, idx, out) as number) === 0) {
        resume = Number(toBigInt(out[0] as bigint));
      }
    }

    const lhs = this.#tryCopyString((od, ol) =>
      this.#ffi.galley_recorded_recovery_lhs_variable(h, idx, od, ol),
    );

    let production: [string, number] | null = null;
    {
      const outVar: unknown[] = [null];
      const outLen: unknown[] = [0];
      const outIdx: unknown[] = [0];
      if (
        (this.#ffi.galley_recorded_recovery_production(h, idx, outVar, outLen, outIdx) as number) ===
        0
      ) {
        production = [copyStringBytes(outVar[0] as bigint, outLen[0] as bigint), outIdx[0] as number];
      }
    }

    let occurrence: [string, number, number, string] | null = null;
    {
      const outParent: unknown[] = [null];
      const outParentLen: unknown[] = [0];
      const outRhs: unknown[] = [0];
      const outSym: unknown[] = [0];
      const outVar: unknown[] = [null];
      const outVarLen: unknown[] = [0];
      if (
        (this.#ffi.galley_recorded_recovery_occurrence(
          h,
          idx,
          outParent,
          outParentLen,
          outRhs,
          outSym,
          outVar,
          outVarLen,
        ) as number) === 0
      ) {
        occurrence = [
          copyStringBytes(outParent[0] as bigint, outParentLen[0] as bigint),
          outRhs[0] as number,
          outSym[0] as number,
          copyStringBytes(outVar[0] as bigint, outVarLen[0] as bigint),
        ];
      }
    }

    return {
      recoveryKind,
      recoveryTerminal: terminal,
      recoveryResume: resume,
      recoveryLhsVariable: lhs,
      recoveryProduction: production,
      recoveryOccurrence: occurrence,
    };
  }

  // -- tree editing ----------------------------------------------------

  appendChildren(parent: Node | bigint, chain: Node | bigint): void {
    const h = this.#requireHandle();
    const st = this.#ffi.galley_tree_append_children(h, toNodeAddress(parent), toNodeAddress(chain));
    this.#checkStatus(st);
  }

  insertBefore(target: Node | bigint, chain: Node | bigint): void {
    const h = this.#requireHandle();
    const st = this.#ffi.galley_tree_insert_before(h, toNodeAddress(target), toNodeAddress(chain));
    this.#checkStatus(st);
  }

  insertAfter(target: Node | bigint, chain: Node | bigint): void {
    const h = this.#requireHandle();
    const st = this.#ffi.galley_tree_insert_after(h, toNodeAddress(target), toNodeAddress(chain));
    this.#checkStatus(st);
  }

  removeSiblings(node: Node | bigint, count: number): Node | null {
    const h = this.#requireHandle();
    const outHead: unknown[] = [INVALID_NODE];
    const st = this.#ffi.galley_tree_remove_siblings(h, toNodeAddress(node), count, outHead);
    this.#checkStatus(st);
    return optNode(this, outHead[0] as bigint);
  }

  removeSelf(node: Node | bigint): Node | null {
    const h = this.#requireHandle();
    const outHead: unknown[] = [INVALID_NODE];
    const st = this.#ffi.galley_tree_remove_self(h, toNodeAddress(node), outHead);
    this.#checkStatus(st);
    return optNode(this, outHead[0] as bigint);
  }

  promoteChildrenOverWrapper(wrapper: Node | bigint): Node | null {
    const h = this.#requireHandle();
    const outHead: unknown[] = [INVALID_NODE];
    const st = this.#ffi.galley_tree_promote_children_over_wrapper(
      h,
      toNodeAddress(wrapper),
      outHead,
    );
    this.#checkStatus(st);
    return optNode(this, outHead[0] as bigint);
  }

  cleanChildren(node: Node | bigint): Node | null {
    const h = this.#requireHandle();
    const outHead: unknown[] = [INVALID_NODE];
    const st = this.#ffi.galley_tree_clean_children(h, toNodeAddress(node), outHead);
    this.#checkStatus(st);
    return optNode(this, outHead[0] as bigint);
  }

  unlinkWrapper(wrapper: Node | bigint): void {
    const h = this.#requireHandle();
    const st = this.#ffi.galley_tree_unlink_wrapper(h, toNodeAddress(wrapper));
    this.#checkStatus(st);
  }

  insertChildrenAt(parent: Node | bigint, index: number, chain: Node | bigint): void {
    const h = this.#requireHandle();
    const st = this.#ffi.galley_tree_insert_children_at(
      h,
      toNodeAddress(parent),
      index,
      toNodeAddress(chain),
    );
    this.#checkStatus(st);
  }

  removeChildrenAt(parent: Node | bigint, index: number, count: number): Node | null {
    const h = this.#requireHandle();
    const outHead: unknown[] = [INVALID_NODE];
    const st = this.#ffi.galley_tree_remove_children_at(
      h,
      toNodeAddress(parent),
      index,
      count,
      outHead,
    );
    this.#checkStatus(st);
    return optNode(this, outHead[0] as bigint);
  }

  // -- symbol table ----------------------------------------------------

  symbolNameAt(index: number): Uint8Array | null {
    const h = this.#requireHandle();
    const outData: unknown[] = [null];
    const outLen: unknown[] = [0];
    const st = this.#ffi.galley_symbol_name(h, BigInt(index), outData, outLen);
    if ((typeof st === "bigint" ? st < 0n : (st as number) < 0)) return null;
    return copyBytes(outData[0] as bigint, outLen[0] as bigint);
  }

  symbolIsTerminal(index: number): boolean {
    const h = this.#requireHandle();
    return this.#ffi.galley_symbol_is_terminal(h, BigInt(index)) !== 0;
  }

  variableNameAt(index: number): Uint8Array | null {
    const h = this.#requireHandle();
    const outData: unknown[] = [null];
    const outLen: unknown[] = [0];
    const st = this.#ffi.galley_variable_name(h, BigInt(index), outData, outLen);
    if ((typeof st === "bigint" ? st < 0n : (st as number) < 0)) return null;
    return copyBytes(outData[0] as bigint, outLen[0] as bigint);
  }
}
