"""
Type stubs for a Galley language package.

The package is compiled per grammar via ``python -m galley`` and
wraps the C ABI in ``bindings/c/galley.h``.  This stub is the single
source of truth for type checkers (``ty``, ``mypy``, ``pyright``) and
editor auto-complete.  It is shipped as ``__init__.pyi`` by
the build command so the language package resolves without inline hints.

Sessions are not thread-safe, but a parse releases the GIL, so sessions on
different threads parse in parallel.  Node handles are
``galley_impl.Node`` objects bound to their owning ``Session`` – a node is
the only thing accepted where a node is expected, and
``Session.snapshot().node(index)`` is the one conversion from a stored
address back to a node.  Module-level procedure hooks are the artifact's
defaults; every
session owns a copy taken when it opens.  All text/diagnostic
accessors copy before returning.
"""

from __future__ import annotations

import enum
import os
from collections.abc import Iterator
from typing import Any, Final

# ---------------------------------------------------------------------------
# Module-level enums (from galley.h, exposed as IntEnum classes)
# ---------------------------------------------------------------------------

class ParserType(enum.IntEnum):
    """Parser families."""

    LL = 0
    LR = 1

class RecoveryMode(enum.IntEnum):
    """Error recovery modes."""

    DISABLED = 0
    AUTOMATIC = 1
    EXPLICIT = 2

class Kind(enum.IntEnum):
    """Diagnostic kinds."""

    NONE = 0
    SYNTAX = 1
    INDENTATION = 2
    SEMANTIC = 3

class RecoveryTarget(enum.IntEnum):
    """Recovery targets."""

    NONE = 0
    LHS_VARIABLE = 1
    PRODUCTION = 2
    OCCURRENCE = 3

class Resume(enum.IntEnum):
    """Resume sides."""

    BEFORE = 0
    AFTER = 1

class Status(enum.IntEnum):
    """Status codes (negative on failure)."""

    OK = 0
    ERROR_NULL_ARGUMENT = -1
    ERROR_SYNTAX = -2
    ERROR_INDENTATION = -3
    ERROR_STACK_OVERFLOW = -4
    ERROR_AST_CAPACITY_EXCEEDED = -5
    ERROR_UNTERMINATED_RAW_STRING = -6
    ERROR_OUT_OF_MEMORY = -7
    ERROR_INTERNAL = -8
    ERROR_NO_DIAGNOSTIC = -9
    ERROR_INVALID_NODE = -10
    ERROR_IO = -11
    ERROR_SEMANTIC = -12
    ERROR_SESSION_IN_USE = -13
    ERROR_STALE_TREE = -14

INVALID_NODE: Final[int]
"""``2**63 - 1``, the address marking an absent node link."""

# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------

class GalleyError(Exception):
    """Failure reported by a Galley operation.

    Attributes:
        code: Raw ``galley_status`` value (negative on failure).
        diagnostic: Snapshot of the session diagnostic at failure, or ``None``.

    ``str(error)`` is the rendered diagnostic message when there is one,
    otherwise the status string.
    """

    code: int
    diagnostic: Diagnostic | None

class StaleTreeError(GalleyError):
    """The tree a handle belongs to is gone.

    Raised by every session-door read of a node, walk, or snapshot whose
    parse generation the core no longer holds live: the session parsed again
    since, the last parse published nothing, or nothing was ever published.
    A subclass of :class:`GalleyError` with code ``ERROR_STALE_TREE``, so
    ``except GalleyError`` still catches it. Distinct from use after
    ``close()``, which raises ``ValueError``.
    """

# ---------------------------------------------------------------------------
# Diagnostic snapshot — read-only, frozen at parse failure
# ---------------------------------------------------------------------------

