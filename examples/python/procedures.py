"""Procedure hooks for the keyvalue grammar.

Shows ProcedureArguments in action: the current node, its text, children,
and source position, plus drop_if_empty on empty tails. Author-defined
grammar hooks arrive as hook_<name> — Key is annotated ``@print``.
"""

from __future__ import annotations

import sys

import galley


def _text(node: galley.Node) -> str:
    raw = node.text()
    return raw.decode() if raw else ""


def _name(node: galley.Node) -> str:
    raw = node.symbol_name()
    return raw.decode() if raw else ""


def _pos(node: galley.Node) -> tuple[int, int]:
    position = node.line_column()
    if position is None:
        return 0, 0
    return position


def _emit(line: str) -> None:
    print(line, file=sys.stderr, flush=True)


def _count_pairs(node: galley.Node) -> tuple[int, int]:
    if _name(node) == "Pair":
        text = _text(node)
        number = text.split(":", 1)[1] if ":" in text else "0"
        digits = "".join(ch for ch in number if ch.isdigit())
        return 1, int(digits) if digits else 0
    count = 0
    total = 0
    for child in node:
        child_count, child_sum = _count_pairs(child)
        count += child_count
        total += child_sum
    return count, total


def reduction(_args: galley.ProcedureArguments) -> None:
    pass


def reduction_Key(_args: galley.ProcedureArguments) -> None:
    pass


def reduction_PairList(_args: galley.ProcedureArguments) -> None:
    pass


def reduction_KeyTail(args: galley.ProcedureArguments) -> None:
    args.drop_if_empty()


def reduction_NumberTail(args: galley.ProcedureArguments) -> None:
    args.drop_if_empty()


def reduction_PairListTail(args: galley.ProcedureArguments) -> None:
    args.drop_if_empty()


def hook_print(args: galley.ProcedureArguments) -> None:
    node = args.current_node()
    if node is None:
        return
    line, column = _pos(node)
    _emit(f'@print "{_text(node)}" at {line}:{column}')


def reduction_Number(args: galley.ProcedureArguments) -> None:
    node = args.current_node()
    if node is None:
        return
    line, column = _pos(node)
    _emit(f"Number {_text(node)} at {line}:{column}")


def reduction_Pair(args: galley.ProcedureArguments) -> None:
    node = args.current_node()
    if node is None:
        return
    line, column = _pos(node)
    text = _text(node)
    key, _, number = text.partition(":")
    _emit(f"Pair {key}={number} ({len(node)} children) at {line}:{column}")


def reduction_Document(args: galley.ProcedureArguments) -> None:
    node = args.current_node()
    if node is None:
        return
    count, total = _count_pairs(node)
    _emit(f"Document {count} pairs, sum={total}")
