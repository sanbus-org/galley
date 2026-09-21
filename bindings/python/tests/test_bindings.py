"""Behavioral tests for the Galley Python bindings.

The suite imports the built fixture package directly (built on demand,
never examples/):

    GALLEY_CHECKOUT=$PWD python -m galley bindings/python/test_fixture
    PYTHONPATH=bindings/python python3 bindings/python/tests/test_bindings.py
"""

from __future__ import annotations

import shutil
import sys
import sysconfig
import tempfile
import unittest
from pathlib import Path
from typing import Any

import galley

BINDINGS_DIRECTORY = Path(__file__).resolve().parent.parent
if str(BINDINGS_DIRECTORY) not in sys.path:
    sys.path.insert(0, str(BINDINGS_DIRECTORY))

# The grammar-bound package under test; every `grammar.` below is one
# artifact's surface (Session, GalleyError, hooks registry), imported directly
# so bundled `procedures.py` hooks wire automatically.
import test_fixture as grammar

FIXTURE_DIRECTORY = BINDINGS_DIRECTORY / "test_fixture"


def _fixture_impl_file() -> Path:
    suffix = sysconfig.get_config_var("EXT_SUFFIX")
    return FIXTURE_DIRECTORY / f"galley_impl{suffix}"


def _restore_procedures(saved: dict[str, Any]) -> None:
    """Return the global hook table to a snapshot.

    Procedure hooks are module-global, so a test that installs or clears
    must not leak into the next one: snapshot in setUp, restore here.
    """
    grammar.clear_procedures()
    if saved:
        grammar.install_procedures(saved)


class ModuleSurfaceTests(unittest.TestCase):
    def test_stub_matches_extension_surface(self):
        # __init__.pyi is a hand-kept mirror of the package API: it must
        # name exactly what the module exposes, in either direction, or
        # type-checked code and runtime drift apart silently.
        import ast
        import pathlib

        stub_path = pathlib.Path(grammar.__file__).parent / "__init__.pyi"
        self.assertTrue(stub_path.is_file(), f"missing {stub_path}")
        names: list[str] = []
        for node in ast.parse(stub_path.read_text(encoding="utf-8")).body:
            if isinstance(node, (ast.ClassDef, ast.FunctionDef)):
                names.append(node.name)
            elif isinstance(node, ast.Assign):
                names += [t.id for t in node.targets if isinstance(t, ast.Name)]
            elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
                names.append(node.target.id)
        module_names = [n for n in dir(grammar) if not n.startswith("_")]
        self.assertEqual(sorted(set(names)), sorted(set(module_names)))

    def test_version_returns_non_empty_string(self):
        self.assertIsInstance(grammar.version(), str)
        self.assertNotEqual(grammar.version(), "")

    def test_parser_metadata_flags_are_consistent(self):
        self.assertIn(
            grammar.parser_type(), (grammar.ParserType.LL, grammar.ParserType.LR)
        )
        self.assertTrue(grammar.has_ast())
        self.assertIsInstance(grammar.has_procedures(), bool)
        self.assertIsInstance(grammar.allows_no_ast_tree_procedures(), bool)
        self.assertIsInstance(grammar.source_retention_enabled(), bool)
        self.assertIsInstance(grammar.has_position_tracking(), bool)
        self.assertIsInstance(grammar.has_input_streaming(), bool)
        self.assertIsInstance(grammar.uses_verbatim(), bool)
        self.assertIsInstance(grammar.stack_overflow_recovery_available(), bool)
        self.assertIn(
            grammar.error_recovery_mode(),
            (
                grammar.RecoveryMode.DISABLED,
                grammar.RecoveryMode.AUTOMATIC,
                grammar.RecoveryMode.EXPLICIT,
            ),
        )

    def test_status_string_renders_known_codes(self):
        rendered = grammar.status_string(grammar.Status.ERROR_SYNTAX)
        self.assertIsInstance(rendered, str)
        assert rendered is not None
        self.assertIn("syntax", rendered.lower())
        self.assertIsNone(grammar.status_string(999999))

    def test_diagnostic_type_is_not_directly_constructible(self):
        with self.assertRaises(TypeError):
            grammar.Diagnostic()

    def test_scanned_hooks_share_error_class(self):
        # The bundled procedures.py wires into the grammar's own registry:
        # hooks fire, and the raised error is the package's Error class.
        from test_fixture import procedures

        self.assertIs(sys.modules["test_fixture.procedures"], procedures)
        self.assertTrue(grammar.list_procedures())
        with grammar.Session() as session:
            with self.assertRaises(grammar.GalleyError) as raised:
                session.parse("alpha:")
            self.assertIs(type(raised.exception), grammar.GalleyError)