class Diagnostic:
    """Read-only snapshot of the last diagnostic.

    All ``bytes`` fields are copies that remain valid after the next parse.
    """

    kind: int
    """``Kind`` classification (``Kind.SYNTAX``, ...)."""
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
    semantic_error_count: int
    """How many semantic errors the parse recorded."""
    semantic: tuple[bytes, str] | None
    """``(variable bytes, message)`` for semantic errors, else ``None``."""
    indentation: tuple[int, int] | None
    """``(emitted spaces, width)`` for indentation errors, else ``None``."""
    recovery_kind: int | None
    """``RecoveryTarget`` of the applied recovery, if any."""
    recovery_terminal: bytes | None
    """Synchronization terminal bytes chosen by recovery."""
    recovery_resume: int | None
    """``Resume.BEFORE`` or ``Resume.AFTER``."""
    recovery_lhs_variable: bytes | None
    """LHS variable scope of the applied recovery."""
    recovery_production: tuple[bytes, int] | None
    """``(variable, rhs_index)`` of the production scope."""
    recovery_occurrence: tuple[bytes, int, int, bytes] | None
    """``(parent variable, rhs index, symbol index, variable)``."""

# ---------------------------------------------------------------------------
# Node handle — session-backed, hashable, indexable, iterable over children
# ---------------------------------------------------------------------------

class Node:
    """Handle for a node in the non-relocating AST storage.

    A ``Node`` keeps a strong reference to its ``Session`` and raises
    ``ValueError`` after the session is closed (``close()`` or exiting
    ``with``) or when its parse generation is gone: a node carries the
    core's parse generation and reads only while that generation is live.
    Inside a hook of the session's running parse, on the thread running
    it, a node is live when it belongs to the running parse and reads the
    live parse; anywhere else it is live when it belongs to the tree the
    last successful parse published, so nodes handed out by the hooks of a
    successful parse stay usable until the session parses again, and nodes
    of a failed parse are gone. A call from another thread while a parse
    runs raises ``GalleyError`` with ``ERROR_SESSION_IN_USE``.
    ``Session.snapshot().node(index)`` is the only conversion from a
    stored address back to a node.
    """

    address: int
    """Display-only raw address (stable index in the session's node
    storage); never an argument where a node is expected."""

    def children(self) -> tuple[Node, ...]:
        """Tuple of direct children, from first to last (empty when leaf)."""
        ...

    def text(self) -> bytes:
        """Text bytes of this node.

        Raises ``StaleTreeError`` once the tree this node belongs to is
        gone; there is no "invalid node" answer any more.
        """
        ...

    def symbol_name(self) -> bytes:
        """Symbol name bytes (``b""`` for a terminal-only node)."""
        ...

    def span(self) -> tuple[int, int]:
        """``(start, length)`` byte span of this node."""
        ...

    def line_column(self) -> tuple[int, int]:
        """1-based ``(line, column)`` of this node's first byte."""
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

    def walk(self, *, skip_semantic_errors: bool = False) -> Walker:
        """Pre-order walker over this node's subtree, this node included at
        depth 0.

        Pass ``skip_semantic_errors`` to prune subtrees rooted at
        semantic-error nodes. ``walk()`` itself only refuses a closed
        session (``ValueError``); a node whose tree is gone is refused by the
        core at the walker's first step, which raises ``StaleTreeError``.
        """
        ...

    def clean_children(self) -> Node | None:
        """Detach all children and return the detached chain head, or ``None``."""
        ...

    def append_children(self, chain: Node) -> None:
        """Append a detached ``chain`` as children of this node."""
        ...

    def __len__(self) -> int:
        """Number of direct children."""
        ...

    def __getitem__(self, index: int) -> Node:
        """Child at ``index`` (negative indices supported)."""
        ...

    def __iter__(self) -> Iterator[Node]:
        """Iterate children from first to last."""
        ...

    def __hash__(self) -> int: ...
    def __eq__(self, other: object) -> bool:
        """Equal when same session, same parse generation, and same address."""
        ...

    def __ne__(self, other: object) -> bool: ...
    def __repr__(self) -> str: ...
    def __str__(self) -> str: ...

