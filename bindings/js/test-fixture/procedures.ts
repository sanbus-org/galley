/**
 * Procedure hooks for the keyvalue grammar.
 *
 * Shows ProcedureArguments in action: the current node, its text, children,
 * and source position, plus dropIfEmpty on empty tails. Author-defined
 * grammar hooks arrive as `hook_<name>` — Key is annotated `@print`.
 */

import type { Node, ProcedureArguments } from "galley-js-node";

function textOf(node: Node): string {
  const bytes = node.text();
  if (bytes === null) return "";
  return Buffer.from(bytes).toString("utf-8");
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

function emit(line: string): void {
  process.stderr.write(`${line}\n`);
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
