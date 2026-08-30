/**
 * Procedure hooks for the keyvalue grammar.
 *
 * Each function fires after the corresponding variable is reduced.
 * Author-defined grammar hooks arrive namespaced as `hook_<name>` — the
 * grammar annotates Key with `@print`, and the entry point is `hook_print`,
 * so it can never collide with unrelated symbols.
 *
 * These implementations are dispatched through the generated TypeScript shim
 * (procedures_typescript.zig) by the JS runtime; no C is involved. The
 * build command `npx galley-typescript-bindings <language-dir>` detects this
 * file and generates the shim automatically, mirroring Rust's
 * `procedures.rs`.
 */

import type { ProcedureArguments } from "galley-typescript-bindings";

function note(label: string, args: ProcedureArguments): void {
  const node = args.currentNode();
  if (node !== null) {
    node.text();
    node.children();
  }
  process.stderr.write(`[hook] ${label}\n`);
}

export function reduction(args: ProcedureArguments): void {
  note("reduction", args);
}

export function reduction_Document(args: ProcedureArguments): void {
  note("Document", args);
}

export function reduction_PairList(args: ProcedureArguments): void {
  note("PairList", args);
}

export function reduction_PairListTail(_args: ProcedureArguments): void {}

export function reduction_Pair(args: ProcedureArguments): void {
  note("Pair", args);
}

export function reduction_Key(args: ProcedureArguments): void {
  note("Key", args);
}

export function hook_print(args: ProcedureArguments): void {
  note("print (Key)", args);
}

export function reduction_KeyTail(_args: ProcedureArguments): void {}

export function reduction_Number(args: ProcedureArguments): void {
  note("Number", args);
}

export function reduction_NumberTail(_args: ProcedureArguments): void {}