class Snapshot:
    """One parse as flat columns: one tuple per node address, read-only.

    Returned by ``Session.snapshot``. ``node(index)`` is the one conversion
    from a stored address back to a node, stamped with the parse generation
    these columns describe, so it reads as a stale tree once the session
    parses again.
    """

    count: int
    """Number of nodes in the parse these columns describe."""

    parent: tuple[int | None, ...]
    """Parent address per node; ``None`` where the link does not exist."""

    first_child: tuple[int | None, ...]
    """First child address per node; ``None`` where the link does not exist."""

    next: tuple[int | None, ...]
    """Next sibling address per node; ``None`` where the link does not exist."""

    child_count: tuple[int, ...]
    """Direct child count per node."""

    variable: tuple[int | None, ...]
    """Variable index per node; ``None`` where there is none."""

    span_start: tuple[int, ...]
    """Span start offset per node, into ``Session.last_input()``."""

    span_len: tuple[int, ...]
    """Span length per node."""

    is_semantic_error: tuple[bool, ...]
    """The semantic-error flag a walk step carries, per node."""

    def node(self, index: int) -> Node | None:
        """Node at ``index`` for this snapshot's parse, or ``None`` for
        ``INVALID_NODE``.

        Raises ``TypeError`` when ``index`` is not an ``int`` (a ``bool``
        included), ``IndexError`` when ``index`` is outside
        ``0 .. count - 1``.
        """
        ...

class WalkStep:
    """One position of a walk: read-only, yielded by ``Walker``, never
    constructed from Python."""

    @property
    def node(self) -> Node:
        """The node this step visited."""
        ...

    @property
    def depth(self) -> int:
        """Depth below the walk's root node, which is at depth 0."""
        ...

    @property
    def is_semantic_error(self) -> bool:
        """Whether the visited node is flagged as a semantic error."""
        ...

class Walker(Iterator[WalkStep]):
    """Pre-order tree walker yielding ``WalkStep`` objects.

    Returned by ``Node.walk``; that node yields at depth 0. The walker
    owns no native resource: abandoning it is free, and parsing again with
    a walker alive succeeds — its next step raises ``StaleTreeError``
    instead. Each step picks its door like any node call, so a walk created
    inside a hook of a running parse walks that parse's in-flight tree.
    """

    def __next__(self) -> WalkStep:
        """Next ``WalkStep`` in pre-order.

        Raises ``ValueError`` when the session has closed, and
        ``StaleTreeError`` when it parsed again since the walker was
        created; raises ``GalleyError`` while a parse holds the session
        (``ERROR_SESSION_IN_USE``) or when a step's position is no longer
        inside the walk's root — removed, or moved elsewhere
        (``ERROR_INVALID_NODE``). Raises ``StopIteration`` at the end of the
        walk, including after a later parse: a finished walker stays
        finished.
        """
        ...

    def __iter__(self) -> Walker:
        """The walker is its own iterator."""
        ...

    def skip_children(self) -> None:
        """Prune the children of the last yielded node.

        No effect without a last step; raises ``ValueError`` when the
        session has closed. Staleness is the next step's answer, not this
        one's.
        """
        ...

class ProcedureArguments:
    """Per-hook arguments passed to a procedure hook.

    Valid only while the hook runs: a reference kept past its hook raises
    ``ValueError``. Tree queries use ``current_node()`` and the ordinary
    ``Node`` methods on the returned handle. Those nodes read the live parse
    while the hook runs and stay usable from later hooks of the same parse
    and, when the parse succeeds, until the session parses again. Drop/replace
    talks to the parser through the current-node channel, not
    ``Session.remove_self``.
    """

    def current_node(self) -> Node | None:
        """The node being reduced, or ``None``."""
        ...

    def set_current_node(self, node: Node) -> None:
        """Redirect the current-node channel to ``node``, a node of this parse.

        Raises ``StaleTreeError`` for a node of another parse."""
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

    def report_semantic_error(self, message: str | bytes) -> int:
        """Record a semantic error on the current node; return the total count."""
        ...

