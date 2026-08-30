"""Procedure hooks for the keyvalue grammar.

Each function fires after the corresponding variable is reduced.
Author-defined grammar hooks arrive namespaced as `hook_<name>` — the
grammar annotates Key with `@print`, and the entry point is `hook_print`,
so it can never collide with unrelated symbols.

These implementations are dispatched through the generated Python shim
(procedures_python.zig) by the extension module; no C is involved. The
build command `python3 <galley>/bindings/python/build.py <language-dir>`
detects this file (or `hooks/procedures.py`) and generates the shim
automatically, mirroring Go's `hooks/procedures.go` and Rust's
`procedures.rs`.
"""

import sys


def reduction(args):
    print("[hook] reduction", file=sys.stderr, flush=True)


def reduction_Document(args):
    print("[hook] Document", file=sys.stderr, flush=True)


def reduction_PairList(args):
    print("[hook] PairList", file=sys.stderr, flush=True)


def reduction_PairListTail(args):
    pass


def reduction_Pair(args):
    print("[hook] Pair", file=sys.stderr, flush=True)


def reduction_Key(args):
    print("[hook] Key", file=sys.stderr, flush=True)


def hook_print(args):
    print("[hook] print (Key)", file=sys.stderr, flush=True)


def reduction_KeyTail(args):
    pass


def reduction_Number(args):
    print("[hook] Number", file=sys.stderr, flush=True)


def reduction_NumberTail(args):
    pass
