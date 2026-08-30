"""Procedure hooks for the keyvalue grammar.

Each function fires after the corresponding variable is reduced.
Author-defined grammar hooks arrive namespaced as `hook_<name>` — the
grammar annotates Key with `@print`, and the entry point is `hook_print`,
so it can never collide with unrelated symbols.

These implementations are dispatched through the generated Python shim
(procedures_python.zig) by the extension module; no C is involved. The
build command `python -m galley_bindings <language-dir>`
detects this file and generates the shim automatically, mirroring Rust's
`procedures.rs`.
"""

import sys


def _note(label, args):
    node = args.current_node()
    if node is not None:
        node.text()
        node.children()
    print(f"[hook] {label}", file=sys.stderr, flush=True)


def reduction(args):
    _note("reduction", args)


def reduction_Document(args):
    _note("Document", args)


def reduction_PairList(args):
    _note("PairList", args)


def reduction_PairListTail(args):
    pass


def reduction_Pair(args):
    _note("Pair", args)


def reduction_Key(args):
    _note("Key", args)


def hook_print(args):
    _note("print (Key)", args)


def reduction_KeyTail(args):
    pass


def reduction_Number(args):
    _note("Number", args)


def reduction_NumberTail(args):
    pass