# ---------------------------------------------------------------------------
# Session — owns arena + nodes, not thread-safe
# ---------------------------------------------------------------------------

class Session:
    """Parsing session bound to this library's parser.

    Usable as a context manager (``with parser.Session() as s:``); ``close()``
    is idempotent and also runs from ``__del__``.  Use one session per
    thread or guard externally.  Node handles remain valid across edits until
    the next successful parse.

    Keyword options mirror ``galley.h`` defaults:
        max_errors: maximum diagnostics before abort (10).
        recovery_window: max bytes to scan for recovery (500).
        stack_overflow_recovery: allow stack-overflow recovery (False).
        syntax_error_stack_depth: extra stack frames to keep for diagnostics (0).
        verbosity: diagnostic verbosity (0).
        ast_preallocation_ratio: preallocation ratio (``-1.0`` selects default; ``0`` drops the scaled contribution, the floor still applies; the scaled contribution is ignored on segment platforms such as Windows/wasm, where only the floor is prepared eagerly).
        ast_preallocation_cap: minimum ready node storage per parse in nodes (0 = default).
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

    def is_closed(self) -> bool:
        """Whether the session is closed."""
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
        of the input object's lifetime. Raises ``GalleyError`` on failure.
        """
        ...

    def parse_file(
        self, path: str | bytes | os.PathLike[str] | os.PathLike[bytes]
    ) -> int:
        """Parse the file at ``path`` and return bytes parsed. Raises ``Error``."""
        ...

    # -- arena --

    def snapshot(self) -> Snapshot:
        """Flat bulk read of the published tree: a ``Snapshot`` with ``count``
        and one tuple per node address for ``parent``, ``first_child``,
        ``next``, ``child_count``, ``variable``, ``span_start``,
        ``span_len`` and ``is_semantic_error`` (booleans, the flag a walk
        step carries). Missing links and variables are ``None``.

        Raises ``StaleTreeError`` when nothing is published, and
        ``GalleyError`` (``ERROR_SESSION_IN_USE``) while a parse runs.
        """
        ...

    def last_input(self) -> bytes:
        """Retained input of the most recent parse as bytes: the buffer that snapshot spans index. Empty before the first parse."""
        ...

    def node_count(self) -> int:
        """Number of AST nodes of the published tree (0 when ``has_ast`` is false).

        Raises ``StaleTreeError`` when nothing is published.
        """
        ...

    def reserve_nodes(self, capacity: int) -> None:
        """Preallocate storage for at least ``capacity`` nodes."""
        ...

    def node_capacity(self) -> int:
        """Current node storage capacity in nodes."""
        ...

    # -- navigation (``Node`` arguments, ``Node`` results) --

    def root_node(self) -> Node | None:
        """Root of the published tree, or ``None`` when nothing is published.

        Raises ``GalleyError`` (``ERROR_SESSION_IN_USE``) while a parse runs.
        """
        ...

    def child_count(self, node: Node) -> int:
        """Direct child count (0 for a leaf).

        Raises ``StaleTreeError`` if ``node`` belongs to a tree the core no
        longer holds live.
        """
        ...

    def children(self, node: Node) -> tuple[Node, ...]:
        """Tuple of direct children, from first to last."""
        ...

    def first_child(self, node: Node) -> Node | None: ...
    def last_child(self, node: Node) -> Node | None: ...
    def next_sibling(self, node: Node) -> Node | None: ...
    def prior_sibling(self, node: Node) -> Node | None: ...
    def parent(self, node: Node) -> Node | None: ...
    def symbol_name(self, node: Node) -> bytes:
        """Symbol name bytes (``b""`` for a terminal-only node)."""
        ...

    def text(self, node: Node) -> bytes:
        """Text bytes matched by ``node``."""
        ...

    def span(self, node: Node) -> tuple[int, int]:
        """``(start, length)`` byte span of ``node``."""
        ...

    def line_column(self, node: Node) -> tuple[int, int]:
        """1-based ``(line, column)`` of ``node``'s first byte."""
        ...

    def variable_index(self, node: Node) -> int | None:
        """Variable table index, or ``None`` when the node has no variable."""
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

    # -- procedure hooks (this session's own; a copy of the defaults at open) --

    def install_procedure(self, name: str | bytes, callable: Any) -> None:
        """Register a procedure hook on this session only.

        Takes effect from the next parse. Raises ``GalleyError``
        (``ERROR_SESSION_IN_USE``) while a parse is in flight, whether from a
        hook or another thread, and leaves the hooks as they were.
        """
        ...

    def install_procedures(self, source: Any) -> int:
        """Register all procedure hooks found in a module, dict, or object.

        One step, refused like ``install_procedure`` during a parse. Returns
        the number of hooks installed.
        """
        ...

    def procedure_hook(self, name: str | bytes) -> Any | None:
        """Return the callable registered on this session for ``name``, or ``None``."""
        ...

    def clear_procedures(self) -> None:
        """Clear this session's procedure hooks (refused during a parse)."""
        ...

    def list_procedures(self) -> dict[str, Any]:
        """Return a copy of this session's procedure hooks."""
        ...

    # -- tree editing (``Node`` arguments) --

    def append_children(self, parent: Node, chain: Node) -> None:
        """Append detached ``chain`` as children of ``parent``."""
        ...

    def insert_before(self, target: Node, chain: Node) -> None:
        """Insert ``chain`` immediately before ``target`` among siblings."""
        ...

    def insert_after(self, target: Node, chain: Node) -> None:
        """Insert ``chain`` immediately after ``target`` among siblings."""
        ...

    def remove_siblings(self, node: Node, count: int) -> Node | None:
        """Remove ``count`` siblings after ``node`` and return the detached head."""
        ...

    def remove_self(self, node: Node) -> Node | None:
        """Detach ``node`` itself and return the detached head (the node)."""
        ...

    def clean_children(self, node: Node) -> Node | None:
        """Detach all children of ``node`` and return the detached head."""
        ...

    def insert_children_at(self, parent: Node, index: int, chain: Node) -> None:
        """Insert ``chain`` into ``parent``'s children at ``index`` (``len`` appends)."""
        ...

    def remove_children_at(self, parent: Node, index: int, count: int) -> Node | None:
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
    """Parser family: ``ParserType.LL`` or ``ParserType.LR``."""
    ...

def error_recovery_mode() -> int:
    """Recovery mode: ``RecoveryMode.DISABLED`` / ``AUTOMATIC`` / ``EXPLICIT``."""
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
    """Register a default Python procedure hook.

    ``name`` is the hook name (e.g. ``"reduction_Pair"`` or ``"hook_print"``)
    and ``callable`` is invoked with a ``ProcedureArguments`` object (or
    with no args for compatibility). Hooks are no-ops until installed;
    reinstalling replaces the previous callable. Every ``Session`` starts
    with a copy of the defaults, so an install here reaches sessions opened
    after it, never sessions already open (see ``Session.install_procedure``).
    """
    ...

def install_procedures(source: Any) -> int:
    """Register all default procedure hooks found in a module, dict, or object.

    Hooks are ``reduction``, ``reduction_<Variable>``, and ``hook_<name>``
    callables. Returns the number of hooks installed.
    """
    ...

def procedure_hook(name: str | bytes) -> Any | None:
    """Return the default callable registered for hook ``name``, or ``None``."""
    ...

def clear_procedures() -> None:
    """Clear the default procedure hooks. Sessions already open keep theirs."""
    ...

def list_procedures() -> dict[str, Any]:
    """Return a copy of the default procedure hooks."""
    ...
