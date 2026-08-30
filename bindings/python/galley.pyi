"""
Type stubs for the Galley CPython extension (``galley``).

The extension is compiled per grammar via ``python -m galley_bindings`` and
wraps the C ABI in ``bindings/c/galley.h``.  This stub is the single
source of truth for type checkers (``ty``, ``mypy``, ``pyright``) and
editor auto-complete.  It is shipped alongside ``galley.*.so`` by
the build command so ``import galley`` resolves without inline hints.

Sessions are not thread-safe; every call holds the GIL.  Node handles are
``galley.Node`` objects bound to their owning ``Session`` – plain ``int``
addresses are still accepted wherever a node is expected for backward
compatibility, and ``int(node)`` / ``operator.index(node)`` recover the
address.  All text/diagnostic accessors copy before returning.
"""

from __future__ import annotations

import os
from collections.abc import Iterator
from typing import Any, Final

# ---------------------------------------------------------------------------
# Module-level constants (from galley.h, exposed via PyModule_AddIntConstant)
# ---------------------------------------------------------------------------

PARSER_TYPE_LL: Final[int]
"""LL parser family."""
PARSER_TYPE_LR: Final[int]
"""LR parser family."""
RECOVERY_MODE_DISABLED: Final[int]
"""No error recovery."""
RECOVERY_MODE_AUTOMATIC: Final[int]
"""Automatic recovery."""
RECOVERY_MODE_EXPLICIT: Final[int]
"""Explicit ``@recovery``-directed recovery."""
KIND_NONE: Final[int]
KIND_SYNTAX: Final[int]
KIND_INDENTATION: Final[int]
RECOVERY_TARGET_NONE: Final[int]
RECOVERY_TARGET_LHS_VARIABLE: Final[int]
RECOVERY_TARGET_PRODUCTION: Final[int]
RECOVERY_TARGET_OCCURRENCE: Final[int]
RESUME_BEFORE: Final[int]
RESUME_AFTER: Final[int]

# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------

class Error(Exception):
    """Failure reported by a Galley operation.

    Attributes:
        code: Raw ``galley_status`` value (negative on failure).
        diagnostic: Snapshot of the session diagnostic at failure, or ``None``.
    """

    code: int
    diagnostic: Diagnostic | None

# ---------------------------------------------------------------------------
# Diagnostic snapshot — read-only, frozen at parse failure
# ---------------------------------------------------------------------------

class Diagnostic:
    """Read-only snapshot of the last diagnostic.

    All ``bytes`` fields are copies that remain valid after the next parse.
    """

    kind: int
    """``KIND_*`` classification."""
    line: int
    """1-based line of the failure."""
    column: int
    """1-based column of the failure."""
    message: str
    """Plain-text rendered message."""
    message_ansi: str
    """Rendered message with ANSI color escapes."""
    unexpected_token: bytes | None
    """Unexpected token bytes (syntax diagnostics only)."""
    expected_tokens: tuple[bytes, ...]
    """Tuple of expected token bytes (syntax only)."""
    context: tuple[bytes, ...]
    """Innermost-first tuple of variables being parsed (syntax only)."""
    syntax_error_count: int
    """How many syntax errors the recovery-enabled parse recorded."""
    indentation: tuple[int, int] | None
    """``(emitted spaces, width)`` for indentation errors, else ``None``."""
    recovery_kind: int | None
    """``RECOVERY_TARGET_*`` of the applied recovery, if any."""
    recovery_terminal: bytes | None
    """Synchronization terminal bytes chosen by recovery."""
    recovery_resume: int | None
    """``RESUME_BEFORE`` or ``RESUME_AFTER``."""
    recovery_lhs_variable: bytes | None
    """LHS variable scope of the applied recovery."""
    recovery_production: tuple[bytes, int] | None
    """``(variable, rhs_index)`` of the production scope."""
    recovery_occurrence: tuple[bytes, int, int, bytes] | None
    """``(parent variable, rhs index, symbol index, variable)``."""

# ---------------------------------------------------------------------------
# Node handle — session-bound, hashable, indexable, iterable over children
# ---------------------------------------------------------------------------

