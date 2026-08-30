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
 * build command `node <galley>/bindings/typescript/build.mjs <language-dir>`
 * detects this file and generates the shim automatically, mirroring Rust's
 * `procedures.rs`.
 */

export function reduction(args: bigint): void {
  process.stderr.write("[hook] reduction\n");
}

export function reduction_Document(args: bigint): void {
  process.stderr.write("[hook] Document\n");
}

export function reduction_PairList(args: bigint): void {
  process.stderr.write("[hook] PairList\n");
}

export function reduction_PairListTail(_args: bigint): void {}

export function reduction_Pair(args: bigint): void {
  process.stderr.write("[hook] Pair\n");
}

export function reduction_Key(args: bigint): void {
  process.stderr.write("[hook] Key\n");
}

export function hook_print(args: bigint): void {
  process.stderr.write("[hook] print (Key)\n");
}

export function reduction_KeyTail(_args: bigint): void {}

export function reduction_Number(args: bigint): void {
  process.stderr.write("[hook] Number\n");
}

export function reduction_NumberTail(_args: bigint): void {}