class SessionTests(unittest.TestCase):
    session: grammar.Session
    saved_procedures: dict[str, Any]

    def setUp(self) -> None:
        self.session = grammar.Session(max_errors=10)
        self.saved_procedures = grammar.list_procedures()

    def tearDown(self) -> None:
        self.session.close()
        _restore_procedures(self.saved_procedures)

    def test_procedure_hook_can_read_node_text(self) -> None:
        seen: list[bytes] = []

        def reduction_Pair(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            self.assertIsNotNone(node)
            assert node is not None
            self.assertIs(args.session, self.session)
            text = node.text()
            self.assertIsInstance(text, bytes)
            assert text is not None
            self.assertGreater(len(text), 0)
            seen.append(text)

        grammar.install_procedure("reduction_Pair", reduction_Pair)
        try:
            self.session.parse("alpha:12,beta:3")
        finally:
            grammar.clear_procedures()
        self.assertEqual(len(seen), 2)

    def test_nested_parse_restores_outer_gates(self) -> None:
        # A hook that swaps the hook set around a nested parse on another
        # session must not silence the enclosing parse: gates restore on
        # nested exit, and mid-parse edits apply to later parses only.
        outer_seen: list[bytes] = []
        inner_seen: list[bytes] = []
        nested = False

        def outer_pair(args: grammar.ProcedureArguments) -> None:
            nonlocal nested
            node = args.current_node()
            assert node is not None
            text = node.text()
            assert text is not None
            outer_seen.append(text)
            if not nested:
                nested = True
                inner_session = grammar.Session()
                try:
                    grammar.clear_procedures()
                    grammar.install_procedure("reduction_Number", inner_number)
                    try:
                        inner_session.parse("alpha:9")
                    finally:
                        grammar.clear_procedures()
                        grammar.install_procedure("reduction_Pair", outer_pair)
                finally:
                    inner_session.close()

        def inner_number(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            assert node is not None
            text = node.text()
            assert text is not None
            inner_seen.append(text)

        grammar.install_procedure("reduction_Pair", outer_pair)
        try:
            self.session.parse("alpha:12,beta:3")
        finally:
            grammar.clear_procedures()
        self.assertEqual(outer_seen, [b"alpha:12", b"beta:3"])
        self.assertEqual(inner_seen, [b"9"])

    def test_mid_parse_clear_is_invisible_in_flight(self) -> None:
        # Dispatch reads the same entry snapshot as the gates: clearing
        # mid-parse must not silence the enclosing parse's remaining
        # reductions, and the clear applies to parses entered after it.
        seen: list[bytes] = []
        cleared = False

        def outer_pair(args: grammar.ProcedureArguments) -> None:
            nonlocal cleared
            node = args.current_node()
            assert node is not None
            text = node.text()
            assert text is not None
            seen.append(text)
            if not cleared:
                cleared = True
                grammar.clear_procedures()
                inner_session = grammar.Session()
                try:
                    inner_session.parse("alpha:9")
                finally:
                    inner_session.close()

        grammar.install_procedure("reduction_Pair", outer_pair)
        try:
            self.session.parse("alpha:12,beta:3")
        finally:
            grammar.clear_procedures()
        self.assertEqual(seen, [b"alpha:12", b"beta:3"])
        self.assertEqual(grammar.list_procedures(), {})

    def test_parse_accepts_str_bytes_and_buffers(self):
        sample = "alpha:12,beta:3"
        parsed_str = self.session.parse(sample)
        self.assertEqual(parsed_str, len(sample))
        self.assertEqual(self.session.parse(sample.encode()), len(sample))
        self.assertEqual(self.session.parse(bytearray(sample.encode())), len(sample))
        self.assertEqual(self.session.parse(memoryview(sample.encode())), len(sample))

    def test_syntax_error_raises_error_with_code_and_diagnostic(self):
        diagnostic: grammar.Diagnostic | None = None
        try:
            self.session.parse("alpha:")
        except grammar.GalleyError as error:
            self.assertEqual(error.code, grammar.Status.ERROR_SYNTAX)
            diagnostic = error.diagnostic
        else:
            self.fail("expected the broken sample to raise")
        self.assertTrue(self.session.has_diagnostic())
        self.assertIsNotNone(self.session.diagnostic())
        self.assertIsNotNone(diagnostic)
        assert diagnostic is not None
        self.assertEqual(diagnostic.kind, grammar.Kind.SYNTAX)
        self.assertEqual(diagnostic.line, 1)
        self.assertEqual(diagnostic.column, 7)
        self.assertIn("parse failed", diagnostic.message)
        self.assertIsInstance(diagnostic.message_ansi, str)
        self.assertGreater(len(diagnostic.expected_tokens), 0)
        self.assertTrue(
            all(isinstance(token, bytes) for token in diagnostic.expected_tokens)
        )
        self.assertEqual(diagnostic.context[-1], "Number")
        self.assertIsInstance(diagnostic.syntax_error_count, int)

    def test_diagnostic_resets_after_successful_parse(self):
        session = grammar.Session()
        try:
            with self.assertRaises(grammar.GalleyError):
                session.parse("alpha:")
            self.assertIsNotNone(session.diagnostic())
            session.parse("alpha:1")
            self.assertFalse(session.has_diagnostic())
            self.assertIsNone(session.diagnostic())
        finally:
            session.close()

    def test_file_parsing_reports_end_position(self):
        path = "/tmp/galley-python-bindings-test.kv"
        with open(path, "wb") as handle:
            handle.write(b"alpha:12,beta:3")
        parsed = self.session.parse_file(path)
        self.assertEqual(parsed, 15)
        position = self.session.last_position()
        self.assertIsNotNone(position)
        assert position is not None
        end_line, end_column = position
        self.assertEqual((end_line, end_column), (1, 17))


class SemanticErrorTests(unittest.TestCase):
    session: grammar.Session
    saved_procedures: dict[str, Any]

    def setUp(self) -> None:
        self.session = grammar.Session(max_errors=10)
        self.saved_procedures = grammar.list_procedures()

    def tearDown(self) -> None:
        self.session.close()
        _restore_procedures(self.saved_procedures)

    def test_hook_reported_semantic_errors_aggregate_and_fail(self) -> None:
        seen_counts: list[int] = []

        def reduction_Number(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            assert node is not None
            text = node.text()
            assert text is not None
            if int(text) > 99:
                seen_counts.append(args.report_semantic_error("value out of range"))

        grammar.install_procedure("reduction_Number", reduction_Number)
        try:
            with self.assertRaises(grammar.GalleyError) as raised:
                self.session.parse("alpha:12,beta:300,gamma:400")
        finally:
            grammar.clear_procedures()
        self.assertEqual(raised.exception.code, grammar.Status.ERROR_SEMANTIC)
        self.assertIn("value out of range", str(raised.exception))
        self.assertEqual(seen_counts, [1, 2])
        diagnostic = self.session.diagnostic()
        self.assertIsNotNone(diagnostic)
        assert diagnostic is not None
        self.assertEqual(diagnostic.kind, grammar.Kind.SEMANTIC)
        self.assertEqual(diagnostic.line, 1)
        self.assertEqual(diagnostic.semantic_error_count, 2)
        self.assertEqual(diagnostic.semantic, ("Number", "value out of range"))
        self.assertIn("SemanticError", diagnostic.message)
        recorded = self.session.diagnostics()
        self.assertEqual(len(recorded), 2)
        self.assertTrue(all(item.kind == grammar.Kind.SEMANTIC for item in recorded))
        self.assertTrue(
            all(item.semantic == ("Number", "value out of range") for item in recorded)
        )

    def test_counts_reset_after_successful_parse(self) -> None:
        def reduction_Number(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            assert node is not None
            text = node.text()
            assert text is not None
            if int(text) > 99:
                args.report_semantic_error("value out of range")

        grammar.install_procedure("reduction_Number", reduction_Number)
        try:
            with self.assertRaises(grammar.GalleyError):
                self.session.parse("alpha:300")
            self.session.parse("alpha:12")
            self.assertFalse(self.session.has_diagnostic())
            self.assertIsNone(self.session.diagnostic())
            self.assertEqual(len(self.session.diagnostics()), 0)
        finally:
            grammar.clear_procedures()


class ProcedureChannelTests(unittest.TestCase):
    session: grammar.Session
    saved_procedures: dict[str, Any]

    def setUp(self) -> None:
        self.session = grammar.Session(max_errors=10)
        self.saved_procedures = grammar.list_procedures()

    def tearDown(self) -> None:
        self.session.close()
        _restore_procedures(self.saved_procedures)

    def test_is_closed_tracks_close(self) -> None:
        self.assertFalse(self.session.is_closed())
        self.session.close()
        self.assertTrue(self.session.is_closed())

    def test_procedure_hook_returns_installed_callable(self) -> None:
        self.assertIs(
            grammar.procedure_hook("reduction_Pair"),
            self.saved_procedures.get("reduction_Pair"),
        )

        def hook(args: grammar.ProcedureArguments) -> None:
            pass

        grammar.install_procedure("hook_channel_probe", hook)
        try:
            self.assertIs(grammar.procedure_hook("hook_channel_probe"), hook)
        finally:
            grammar.clear_procedures()
        self.assertIsNone(grammar.procedure_hook("hook_channel_probe"))

    def test_current_node_channel_round_trip(self) -> None:
        detached: list[int] = []

        def reduction_Pair(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            assert node is not None
            args.set_current_node(int(node))
            current = args.current_node()
            assert current is not None
            self.assertEqual(int(current), int(node))
            session = args.session
            assert session is not None
            head = session.clean_children(current)
            assert head is not None
            detached.append(int(head))
            session.append_children(current, head)

        grammar.install_procedure("reduction_Pair", reduction_Pair)
        try:
            self.assertEqual(self.session.parse("alpha:12,beta:3"), 15)
        finally:
            grammar.clear_procedures()
        self.assertEqual(len(detached), 2)


class WalkTests(unittest.TestCase):
    session: grammar.Session

    def setUp(self) -> None:
        self.session = grammar.Session()
        self.session.parse("alpha:12,beta:3")

    def tearDown(self) -> None:
        self.session.close()

    def test_root_and_navigation_links(self) -> None:
        root = self.session.root_node()
        self.assertIsNotNone(root)
        assert root is not None
        self.assertTrue(self.session.node_valid(root))
        self.assertIsNone(self.session.parent(root))
        self.assertFalse(self.session.node_valid(grammar.INVALID_NODE))

        first = self.session.first_child(root)
        last = self.session.last_child(root)
        self.assertIsNotNone(first)
        self.assertIsNotNone(last)
        assert first is not None
        assert last is not None
        self.assertIsNone(self.session.next_sibling(last))
        self.assertIsNone(self.session.prior_sibling(first))
        self.assertEqual(self.session.parent(first), root)

        visited: list[grammar.Node] = []
        child = first
        while child is not None:
            visited.append(child)
            child = self.session.next_sibling(child)
        self.assertEqual(len(visited), self.session.child_count(root))

    def test_address_matches_int_conversion(self) -> None:
        root = self.session.root_node()
        assert root is not None
        self.assertEqual(root.address, int(root))
        again = self.session.root_node()
        assert again is not None
        self.assertEqual(again.address, root.address)

    def test_symbol_names_text_spans_and_positions(self) -> None:
        root = self.session.root_node()
        self.assertIsNotNone(root)
        assert root is not None
        self.assertEqual(self.session.symbol_name(root), b"Document")
        text = self.session.text(root)
        self.assertEqual(text, b"alpha:12,beta:3")
        assert text is not None
        span = self.session.span(root)
        self.assertIsNotNone(span)
        assert span is not None
        start, length = span
        self.assertEqual((start, length), (0, len(text)))
        position = self.session.line_column(root)
        self.assertIsNotNone(position)
        assert position is not None
        line, column = position
        self.assertEqual((line, column), (1, 1))
        self.assertIsInstance(self.session.variable_index(root), int)
        self.assertEqual(self.session.node_count() > 0, True)

    def test_terminal_only_nodes_have_empty_symbol_names(self):
        def contains_terminal_only(node: grammar.Node) -> grammar.Node | None:
            if self.session.symbol_name(node) == b"":
                return node
            child = self.session.first_child(node)
            while child is not None:
                found = contains_terminal_only(child)
                if found is not None:
                    return found
                child = self.session.next_sibling(child)
            return None

        root = self.session.root_node()
        self.assertIsNotNone(root)
        assert root is not None
        self.assertIsNotNone(contains_terminal_only(root))

    def test_invalid_node_accessors_return_none(self):
        invalid = grammar.INVALID_NODE
        self.assertIsNone(self.session.symbol_name(invalid))
        self.assertIsNone(self.session.text(invalid))
        self.assertIsNone(self.session.span(invalid))
        self.assertIsNone(self.session.line_column(invalid))
        self.assertIsNone(self.session.variable_index(invalid))
        self.assertEqual(self.session.child_count(invalid), 0)

    def test_walk_matches_hand_rolled_recursion(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        root = self.session.root_node()
        self.assertIsNotNone(root)
        assert root is not None

        def recurse(node: grammar.Node, depth: int, out: list[tuple[int, int]]) -> None:
            out.append((int(node), depth))
            child = self.session.first_child(node)
            while child is not None:
                recurse(child, depth + 1, out)
                child = self.session.next_sibling(child)

        expected: list[tuple[int, int]] = []
        recurse(root, 0, expected)
        self.assertGreater(len(expected), 1)

        walked = [
            (int(step["node"]), step["depth"]) for step in self.session.walk(root)
        ]
        self.assertEqual(expected, walked)
        first = next(iter(self.session.walk(root)))
        self.assertEqual(first["node"], root)
        self.assertEqual(first["depth"], 0)
        self.assertFalse(first["is_semantic_error"])

    def test_snapshot_matches_per_node_accessors(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        snap = self.session.snapshot()
        count = self.session.node_count()
        self.assertEqual(snap["count"], count)
        self.assertGreater(count, 0)
        for key in (
            "parent",
            "first_child",
            "next",
            "child_count",
            "variable",
            "span_start",
            "span_len",
        ):
            self.assertEqual(len(snap[key]), count)
        for address in range(count):
            parent = self.session.parent(address)
            self.assertEqual(
                snap["parent"][address], None if parent is None else int(parent)
            )
            first = self.session.first_child(address)
            self.assertEqual(
                snap["first_child"][address], None if first is None else int(first)
            )
            nxt = self.session.next_sibling(address)
            self.assertEqual(snap["next"][address], None if nxt is None else int(nxt))
            self.assertEqual(
                snap["child_count"][address], self.session.child_count(address)
            )
            self.assertEqual(
                snap["variable"][address], self.session.variable_index(address)
            )
            self.assertEqual(
                (snap["span_start"][address], snap["span_len"][address]),
                self.session.span(address),
            )
        # Spans index last_input.
        data = self.session.last_input()
        self.assertEqual(data, b"alpha:12,beta:3")
        for address in range(count):
            start = snap["span_start"][address]
            length = snap["span_len"][address]
            assert isinstance(start, int) and isinstance(length, int)
            text = self.session.text(address)
            assert text is not None
            self.assertEqual(data[start : start + length], text)
        # The snapshot alone drives the same preorder walk as the walker.
        root = self.session.root_node()
        assert root is not None
        preorder: list[int] = []
        stack = [int(root)]
        while stack:
            node = stack.pop()
            preorder.append(node)
            child = snap["first_child"][node]
            chain: list[int] = []
            while child is not None:
                chain.append(child)
                child = snap["next"][child]
            self.assertEqual(len(chain), snap["child_count"][node])
            stack.extend(reversed(chain))
        walked = [int(step["node"]) for step in self.session.walk(root)]
        self.assertEqual(preorder, walked)

    def test_walk_skip_children_prunes_subtree(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        root = self.session.root_node()
        assert root is not None
        walker = self.session.walk(root)
        first = next(walker)
        self.assertEqual(first["node"], root)
        walker.skip_children()
        self.assertEqual(list(walker), [])
        self.assertIsNone(self.session.walk(grammar.INVALID_NODE))

    def test_walker_close_is_idempotent_and_scoped(self) -> None:
        root = self.session.root_node()
        assert root is not None
        walker = self.session.walk(root)
        next(walker)
        walker.close()
        walker.close()
        with self.assertRaises(ValueError):
            next(walker)
        with self.session.walk(root) as scoped:
            self.assertIsNotNone(next(scoped))

    def test_walker_step_after_reparse_raises(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        root = self.session.root_node()
        assert root is not None
        walker = self.session.walk(root)
        self.assertIsNotNone(next(walker))
        self.assertEqual(self.session.parse("alpha:12,beta:3"), 15)
        with self.assertRaises(ValueError):
            next(walker)
        with self.assertRaises(ValueError):
            walker.skip_children()
        walker.close()
        walker.close()

    def test_parse_with_abandoned_walker_succeeds(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        root = self.session.root_node()
        assert root is not None
        walker = self.session.walk(root)
        # Parsing never raises merely because a walker is open; the
        # abandoned walker fails at its next step instead.
        self.assertEqual(self.session.parse("alpha:12,beta:3"), 15)
        with self.assertRaises(ValueError):
            next(walker)
        walker.close()
        fresh = self.session.root_node()
        assert fresh is not None
        self.assertGreater(len(list(self.session.walk(fresh))), 1)

    def test_failed_parse_invalidates_walkers(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        root = self.session.root_node()
        assert root is not None
        walker = self.session.walk(root)
        self.assertIsNotNone(next(walker))
        with self.assertRaises(grammar.GalleyError):
            self.session.parse("alpha:")
        with self.assertRaises(ValueError):
            next(walker)
        walker.close()

    def test_node_after_reparse_raises(self) -> None:
        root = self.session.root_node()
        assert root is not None
        self.assertGreater(self.session.child_count(root), 0)
        self.session.parse("alpha:12,beta:3")
        with self.assertRaises(ValueError):
            self.session.child_count(root)
        with self.assertRaises(ValueError):
            root.text()
        fresh = self.session.root_node()
        assert fresh is not None
        self.assertGreater(self.session.child_count(fresh), 0)

    def test_walk_reports_no_error_flags_on_a_clean_tree(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        # Failed parses keep the previous successful tree, so error-marked
        # nodes are only reachable through the Zig-native session; bindings
        # walk the last successful parse, which carries no marks. Semantic
        # pruning itself is covered by the runtime fixture tests.
        root = self.session.root_node()
        assert root is not None
        flagged = [
            step["node"]
            for step in self.session.walk(root)
            if step["is_semantic_error"]
        ]
        self.assertEqual(flagged, [])
        pruned = [
            int(step["node"])
            for step in self.session.walk(root, skip_semantic_errors=True)
        ]
        full = [int(step["node"]) for step in self.session.walk(root)]
        self.assertEqual(pruned, full)


class EditTests(unittest.TestCase):
    session: grammar.Session
    root: grammar.Node

    def setUp(self) -> None:
        self.session = grammar.Session()
        self.session.parse("alpha:12,beta:3")
        root = self.session.root_node()
        assert root is not None
        self.root = root

    def tearDown(self) -> None:
        self.session.close()

    def test_clean_and_append_round_trip(self):
        before = self.session.child_count(self.root)
        head = self.session.clean_children(self.root)
        self.assertIsNotNone(head)
        assert head is not None
        self.assertEqual(self.session.child_count(self.root), 0)
        self.session.append_children(self.root, head)
        self.assertEqual(self.session.child_count(self.root), before)

    def test_insert_before_reorders_siblings(self) -> None:
        wrapper = self.session.first_child(self.root)
        self.assertIsNotNone(wrapper)
        assert wrapper is not None
        pair = self.session.first_child(wrapper)
        self.assertIsNotNone(pair)
        assert pair is not None
        tail = self.session.next_sibling(pair)
        self.assertIsNotNone(tail)
        assert tail is not None
        detached = self.session.remove_siblings(tail, 1)
        self.assertIsNotNone(detached)
        assert detached is not None
        self.session.insert_before(pair, detached)
        self.assertEqual(self.session.first_child(wrapper), tail)
        self.assertIsNone(self.session.next_sibling(pair))
        self.assertEqual(self.session.next_sibling(tail), pair)

    def test_remove_self_detaches_single_node(self) -> None:
        first = self.session.first_child(self.root)
        self.assertIsNotNone(first)
        assert first is not None
        head = self.session.remove_self(first)
        self.assertEqual(head, first)
        self.assertIsNone(self.session.parent(first))

    def test_insert_and_remove_children_at(self):
        original = self.session.child_count(self.root)
        head = self.session.clean_children(self.root)
        self.assertIsNotNone(head)
        assert head is not None
        self.session.insert_children_at(self.root, 0, head)
        self.assertEqual(self.session.child_count(self.root), original)
        removed = self.session.remove_children_at(self.root, 0, original)
        self.assertIsNotNone(removed)
        self.assertEqual(self.session.child_count(self.root), 0)

    def test_promote_and_unlink_wrapper(self) -> None:
        # Promote the document's only child over its wrapper: the
        # wrapper's children take its place among the root's children.
        # Note the underlying ABI leaves the promoted-over wrapper with a
        # readable former-parent pointer, so detachment is asserted via
        # active membership rather than parent().
        wrapper = self.session.first_child(self.root)
        self.assertIsNotNone(wrapper)
        assert wrapper is not None
        grandchildren_head = self.session.clean_children(wrapper)
        self.assertIsNotNone(grandchildren_head)
        assert grandchildren_head is not None
        self.session.append_children(wrapper, grandchildren_head)
        promoted = self.session.promote_children_over_wrapper(wrapper)
        self.assertIsNotNone(promoted)
        assert promoted is not None
        active: list[grammar.Node] = []
        child = self.session.first_child(self.root)
        while child is not None:
            active.append(child)
            child = self.session.next_sibling(child)
        self.assertNotIn(wrapper, active)
        self.assertIn(promoted, active)

    def test_unlink_wrapper_detaches_without_touching_children(self) -> None:
        # The ABI leaves the unlinked wrapper's former-parent pointer
        # readable, so detachment is asserted via active membership.
        wrapper = self.session.first_child(self.root)
        self.assertIsNotNone(wrapper)
        assert wrapper is not None
        children_before = self.session.child_count(wrapper)
        self.session.unlink_wrapper(wrapper)
        self.assertEqual(self.session.child_count(wrapper), children_before)
        self.assertNotEqual(self.session.first_child(self.root), wrapper)


class SymbolTableTests(unittest.TestCase):
    session: grammar.Session

    def setUp(self) -> None:
        self.session = grammar.Session()

    def tearDown(self) -> None:
        self.session.close()

    def test_symbol_and_variable_tables(self):
        self.assertGreater(grammar.symbol_count(), 0)
        self.assertGreater(grammar.variable_count(), 0)
        first_name = self.session.symbol_name_at(0)
        self.assertIsInstance(first_name, bytes)
        self.assertIsInstance(self.session.symbol_is_terminal(0), bool)
        variable_name = self.session.variable_name_at(0)
        self.assertIsInstance(variable_name, bytes)
        self.assertIsNone(self.session.symbol_name_at(10**9))
        self.assertIsNone(self.session.variable_name_at(10**9))


class ReservationTests(unittest.TestCase):
    def test_reserve_and_report_capacity(self):
        session = grammar.Session()
        try:
            capacity = session.node_capacity()
            session.reserve_nodes(capacity + 1024)
            self.assertGreaterEqual(session.node_capacity(), capacity + 1024)
        finally:
            session.close()


class LifetimeTests(unittest.TestCase):
    def test_close_is_idempotent_and_closed_sessions_raise(self):
        session = grammar.Session()
        session.parse("alpha:12")
        session.close()
        session.close()
        with self.assertRaises(ValueError):
            session.parse("alpha:12")
        with self.assertRaises(ValueError):
            session.root_node()

    def test_context_manager_closes_session(self):
        with grammar.Session() as session:
            self.assertGreater(session.parse("alpha:12"), 0)
        with self.assertRaises(ValueError):
            session.parse("alpha:12")

    def test_walker_step_after_session_close_raises(self):
        session = grammar.Session()
        session.parse("alpha:12")
        root = session.root_node()
        assert root is not None
        walker = session.walk(root)
        self.assertIsNotNone(next(walker))
        session.close()
        with self.assertRaises(ValueError):
            next(walker)
        with self.assertRaises(ValueError):
            walker.skip_children()
        walker.close()
        walker.close()

    def test_options_round_trip(self):
        session = grammar.Session(
            max_errors=3,
            recovery_window=100,
            stack_overflow_recovery=False,
            syntax_error_stack_depth=8,
            verbosity=0,
            ast_preallocation_ratio=2.0,
            ast_preallocation_cap=4096,
        )
        try:
            self.assertGreater(session.parse("alpha:12"), 0)
        finally:
            session.close()


def _package_files() -> list[str]:
    suffix = sysconfig.get_config_var("EXT_SUFFIX")
    return ["__init__.py", "__init__.pyi", f"galley_impl{suffix}"]


class LoaderTests(unittest.TestCase):
    """Contracts of the bare-file loader.

    Copies of the already-built fixture extension stand in for distinct
    grammars: same content, separate module objects — which is exactly
    what per-artifact isolation rests on. No rebuilds, no examples.
    Bare loads never scan: a `procedures.py` next to the file is
    ignored, and hooks arrive only through explicit installs.
    """

    def setUp(self) -> None:
        self.directory = Path(tempfile.mkdtemp(prefix="galley-loader-test-"))
        self.addCleanup(shutil.rmtree, self.directory, True)

    def _copy_impl(self, name: str | None = None) -> Path:
        suffix = sysconfig.get_config_var("EXT_SUFFIX")
        if name is None:
            target = self.directory / f"galley_impl_copy{suffix}"
        elif Path(name).suffix:
            target = self.directory / name
        else:
            target = self.directory / f"{name}{suffix}"
        shutil.copy2(_fixture_impl_file(), target)
        return target

    def test_missing_file_names_path_and_build(self) -> None:
        suffix = sysconfig.get_config_var("EXT_SUFFIX")
        missing = self.directory / f"no-such-grammar{suffix}"
        with self.assertRaises(galley.MissingArtifactError) as raised:
            galley.load(missing)
        self.assertIn(str(missing), str(raised.exception))
        self.assertIn("python -m galley", str(raised.exception))
        self.assertIsInstance(raised.exception, FileNotFoundError)
        self.assertEqual(raised.exception.code, "galley:missing-artifact")

    def test_same_path_returns_same_module(self) -> None:
        impl = self._copy_impl()
        first = galley.load(impl)
        second = galley.load(impl)
        self.assertIs(first, second)

    def test_two_files_hold_independent_tables(self) -> None:
        first = galley.load(self._copy_impl("first"))
        second = galley.load(self._copy_impl("second"))
        self.assertIsNot(first, second)

        calls: list[bool] = []

        def probe(args: Any) -> None:
            calls.append(True)

        first.install_procedure("reduction_Number", probe)
        try:
            self.assertIs(first.list_procedures()["reduction_Number"], probe)
            self.assertNotIn("reduction_Number", second.list_procedures())
            with first.Session() as session:
                session.parse("alpha:12")
            self.assertEqual(len(calls), 1)
            with second.Session() as session:
                session.parse("alpha:12")
            self.assertEqual(len(calls), 1)
        finally:
            first.clear_procedures()

    def test_bare_load_installs_nothing(self) -> None:
        package = self.directory / "hookless"
        package.mkdir(parents=True, exist_ok=True)
        suffix = sysconfig.get_config_var("EXT_SUFFIX")
        impl = package / f"galley_impl{suffix}"
        shutil.copy2(_fixture_impl_file(), impl)
        (package / "procedures.py").write_text(
            "seen: list[bytes] = []\n"
            "def reduction_Number(args) -> None:\n"
            "    node = args.current_node()\n"
            "    assert node is not None\n"
            "    text = node.text()\n"
            "    assert text is not None\n"
            "    seen.append(text)\n",
            encoding="utf-8",
        )
        module = galley.load(impl)
        self.assertFalse(hasattr(module, "procedures"))
        self.assertEqual(module.list_procedures(), {})
        with module.Session() as session:
            session.parse("alpha:12")
        self.assertEqual(module.list_procedures(), {})

    def test_manual_dict_install_fires(self) -> None:
        module = galley.load(self._copy_impl())
        fired: list[bytes] = []

        def reduction_Number(args: Any) -> None:
            node = args.current_node()
            assert node is not None
            text = node.text()
            assert text is not None
            fired.append(text)

        module.install_procedures({"reduction_Number": reduction_Number})
        try:
            self.assertIn("reduction_Number", module.list_procedures())
            with module.Session() as session:
                session.parse("alpha:12")
            self.assertEqual(fired, [b"12"])
        finally:
            module.clear_procedures()

    def test_near_miss_hook_names_warn(self) -> None:
        module = galley.load(self._copy_impl())

        def reductionPair(args: Any) -> None:
            pass

        try:
            with self.assertWarns(RuntimeWarning):
                installed = module.install_procedures({"reductionPair": reductionPair})
            self.assertEqual(installed, 0)
            self.assertNotIn("reductionPair", module.list_procedures())
        finally:
            module.clear_procedures()

    def test_failed_load_preserves_previous_entry(self) -> None:
        import importlib.machinery
        import importlib.util
        from unittest import mock

        first_path = self._copy_impl("first")
        first = galley.load(first_path)
        self.assertIs(sys.modules[galley._constants.IMPL_MODULE_NAME], first)

        marker = object()
        saved = sys.modules.get(galley._constants.IMPL_MODULE_NAME, marker)

        def restore_stem():
            if saved is marker:
                sys.modules.pop(galley._constants.IMPL_MODULE_NAME, None)
            else:
                sys.modules[galley._constants.IMPL_MODULE_NAME] = saved

        self.addCleanup(restore_stem)

        class _FailingLoader:
            def create_module(self, spec):
                return None

            def exec_module(self, module):
                raise ImportError("simulated exec failure")

        other = self.directory / "other.so"
        other.write_bytes(b"not an extension")

        def fake_factory(name, path):
            return importlib.machinery.ModuleSpec(
                name, _FailingLoader(), origin=str(path)
            )

        with (
            mock.patch.object(importlib.util, "spec_from_file_location", fake_factory),
            self.assertRaises(ImportError),
        ):
            galley.load(other)
        self.assertIs(sys.modules[galley._constants.IMPL_MODULE_NAME], first)
        self.assertNotIn(str(other.resolve()), galley._artifact_cache)

    def _copy_package(self, target: Path) -> Path:
        target.mkdir(parents=True, exist_ok=True)
        for name in _package_files():
            shutil.copy2(FIXTURE_DIRECTORY / name, target / name)
        return target

    def _write_procedures(self, package: Path, body: str) -> None:
        (package / "procedures.py").write_text(body, encoding="utf-8")

    def test_direct_import_wires_bundled_hooks(self) -> None:
        # No loader: an identifier-named copy imports as an ordinary
        # package, hooks bundled.
        package = self.directory / "directlang"
        self._copy_package(package)
        self._write_procedures(
            package,
            "seen: list[bytes] = []\n"
            "def reduction_Number(args) -> None:\n"
            "    node = args.current_node()\n"
            "    assert node is not None\n"
            "    text = node.text()\n"
            "    assert text is not None\n"
            "    seen.append(text)\n",
        )
        sys.path.insert(0, str(self.directory))
        self.addCleanup(sys.path.remove, str(self.directory))
        for key in (
            "directlang",
            "directlang.procedures",
            "directlang.galley_impl",
        ):
            self.addCleanup(sys.modules.pop, key, None)
        import directlang  # noqa: E402

        with directlang.Session() as session:
            session.parse("alpha:12")
        from directlang import procedures as namespace

        self.assertEqual(namespace.seen, [b"12"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