class Node:
    """Session-bound handle for a node in the non-relocating AST storage.

    A ``Node`` keeps a strong reference to its ``Session`` and raises
    ``ValueError`` after the session is closed (``close()`` or exiting
    ``with``).  ``int(node)`` and ``operator.index(node)`` return the raw
    address; plain ``int`` addresses are accepted wherever a ``Node`` is
    expected.
    """

    def children(self) -> tuple[Node, ...]:
        """Tuple of direct children, from first to last (empty when leaf)."""
        ...

    def text(self) -> bytes | None:
        """Text bytes of this node, or ``None`` for an invalid node."""
        ...

    def symbol_name(self) -> bytes | None:
        """Symbol name bytes, or ``None`` for an invalid node."""
        ...

    def span(self) -> tuple[int, int] | None:
        """``(start, length)`` byte span, or ``None`` for an invalid node."""
        ...

    def line_column(self) -> tuple[int, int] | None:
        """1-based ``(line, column)`` of the first byte, or ``None``."""
        ...

    def parent(self) -> Node | None:
        """Parent node, or ``None`` for the root."""
        ...

    def next_sibling(self) -> Node | None:
        """Next sibling, or ``None`` when none."""
        ...

    def prior_sibling(self) -> Node | None:
        """Prior sibling, or ``None`` when none."""
        ...

    def first_child(self) -> Node | None:
        """First child, or ``None`` when leaf."""
        ...

    def last_child(self) -> Node | None:
        """Last child, or ``None`` when leaf."""
        ...

class ProcedureArguments:
    """Parse-time arguments passed to a procedure hook.

    Tree queries use ``current_node()`` and the ordinary ``Node`` methods
    on the returned handle. Drop/replace talks to the parser through the
    current-node channel, not ``Session.remove_self``.
    """

    session: Session | None
    """The ``Session`` currently parsing, or ``None``."""

    def current_node(self) -> Node | None:
        """The node being reduced, or ``None``."""
        ...

    def drop_self(self) -> None:
        """Drop the current node from the parse."""
        ...

    def drop_children(self) -> None:
        """Drop children of the current node."""
        ...

    def drop_if_empty(self) -> None:
        """Drop the current node when it has no children."""
        ...

    def replace_with_children(self) -> None:
        """Replace the current node with its children."""
        ...

    def current_line(self) -> int:
        """Scanner line during this reduction."""
        ...

    def current_column(self) -> int:
        """Scanner column during this reduction."""
        ...

    def clean_children(self) -> Node | None:
        """Detach all children and return the detached chain head, or ``None``."""
        ...

    def append_children(self, chain: Node | int) -> None:
        """Append a detached ``chain`` as children of this node."""
        ...

    def __len__(self) -> int:
        """Number of direct children (``child_count``)."""
        ...

    def __getitem__(self, index: int) -> Node:
        """Child at ``index`` (negative indices supported)."""
        ...

    def __iter__(self) -> Iterator[Node]:
        """Iterate children from first to last (``for child in node:``)."""
        ...

    def __int__(self) -> int:
        """Raw address (stable index in the session's node storage)."""
        ...

    def __index__(self) -> int:
        """Raw address for ``operator.index`` / slicing."""
        ...

    def __hash__(self) -> int: ...
    def __eq__(self, other: object) -> bool:
        """Equal when same session and same address."""
        ...

    def __ne__(self, other: object) -> bool: ...
    def __repr__(self) -> str: ...
    def __str__(self) -> str: ...

# ---------------------------------------------------------------------------
# Session — owns arena + nodes, not thread-safe
# ---------------------------------------------------------------------------

