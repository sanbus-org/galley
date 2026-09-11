/**
 * Procedure hooks for the keyvalue grammar.
 *
 * Shows ProcedureArguments in action: the current node, its text, children,
 * and source position, plus dropIfEmpty on empty tails. Author-defined
 * grammar hooks arrive as `hook_<name>` — Key is annotated `@print`.
 */

import type { Node, ProcedureArguments } from "@sanbus/galley";

// Runtime-neutral host primitives: TextDecoder and console/process exist
// in Node, Bun, Deno, and browsers alike, so these hook bodies run
// unmodified on every runtime with byte-identical output.
const utf8 = new TextDecoder();

// One stderr sink resolved at import: process.stderr on Node, Bun, and
// Deno (all expose the global), console.error in browsers. Single-arg
// console.error appends its own newline, so bytes match on every runtime.
const emit: (line: string) => void = (() => {
  const stderr = (globalThis as { process?: { stderr?: { write?: unknown } } }).process?.stderr;
  if (stderr && typeof stderr.write === "function") {
    const write = stderr.write as (this: unknown, chunk: string) => void;
    return (line: string) => write.call(stderr, `${line}\n`);
  }
  return (line: string) => console.error(line);
})();

function textOf(node: Node): string {
  const bytes = node.text();
  if (bytes === null) return "";
  return utf8.decode(bytes);
}

function posOf(node: Node): [number, number] {
  return node.lineColumn() ?? [0, 0];
}

function parseU(text: string): number {
  let value = 0;
  for (const ch of text) {
    if (ch >= "0" && ch <= "9") value = value * 10 + (ch.charCodeAt(0) - 48);
  }
  return value;
}

function countPairs(node: Node): [number, number] {
  if (node.symbolName() === "Pair") {
    const text = textOf(node);
    const colon = text.indexOf(":");
    return [1, parseU(colon >= 0 ? text.slice(colon + 1) : "")];
  }
  let count = 0;
  let total = 0;
  for (const child of node) {
    const [childCount, childSum] = countPairs(child);
    count += childCount;
    total += childSum;
  }
  return [count, total];
}

export function reduction(_args: ProcedureArguments): void {}

export function reduction_Key(_args: ProcedureArguments): void {}

export function reduction_PairList(_args: ProcedureArguments): void {}

export function reduction_KeyTail(args: ProcedureArguments): void {
  args.dropIfEmpty();
}

export function reduction_NumberTail(args: ProcedureArguments): void {
  args.dropIfEmpty();
}

export function reduction_PairListTail(args: ProcedureArguments): void {
  args.dropIfEmpty();
}

export function hook_print(args: ProcedureArguments): void {
  const node = args.currentNode();
  if (node === null) return;
  const [line, column] = posOf(node);
  emit(`@print "${textOf(node)}" at ${line}:${column}`);
}

export function reduction_Number(args: ProcedureArguments): void {
  const node = args.currentNode();
  if (node === null) return;
  const [line, column] = posOf(node);
  emit(`Number ${textOf(node)} at ${line}:${column}`);
  const value = Number.parseInt(textOf(node), 10);
  if (Number.isInteger(value) && value > 999) {
    args.reportSemanticError("value out of range");
  }
}

export function reduction_Pair(args: ProcedureArguments): void {
  const node = args.currentNode();
  if (node === null) return;
  const [line, column] = posOf(node);
  const text = textOf(node);
  const colon = text.indexOf(":");
  const key = colon >= 0 ? text.slice(0, colon) : text;
  const number = colon >= 0 ? text.slice(colon + 1) : "";
  emit(`Pair ${key}=${number} (${node.length} children) at ${line}:${column}`);
}

export function reduction_Document(args: ProcedureArguments): void {
  const node = args.currentNode();
  if (node === null) return;
  const [count, total] = countPairs(node);
  emit(`Document ${count} pairs, sum=${total}`);
}