class Session:
    """Parsing session bound to this library's parser.

    Usable as a context manager (``with galley.Session() as s:``); ``close()``
    is idempotent and also runs from ``__del__``.  Use one session per
    thread or guard externally.  Node handles remain valid across edits until
    the next successful parse.

    Keyword options mirror ``galley.h`` defaults:
        max_errors: maximum diagnostics before abort (10).
        recovery_window: max bytes to scan for recovery (500).
        stack_overflow_recovery: allow stack-overflow recovery (False).
        syntax_error_stack_depth: extra stack frames to keep for diagnostics (0).
        verbosity: diagnostic verbosity (0).
        ast_preallocation_ratio: preallocation ratio (``-1.0`` selects default).
        ast_preallocation_cap: preallocation cap in nodes (0 = no cap).
    """

    def __init__(
        self,
        *,
        max_errors: int = 10,
        recovery_window: int = 500,
        stack_overflow_recovery: bool = False,
        syntax_error_stack_depth: int = 0,
        verbosity: int = 0,
        ast_preallocation_ratio: float = -1.0,
        ast_preallocation_cap: int = 0,
    ) -> None: ...
    def close(self) -> None:
        """Release the underlying session; safe to call more than once."""
        ...

    def __enter__(self) -> Session: ...
    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: Any | None,
    ) -> None:
        """Close the session even when the ``with`` block raises."""
        ...

    # -- parsing --

    def parse(self, data: str | bytes | bytearray | memoryview) -> int:
        """Parse ``data`` (may contain NUL bytes) and return bytes parsed.

        Copies ``data`` so node text stays valid after the call regardless
        of the input object's lifetime. Raises ``Error`` on failure.
        """
        ...

    def parse_sentinel(self, data: str | bytes | bytearray | memoryview) -> int:
        """Parse ``data`` without copying input (zero-copy for ``str``).

        The input object must stay alive until the next parse on this
        session. Raises ``Error`` on failure.
        """
        ...

    def parse_file(
        self, path: str | bytes | os.PathLike[str] | os.PathLike[bytes]
    ) -> int:
        """Parse the file at ``path`` and return bytes parsed. Raises ``Error``."""
        ...

    # -- arena --

    def node_count(self) -> int:
        """Number of AST nodes allocated by the last successful parse (0 when ``has_ast`` is false)."""
        ...

    def reserve_nodes(self, capacity: int) -> None:
        """Preallocate storage for at least ``capacity`` nodes."""
        ...

    def node_capacity(self) -> int:
        """Current node storage capacity in nodes."""
        ...

    # -- navigation (all accept ``Node | int`` for backward compat, return ``Node``) --

    def root_node(self) -> Node | None:
        """Root of the last successful parse, or ``None``."""
        ...

    def node_valid(self, node: Node | int) -> bool:
        """Whether ``node`` refers to a live node of the last parse."""
        ...

    def child_count(self, node: Node | int) -> int:
        """Direct child count (0 for invalid nodes)."""
        ...

    def children(self, node: Node | int) -> tuple[Node, ...]:
        """Tuple of direct children, from first to last."""
        ...

    def first_child(self, node: Node | int) -> Node | None: ...
    def last_child(self, node: Node | int) -> Node | None: ...
    def next_sibling(self, node: Node | int) -> Node | None: ...
    def prior_sibling(self, node: Node | int) -> Node | None: ...
    def parent(self, node: Node | int) -> Node | None: ...
    def symbol_name(self, node: Node | int) -> bytes | None:
        """Symbol name bytes, or ``None`` for an invalid node."""
        ...

    def text(self, node: Node | int) -> bytes | None:
        """Text bytes, or ``None`` for an invalid node."""
        ...

    def span(self, node: Node | int) -> tuple[int, int] | None:
        """``(start, length)`` byte span, or ``None`` for an invalid node."""
        ...

    def line_column(self, node: Node | int) -> tuple[int, int] | None:
        """1-based ``(line, column)`` of the first byte, or ``None``."""
        ...

    def variable_index(self, node: Node | int) -> int | None:
        """Variable table index, or ``None`` for an invalid node."""
        ...

    def last_position(self) -> tuple[int, int] | None:
        """1-based ``(line, column)`` just past the last parsed byte, or ``None``."""
        ...

    def has_diagnostic(self) -> bool:
        """Whether the last parse produced a diagnostic."""
        ...

    def diagnostic(self) -> Diagnostic | None:
        """Snapshot of the last diagnostic, or ``None`` on success."""
        ...

    def diagnostics(self) -> tuple[Diagnostic, ...]:
        """All recorded diagnostics (empty tuple on success)."""
        ...

    def set_message_override(self, name: str | bytes, message: str | bytes) -> None:
        """Override the message for variable ``name`` for this session.

        ``message`` may contain ``{line}``, ``{column}``, ``{unexpected}``,
        ``{expected}``, ``{context}`` placeholders.
        """
        ...

    # -- tree editing (accept ``Node | int``) --

    def append_children(self, parent: Node | int, chain: Node | int) -> None:
        """Append detached ``chain`` as children of ``parent``."""
        ...

    def insert_before(self, target: Node | int, chain: Node | int) -> None:
        """Insert ``chain`` immediately before ``target`` among siblings."""
        ...

    def insert_after(self, target: Node | int, chain: Node | int) -> None:
        """Insert ``chain`` immediately after ``target`` among siblings."""
        ...

    def remove_siblings(self, node: Node | int, count: int) -> Node | None:
        """Remove ``count`` siblings after ``node`` and return the detached head."""
        ...

    def remove_self(self, node: Node | int) -> Node | None:
        """Detach ``node`` itself and return the detached head (the node)."""
        ...

    def promote_children_over_wrapper(self, wrapper: Node | int) -> Node | None:
        """Splice ``wrapper``'s children in place of ``wrapper``; return promoted head."""
        ...

    def clean_children(self, node: Node | int) -> Node | None:
        """Detach all children of ``node`` and return the detached head."""
        ...

    def unlink_wrapper(self, wrapper: Node | int) -> None:
        """Detach ``wrapper`` without touching its children."""
        ...

    def insert_children_at(
        self, parent: Node | int, index: int, chain: Node | int
    ) -> None:
        """Insert ``chain`` into ``parent``'s children at ``index`` (``len`` appends)."""
        ...

    def remove_children_at(
        self, parent: Node | int, index: int, count: int
    ) -> Node | None:
        """Remove ``count`` children of ``parent`` at ``index`` and return the head."""
        ...

    def symbol_name_at(self, index: int) -> bytes | None:
        """Symbol name at global symbol table ``index``."""
        ...

    def symbol_is_terminal(self, index: int) -> bool:
        """Whether global symbol ``index`` is a terminal."""
        ...

    def variable_name_at(self, index: int) -> bytes | None:
        """Variable name at ``index``."""
        ...

# ---------------------------------------------------------------------------
# Module-level queries (mirror ``galley.h`` / ``config.zig`` generation options)
# ---------------------------------------------------------------------------

def version() -> str:
    """Build-supplied version string of this library."""
    ...

def parser_type() -> int:
    """Parser family: ``PARSER_TYPE_LL`` or ``PARSER_TYPE_LR``."""
    ...

def error_recovery_mode() -> int:
    """Recovery mode: ``RECOVERY_MODE_DISABLED`` / ``AUTOMATIC`` / ``EXPLICIT``."""
    ...

def has_ast() -> bool:
    """Whether the library was built with AST construction."""
    ...

def has_procedures() -> bool:
    """Whether procedure hooks are compiled in."""
    ...

def allows_no_ast_tree_procedures() -> bool:
    """Whether tree helpers are usable in no-AST mode."""
    ...

def source_retention_enabled() -> bool:
    """Whether sessions retain source text."""
    ...

def has_position_tracking() -> bool:
    """Whether line/column data is meaningful."""
    ...

def has_input_streaming() -> bool:
    """Whether incremental input is supported."""
    ...

def uses_verbatim() -> bool:
    """Whether the grammar uses verbatim capture."""
    ...

def stack_overflow_recovery_available() -> bool:
    """Whether the platform supports stack-overflow recovery."""
    ...

def symbol_count() -> int:
    """How many symbols the grammar declares."""
    ...

def variable_count() -> int:
    """How many variables the grammar declares."""
    ...

def status_string(status: int) -> str | None:
    """Human-readable string for ``status`` code, or ``None`` when unknown."""
    ...

def install_procedure(name: str | bytes, callable: Any) -> None:
    """Register a Python procedure hook.

    ``name`` is the hook name (e.g. ``"reduction_Pair"`` or ``"hook_print"``)
    and ``callable`` is invoked with the opaque ``ProcedureArguments`` pointer
    as an ``int``. Hooks are no-ops until installed; reinstalling replaces
    the previous callable. Mirrors Go's ``hooks/procedures.go`` and Rust's
    ``procedures.rs`` registration.
    """
    ...

def install_procedures(source: Any) -> int:
    """Register all procedure hooks found in a module, dict, or object.

    Hooks are ``reduction``, ``reduction_<Variable>``, and ``hook_<name>``
    callables. Returns the number of hooks installed.
    """
    ...

def clear_procedures() -> None:
    """Clear all registered Python procedure hooks."""
    ...

def list_procedures() -> dict[str, Any]:
    """Return a copy of currently registered Python procedure hooks."""
    ...
