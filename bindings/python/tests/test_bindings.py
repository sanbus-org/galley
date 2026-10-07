"""Behavioral tests for the Galley Python bindings.

The suite imports the built fixture package directly (built on demand,
never examples/):

    GALLEY_CHECKOUT=$PWD python -m galley bindings/python/test_fixture
    GALLEY_CHECKOUT=$PWD python -m galley bindings/python/test_fixture_second
    PYTHONPATH=bindings/python python3 bindings/python/tests/test_bindings.py

The second fixture (the second shared grammar) is the other parser of the
concurrency tests.
"""

from __future__ import annotations

import gc
import operator
import os
import shutil
import subprocess
import sys
import sysconfig
import tempfile
import threading
import unittest
import warnings
import weakref
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

    The module's default hooks outlive every session, so a test that
    installs or clears them must not leak into the next one: snapshot in
    setUp, restore here.
    """
    grammar.clear_procedures()
    if saved:
        grammar.install_procedures(saved)


class ParserSurfaceTests(unittest.TestCase):
    def test_node_snapshot_and_walk_step_cannot_be_constructed(self):
        # Creation happens only inside the extension (the session's read
        # paths and the walker); the types expose no constructor.
        with self.assertRaises(TypeError):
            grammar.Node()
        with self.assertRaises(TypeError):
            grammar.Snapshot()
        with self.assertRaises(TypeError):
            grammar.WalkStep()

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

    def test_stub_walk_return_is_walker(self):
        # Runtime always returns a Walker (the cursor lives host-side, never
        # None); the stub must spell the same non-optional `Walker` on Node.
        import ast
        import pathlib

        stub_path = pathlib.Path(grammar.__file__).parent / "__init__.pyi"
        tree = ast.parse(stub_path.read_text(encoding="utf-8"))
        node_class = next(
            node
            for node in tree.body
            if isinstance(node, ast.ClassDef) and node.name == "Node"
        )
        walk = next(
            node
            for node in node_class.body
            if isinstance(node, ast.FunctionDef) and node.name == "walk"
        )
        assert walk.returns is not None
        self.assertEqual(ast.unparse(walk.returns), "Walker")

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

    def assert_nothing_published(self, session: grammar.Session) -> None:
        # Root is the one "nothing here" probe and answers None; every other
        # session-door read, the input and the position included, refuses.
        # No call answers 0, empty or None for a refusal.
        self.assertIsNone(session.root_node())
        for read in (
            session.node_count,
            session.snapshot,
            session.last_input,
            session.last_position,
        ):
            with self.assertRaises(grammar.StaleTreeError):
                read()

    def test_nothing_published_refuses_instead_of_answering(self) -> None:
        # Before any parse there is no tree.
        self.assert_nothing_published(self.session)
        # And after a failed parse that publishes nothing: one error is the
        # limit, so the parser raises instead of recovering.
        strict = grammar.Session(max_errors=1)
        try:
            strict.parse("alpha:12")
            self.assertEqual(strict.last_input(), b"alpha:12")
            with self.assertRaises(grammar.GalleyError):
                strict.parse("alpha:")
            self.assert_nothing_published(strict)
        finally:
            strict.close()

    def test_use_after_close_is_not_a_stale_tree(self) -> None:
        # A closed session has its own error: the stale-tree error means the
        # tree is gone, not that the session is.
        self.session.parse("alpha:12,beta:3")
        root = self.session.root_node()
        assert root is not None
        self.session.close()
        for probe in (root.text, self.session.node_count, self.session.root_node):
            with self.assertRaises(ValueError) as closed:
                probe()
            self.assertNotIsInstance(closed.exception, grammar.StaleTreeError)

    def test_finished_parse_queries_are_refused_inside_a_hook(self) -> None:
        # Inside a hook (this thread, this session) nothing that describes a
        # finished parse answers: not before the first parse publishes, not
        # with a tree published, never 0 or empty. `session in use` comes
        # first, and it is not a stale tree.
        codes: list[tuple[str, int]] = []

        def probe(args: grammar.ProcedureArguments) -> None:
            for name in (
                "node_capacity",
                "node_count",
                "snapshot",
                "last_input",
                "last_position",
                "root_node",
            ):
                try:
                    getattr(self.session, name)()
                    codes.append((name, 0))
                except grammar.GalleyError as error:
                    codes.append((name, error.code))
                    self.assertNotIsInstance(error, grammar.StaleTreeError)

        names = [
            "node_capacity", "node_count", "snapshot", "last_input",
            "last_position", "root_node",
        ]
        refused = [(name, grammar.Status.ERROR_SESSION_IN_USE) for name in names]
        for attempt in range(2):  # nothing published, then a tree published
            codes.clear()
            self.session.install_procedure("reduction_Document", probe)
            try:
                self.session.parse("alpha:12,beta:3")
            finally:
                self.session.clear_procedures()
            self.assertEqual(codes, refused, f"attempt {attempt}")

    def test_node_capacity_is_refused_while_another_thread_parses(self) -> None:
        entered = threading.Event()
        release = threading.Event()
        outcome: list[int] = []

        def block(args: grammar.ProcedureArguments) -> None:
            entered.set()
            self.assertTrue(release.wait(30))

        self.session.install_procedure("reduction_Document", block)
        thread = threading.Thread(target=lambda: self.session.parse("alpha:12,beta:3"))
        thread.start()
        try:
            self.assertTrue(entered.wait(30))
            for read in (self.session.node_capacity, self.session.node_count,
                         self.session.snapshot, self.session.last_input,
                         self.session.last_position):
                with self.assertRaises(grammar.GalleyError) as refusal:
                    read()
                outcome.append(refusal.exception.code)
        finally:
            release.set()
            thread.join(30)
            self.session.clear_procedures()
        self.assertEqual(outcome, [grammar.Status.ERROR_SESSION_IN_USE] * 5)

    def test_procedure_hook_can_read_node_text(self) -> None:
        seen: list[bytes] = []

        def reduction_Pair(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            self.assertIsNotNone(node)
            assert node is not None
            text = node.text()
            self.assertIsInstance(text, bytes)
            assert text is not None
            self.assertGreater(len(text), 0)
            seen.append(text)

        self.session.install_procedure("reduction_Pair", reduction_Pair)
        try:
            self.session.parse("alpha:12,beta:3")
        finally:
            self.session.clear_procedures()
        self.assertEqual(len(seen), 2)

    def test_hook_nodes_outlive_their_hook_and_their_parse(self) -> None:
        # The tree belongs to the parse, not to the hook that handed out a
        # node: a node stashed by one hook stays usable from a later hook
        # of the same parse, after the parse succeeds, and refuses only
        # once the session parses again.
        stashed: list[grammar.Node] = []
        seen: list[bytes | None] = []

        def stash_first_pair(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            assert node is not None
            if not stashed:
                stashed.append(node)

        def use_in_document(args: grammar.ProcedureArguments) -> None:
            seen.append(stashed[0].text())

        self.session.install_procedure("reduction_Pair", stash_first_pair)
        self.session.install_procedure("reduction_Document", use_in_document)
        try:
            self.session.parse("alpha:12,beta:3")
        finally:
            self.session.clear_procedures()
        self.assertEqual(seen, [b"alpha:12"])
        self.assertEqual(stashed[0].text(), b"alpha:12")
        self.session.parse("gamma:7")
        with self.assertRaises(grammar.StaleTreeError):
            stashed[0].text()

    def test_procedure_arguments_die_with_their_hook(self) -> None:
        # The arguments carry per-hook state (current node, position, the
        # drop and replace channel). The core refuses every call made with
        # a hook that has returned: from a later hook of the same parse and
        # after the parse alike, on every accessor and with no expiry flag
        # in the binding.
        stashed: list[grammar.ProcedureArguments] = []
        during: list[tuple[str, int]] = []
        later: list[grammar.ProcedureArguments] = []

        def stash_pair(args: grammar.ProcedureArguments) -> None:
            if not stashed:
                stashed.append(args)

        def uses(args: grammar.ProcedureArguments, node: Any = None) -> list[Any]:
            return [
                args.current_line,
                args.current_column,
                args.current_node,
                args.drop_self,
                args.drop_children,
                args.drop_if_empty,
                args.replace_with_children,
                lambda: args.report_semantic_error("late"),
                lambda: args.set_current_node(node),
            ]

        def use_in_document(args: grammar.ProcedureArguments) -> None:
            later.append(args)
            for use in uses(stashed[0], args.current_node()):
                try:
                    use()
                except grammar.GalleyError as error:
                    during.append((type(error).__name__, error.code))

        self.session.install_procedure("reduction_Pair", stash_pair)
        self.session.install_procedure("reduction_Document", use_in_document)
        try:
            self.session.parse("alpha:12,beta:3")
        finally:
            self.session.clear_procedures()
        calls = len(uses(stashed[0]))
        # Every call refused, none as a stale tree, and the later hook's own
        # arguments were served the whole time (the parse succeeded).
        self.assertEqual(during, [("GalleyError", grammar.Status.ERROR_STALE_HOOK)] * calls)
        # After the parse the same arguments, and the last hook's, still refuse.
        root = self.session.root_node()
        assert root is not None
        for args in (stashed[0], later[0]):
            for use in uses(args, root):
                with self.assertRaises(grammar.GalleyError) as refusal:
                    use()
                self.assertEqual(refusal.exception.code, grammar.Status.ERROR_STALE_HOOK)
                self.assertNotIsInstance(refusal.exception, grammar.StaleTreeError)
        self.assertEqual(root.text(), b"alpha:12,beta:3")

    def test_live_arguments_are_refused_on_any_thread_but_the_hooks(self) -> None:
        # A hook's arguments live on the dispatching thread's stack: while the
        # hook runs, every other thread is refused with `session in use` before
        # anything is read, and nothing is changed.
        entered = threading.Event()
        probed = threading.Event()
        codes: list[int] = []

        def reduction_Document(args: grammar.ProcedureArguments) -> None:
            def probe() -> None:
                for use in (
                    args.current_line,
                    args.current_node,
                    args.drop_self,
                    lambda: args.report_semantic_error("late"),
                ):
                    try:
                        use()
                    except grammar.GalleyError as error:
                        codes.append(error.code)
                probed.set()

            thread = threading.Thread(target=probe)
            thread.start()
            thread.join(30)
            entered.set()
            # Same thread, still live: served.
            args.current_line()

        self.session.install_procedure("reduction_Document", reduction_Document)
        try:
            self.session.parse("alpha:12,beta:3")
        finally:
            self.session.clear_procedures()
        self.assertTrue(probed.is_set())
        self.assertEqual(codes, [grammar.Status.ERROR_SESSION_IN_USE] * 4)
        self.assertEqual(self.session.root_node().text(), b"alpha:12,beta:3")

    def test_a_refused_call_with_returned_arguments_changes_nothing(self) -> None:
        # drop_self through the first Pair's arguments, made from a later
        # Pair hook, is refused and so cannot drop that later hook's node.
        stashed: list[grammar.ProcedureArguments] = []
        refusals: list[int] = []

        def reduction_Pair(args: grammar.ProcedureArguments) -> None:
            if not stashed:
                stashed.append(args)
                return
            try:
                stashed[0].drop_self()
            except grammar.GalleyError as error:
                refusals.append(error.code)

        self.session.install_procedure("reduction_Pair", reduction_Pair)
        try:
            self.session.parse("alpha:12,beta:3")
        finally:
            self.session.clear_procedures()
        self.assertEqual(refusals, [grammar.Status.ERROR_STALE_HOOK])
        root = self.session.root_node()
        assert root is not None
        pairs = [
            step.node
            for step in root.walk()
            if step.node.symbol_name() == b"Pair"
        ]
        self.assertEqual([pair.text() for pair in pairs], [b"alpha:12", b"beta:3"])

    def test_nested_parse_of_another_session_uses_its_own_hooks(self) -> None:
        # A hook that parses on another session: that session runs with its
        # own hooks, and neither parse sees or disturbs the other's.
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
                with grammar.Session() as inner_session:
                    inner_session.install_procedure("reduction_Number", inner_number)
                    inner_session.parse("alpha:9")

        def inner_number(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            assert node is not None
            text = node.text()
            assert text is not None
            inner_seen.append(text)

        self.session.install_procedure("reduction_Pair", outer_pair)
        try:
            self.session.parse("alpha:12,beta:3")
        finally:
            self.session.clear_procedures()
        self.assertEqual(outer_seen, [b"alpha:12", b"beta:3"])
        self.assertEqual(inner_seen, [b"9"])

    def test_changing_hooks_during_a_parse_is_refused(self) -> None:
        # The hooks a parse runs with are fixed for that parse: a change
        # from inside a hook raises, leaves the hooks as they were, and
        # the enclosing parse keeps firing all of its hooks.
        seen: list[bytes] = []
        refusals: list[int] = []

        def outer_pair(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            assert node is not None
            text = node.text()
            assert text is not None
            seen.append(text)
            for change in (
                self.session.clear_procedures,
                lambda: self.session.install_procedure("reduction_Number", outer_pair),
            ):
                try:
                    change()
                except grammar.GalleyError as error:
                    refusals.append(error.code)

        self.session.install_procedure("reduction_Pair", outer_pair)
        before = self.session.list_procedures()
        try:
            self.session.parse("alpha:12,beta:3")
            self.assertEqual(self.session.list_procedures(), before)
            self.assertIs(self.session.procedure_hook("reduction_Pair"), outer_pair)
        finally:
            self.session.clear_procedures()
        self.assertEqual(seen, [b"alpha:12", b"beta:3"])
        self.assertEqual(refusals, [grammar.Status.ERROR_SESSION_IN_USE] * 4)

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
        self.assertEqual(diagnostic.context[-1], b"Number")
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

    def test_file_parsing_rejects_interior_nul(self):
        # Paths cross into native code NUL-terminated: an interior NUL
        # is a loud ValueError, never a silent truncation.
        with self.assertRaises(ValueError):
            self.session.parse_file("/tmp/galley-python-bindings-test.kv\0")
        with self.assertRaises(ValueError):
            self.session.parse_file(b"/tmp/galley-python-bindings-test.kv\0")


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

        self.session.install_procedure("reduction_Number", reduction_Number)
        try:
            with self.assertRaises(grammar.GalleyError) as raised:
                self.session.parse("alpha:12,beta:300,gamma:400")
        finally:
            self.session.clear_procedures()
        self.assertEqual(raised.exception.code, grammar.Status.ERROR_SEMANTIC)
        self.assertIn("value out of range", str(raised.exception))
        self.assertEqual(seen_counts, [1, 2])
        diagnostic = self.session.diagnostic()
        self.assertIsNotNone(diagnostic)
        assert diagnostic is not None
        self.assertEqual(diagnostic.kind, grammar.Kind.SEMANTIC)
        self.assertEqual(diagnostic.line, 1)
        self.assertEqual(diagnostic.semantic_error_count, 2)
        self.assertEqual(diagnostic.semantic, (b"Number", "value out of range"))
        self.assertIn("SemanticError", diagnostic.message)
        recorded = self.session.diagnostics()
        self.assertEqual(len(recorded), 2)
        self.assertTrue(all(item.kind == grammar.Kind.SEMANTIC for item in recorded))
        self.assertTrue(
            all(item.semantic == (b"Number", "value out of range") for item in recorded)
        )

    def test_counts_reset_after_successful_parse(self) -> None:
        def reduction_Number(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            assert node is not None
            text = node.text()
            assert text is not None
            if int(text) > 99:
                args.report_semantic_error("value out of range")

        self.session.install_procedure("reduction_Number", reduction_Number)
        try:
            with self.assertRaises(grammar.GalleyError):
                self.session.parse("alpha:300")
            self.session.parse("alpha:12")
            self.assertFalse(self.session.has_diagnostic())
            self.assertIsNone(self.session.diagnostic())
            self.assertEqual(len(self.session.diagnostics()), 0)
        finally:
            self.session.clear_procedures()


class HookDispatchTests(unittest.TestCase):
    session: grammar.Session
    saved_procedures: dict[str, Any]

    def setUp(self) -> None:
        self.session = grammar.Session(max_errors=10)
        self.saved_procedures = grammar.list_procedures()

    def tearDown(self) -> None:
        self.session.close()
        _restore_procedures(self.saved_procedures)

    def test_raising_hook_aborts_the_parse_and_publishes_nothing(self) -> None:
        # A hook that raises stops the parse at that hook: parse raises the
        # binding's failure with the hook's own exception as its cause, the
        # failure carries the status and the snapshot of where the parse
        # stopped, and the parse publishes nothing.
        fired: list[grammar.Node] = []
        failure = ValueError("hook body failure")

        def reduction_Number(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            assert node is not None
            fired.append(node)
            raise failure

        self.session.parse("alpha:12,beta:3")
        earlier = self.session.root_node()
        assert earlier is not None
        self.session.install_procedure("reduction_Number", reduction_Number)
        with self.assertRaises(grammar.GalleyError) as raised:
            self.session.parse("alpha:12,beta:3")
        self.assertEqual(len(fired), 1)
        self.assertIs(raised.exception.__cause__, failure)
        self.assertEqual(raised.exception.code, grammar.Status.ERROR_HOOK_FAILED)
        diagnostic = raised.exception.diagnostic
        assert diagnostic is not None
        self.assertEqual(diagnostic.kind, grammar.Kind.HOOK)
        self.assertGreaterEqual(diagnostic.line, 1)
        self.assertGreaterEqual(diagnostic.column, 1)
        self.assertIn("reduction_Number", str(raised.exception))
        self.assertIsNone(self.session.root_node())
        with self.assertRaises(grammar.StaleTreeError):
            self.session.node_count()
        with self.assertRaises(grammar.StaleTreeError):
            fired[0].text()
        with self.assertRaises(grammar.StaleTreeError):
            earlier.text()

    def test_hook_failure_after_a_recovered_syntax_error_reports_the_hook(self) -> None:
        # The message belongs to the failure's own diagnostic: the syntax
        # error the parser recovered from earlier must not speak for it.
        def reduction_Document(args: grammar.ProcedureArguments) -> None:
            raise ValueError("late failure")

        self.session.install_procedure("reduction_Document", reduction_Document)
        with self.assertRaises(grammar.GalleyError) as raised:
            self.session.parse("alpha:12,beta@3")
        self.assertEqual(raised.exception.code, grammar.Status.ERROR_HOOK_FAILED)
        diagnostic = raised.exception.diagnostic
        assert diagnostic is not None
        self.assertEqual(diagnostic.kind, grammar.Kind.HOOK)
        self.assertIn("HookError", str(raised.exception))
        assert diagnostic.message is not None and diagnostic.message_ansi is not None
        self.assertIn("HookError", diagnostic.message)
        self.assertNotIn("SyntaxError", diagnostic.message)
        import re

        self.assertEqual(
            re.sub(r"\x1b\[[0-9;]*m", "", diagnostic.message_ansi), diagnostic.message
        )

    def test_session_is_reusable_after_a_hook_aborted_the_parse(self) -> None:
        calls: list[int] = []

        def reduction_Number(args: grammar.ProcedureArguments) -> None:
            calls.append(1)
            if len(calls) == 1:
                raise RuntimeError("first parse only")

        self.session.install_procedure("reduction_Number", reduction_Number)
        with self.assertRaises(grammar.GalleyError) as raised:
            self.session.parse("alpha:12,beta:3")
        self.assertIsInstance(raised.exception.__cause__, RuntimeError)
        self.assertEqual(self.session.parse("alpha:12,beta:3"), 15)
        self.assertEqual(len(calls), 3)
        root = self.session.root_node()
        assert root is not None
        self.assertEqual(root.text(), b"alpha:12,beta:3")
        self.assertIsNone(self.session.diagnostic())

    def test_hook_failure_does_not_leak_across_nested_sessions(self) -> None:
        # A hook parses on another session whose own hook raises: that
        # parse fails with that exception as its cause, the outer hook
        # handles it, and the outer parse completes untouched.
        inner_failure = KeyError("inner hook")
        inner_errors: list[grammar.GalleyError] = []
        outer_seen: list[bytes] = []
        nested = False

        def inner_number(args: grammar.ProcedureArguments) -> None:
            raise inner_failure

        def outer_pair(args: grammar.ProcedureArguments) -> None:
            nonlocal nested
            node = args.current_node()
            assert node is not None
            text = node.text()
            assert text is not None
            outer_seen.append(text)
            if not nested:
                nested = True
                with grammar.Session() as inner_session:
                    inner_session.install_procedure("reduction_Number", inner_number)
                    try:
                        inner_session.parse("alpha:9")
                    except grammar.GalleyError as error:
                        inner_errors.append(error)

        self.session.install_procedure("reduction_Pair", outer_pair)
        self.assertEqual(self.session.parse("alpha:12,beta:3"), 15)
        self.assertEqual(outer_seen, [b"alpha:12", b"beta:3"])
        self.assertEqual(len(inner_errors), 1)
        self.assertIs(inner_errors[0].__cause__, inner_failure)
        self.assertIsNotNone(self.session.root_node())

    def test_body_type_error_is_not_retried_without_args(self) -> None:
        # A TypeError from inside the hook body aborts the parse as-is: no
        # silent retry with no arguments, no second invocation.
        calls: list[bool] = []
        failure = TypeError("body boom")

        def reduction_Number(args: Any = None) -> None:
            calls.append(args is None)
            raise failure

        self.session.install_procedure("reduction_Number", reduction_Number)
        with self.assertRaises(grammar.GalleyError) as raised:
            self.session.parse("alpha:12,beta:3")
        self.assertIs(raised.exception.__cause__, failure)
        self.assertEqual(calls, [False])

    def test_zero_arg_hook_fires_once_per_reduction(self) -> None:
        # Hooks taking no arguments stay compatible: called empty, once
        # per reduction.
        fired: list[bool] = []

        def reduction_Pair() -> None:
            fired.append(True)

        self.session.install_procedure("reduction_Pair", reduction_Pair)
        try:
            self.assertEqual(self.session.parse("alpha:12,beta:3"), 15)
        finally:
            self.session.clear_procedures()
        self.assertEqual(len(fired), 2)


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
            args.set_current_node(node)
            current = args.current_node()
            assert current is not None
            self.assertEqual(current, node)
            # Tree edits during a parse cross the hook door: the session
            # door refuses while the parse holds the session.
            head = current.clean_children()
            assert head is not None
            detached.append(head.address)
            current.append_children(head)

        self.session.install_procedure("reduction_Pair", reduction_Pair)
        try:
            self.assertEqual(self.session.parse("alpha:12,beta:3"), 15)
        finally:
            self.session.clear_procedures()
        self.assertEqual(len(detached), 2)

    def test_set_current_node_refuses_a_raw_address(self) -> None:
        refusals: list[BaseException] = []

        def reduction_Pair(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            assert node is not None
            try:
                args.set_current_node(node.address)
            except BaseException as error:
                refusals.append(error)

        self.session.install_procedure("reduction_Pair", reduction_Pair)
        try:
            self.session.parse("alpha:12,beta:3")
        finally:
            self.session.clear_procedures()
        self.assertGreater(len(refusals), 0)
        for error in refusals:
            self.assertIsInstance(error, TypeError)


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
        # No validity probe: a real read is the answer, and it reads.
        self.assertGreater(self.session.child_count(root), 0)
        self.assertIsNone(self.session.parent(root))
        with self.assertRaisesRegex(TypeError, "expected a Node"):
            self.session.parent(grammar.INVALID_NODE)

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

    def test_address_is_display_only(self) -> None:
        root = self.session.root_node()
        assert root is not None
        again = self.session.root_node()
        assert again is not None
        self.assertEqual(again.address, root.address)
        self.assertEqual(again, root)
        # The address never converts back into something a call accepts:
        # neither int()/operator.index() nor the raw address itself.
        with self.assertRaises(TypeError):
            int(root)
        with self.assertRaises(TypeError):
            operator.index(root)
        with self.assertRaisesRegex(TypeError, "expected a Node"):
            self.session.child_count(root.address)

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

    def test_accessors_refuse_raw_addresses(self) -> None:
        # A raw address carries no generation, so an accessor that takes a
        # node refuses it instead of reading whichever node happens to
        # hold that index.
        root = self.session.root_node()
        self.assertIsNotNone(root)
        assert root is not None
        for address in (grammar.INVALID_NODE, root.address):
            for call in (
                self.session.symbol_name,
                self.session.text,
                self.session.span,
                self.session.line_column,
                self.session.variable_index,
                self.session.child_count,
            ):
                with self.assertRaisesRegex(TypeError, "expected a Node"):
                    call(address)

    def test_walk_matches_hand_rolled_recursion(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        root = self.session.root_node()
        self.assertIsNotNone(root)
        assert root is not None

        def recurse(node: grammar.Node, depth: int, out: list[tuple[int, int]]) -> None:
            out.append((node.address, depth))
            child = self.session.first_child(node)
            while child is not None:
                recurse(child, depth + 1, out)
                child = self.session.next_sibling(child)

        expected: list[tuple[int, int]] = []
        recurse(root, 0, expected)
        self.assertGreater(len(expected), 1)

        walked = [(step.node.address, step.depth) for step in root.walk()]
        self.assertEqual(expected, walked)
        first = next(iter(root.walk()))
        self.assertEqual(first.node, root)
        self.assertEqual(first.depth, 0)
        self.assertFalse(first.is_semantic_error)

    def test_walk_from_a_non_root_node_yields_its_subtree_with_relative_depths(
        self,
    ) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        root = self.session.root_node()
        assert root is not None
        pair_list = self.session.first_child(root)
        assert pair_list is not None
        pair = self.session.first_child(pair_list)
        assert pair is not None
        self.assertNotEqual(pair, root)

        def recurse(node: grammar.Node, depth: int, out: list[tuple[int, int]]) -> None:
            out.append((node.address, depth))
            for child in node.children():
                recurse(child, depth + 1, out)

        expected: list[tuple[int, int]] = []
        recurse(pair, 0, expected)
        walked = [(step.node.address, step.depth) for step in pair.walk()]
        self.assertEqual(walked, expected)
        self.assertEqual(walked[0], (pair.address, 0))
        # A strict subtree: the full walk from the root visits more.
        self.assertLess(len(walked), len(list(root.walk())))

    def test_session_has_no_walk(self) -> None:
        self.assertFalse(hasattr(grammar.Session, "walk"))
        self.assertFalse(hasattr(self.session, "walk"))
        root = self.session.root_node()
        assert root is not None
        self.assertTrue(hasattr(root, "walk"))

    def test_walk_step_is_read_only_and_cannot_be_constructed(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        root = self.session.root_node()
        assert root is not None
        step = next(iter(root.walk()))
        self.assertIsInstance(step, grammar.WalkStep)
        for name in ("node", "depth", "is_semantic_error"):
            with self.assertRaises(AttributeError):
                setattr(step, name, None)
        with self.assertRaises(AttributeError):
            step.extra = 1  # type: ignore[attr-defined]
        with self.assertRaises(TypeError):
            step["node"]  # type: ignore[index]
        with self.assertRaises(TypeError):
            grammar.WalkStep()  # type: ignore[call-arg]

    def test_snapshot_matches_per_node_accessors(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        snap = self.session.snapshot()
        count = self.session.node_count()
        self.assertEqual(snap.count, count)
        self.assertGreater(count, 0)
        for name in (
            "parent",
            "first_child",
            "next",
            "child_count",
            "variable",
            "span_start",
            "span_len",
            "is_semantic_error",
        ):
            self.assertEqual(len(getattr(snap, name)), count)
        for address in range(count):
            node = snap.node(address)
            self.assertIsNotNone(node)
            assert node is not None
            parent = self.session.parent(node)
            self.assertEqual(
                snap.parent[address], None if parent is None else parent.address
            )
            first = self.session.first_child(node)
            self.assertEqual(
                snap.first_child[address],
                None if first is None else first.address,
            )
            nxt = self.session.next_sibling(node)
            self.assertEqual(snap.next[address], None if nxt is None else nxt.address)
            self.assertEqual(snap.child_count[address], self.session.child_count(node))
            self.assertEqual(snap.variable[address], self.session.variable_index(node))
            self.assertEqual(
                (snap.span_start[address], snap.span_len[address]),
                self.session.span(node),
            )
        # Spans index last_input.
        data = self.session.last_input()
        self.assertEqual(data, b"alpha:12,beta:3")
        for address in range(count):
            start = snap.span_start[address]
            length = snap.span_len[address]
            assert isinstance(start, int) and isinstance(length, int)
            node = snap.node(address)
            assert node is not None
            text = self.session.text(node)
            assert text is not None
            self.assertEqual(data[start : start + length], text)
        # The snapshot alone drives the same preorder walk as the walker.
        root = self.session.root_node()
        assert root is not None
        preorder: list[int] = []
        stack = [root.address]
        while stack:
            address = stack.pop()
            preorder.append(address)
            child = snap.first_child[address]
            chain: list[int] = []
            while child is not None:
                chain.append(child)
                child = snap.next[child]
            self.assertEqual(len(chain), snap.child_count[address])
            stack.extend(reversed(chain))
        walked = [step.node.address for step in root.walk()]
        self.assertEqual(preorder, walked)

    def test_snapshot_node_round_trips_columns_and_accessors(self) -> None:
        snap = self.session.snapshot()
        root = self.session.root_node()
        self.assertIsNotNone(root)
        assert root is not None
        node = snap.node(root.address)
        self.assertEqual(node, root)
        first = self.session.first_child(node)
        self.assertIsNotNone(first)
        assert first is not None
        self.assertEqual(snap.first_child[node.address], first.address)
        self.assertEqual(snap.node(first.address), first)
        # An absent node link answers None, never a node.
        self.assertIsNone(snap.node(grammar.INVALID_NODE))
        # Every address and the sentinel are non-negative: only statuses are
        # negative in the ABI, so the sentinel is the largest signed 64-bit value.
        self.assertEqual(grammar.INVALID_NODE, 2**63 - 1)
        # A node without a variable reads None in the column and the accessor.
        self.assertIn(None, snap.variable)
        for address, variable in enumerate(snap.variable):
            self.assertEqual(variable, self.session.variable_index(snap.node(address)))

    def test_snapshot_node_out_of_range_raises(self) -> None:
        snap = self.session.snapshot()
        self.assertGreater(snap.count, 0)
        with self.assertRaises(IndexError):
            snap.node(snap.count)
        with self.assertRaises(IndexError):
            snap.node(-1)

    def test_snapshot_node_rejects_bool(self) -> None:
        # bool subclasses int, but True/False are not node addresses.
        snap = self.session.snapshot()
        for flag in (True, False):
            with self.assertRaises(TypeError):
                snap.node(flag)

    def test_snapshot_is_stale_after_a_reparse(self) -> None:
        root = self.session.root_node()
        self.assertIsNotNone(root)
        assert root is not None
        snap = self.session.snapshot()
        stale = snap.node(root.address)
        self.assertIsNotNone(stale)
        assert stale is not None
        self.session.parse("alpha:12")
        fresh = self.session.root_node()
        self.assertIsNotNone(fresh)
        assert fresh is not None
        # The columns never follow a later parse: node() keeps answering
        # for its own parse, and that node reads as a stale tree.
        self.assertEqual(snap.node(root.address), stale)
        self.assertNotEqual(stale, fresh)
        with self.assertRaises(grammar.StaleTreeError):
            stale.text()
        self.assertEqual(fresh.text(), b"alpha:12")

    def test_a_stale_snapshot_node_is_stale_after_a_failed_parse_too(self) -> None:
        root = self.session.root_node()
        assert root is not None
        stale = self.session.snapshot().node(root.address)
        assert stale is not None
        with self.assertRaises(grammar.GalleyError):
            self.session.parse("alpha:")
        with self.assertRaises(grammar.StaleTreeError):
            stale.text()

    def test_walk_skip_children_prunes_subtree(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        root = self.session.root_node()
        assert root is not None
        walker = root.walk()
        first = next(walker)
        self.assertEqual(first.node, root)
        walker.skip_children()
        self.assertEqual(list(walker), [])

    def test_walk_stale_root_raises(self) -> None:
        # A Node root from a previous parse generation is stale: the walk is
        # bound to that parse, so its first step refuses loudly instead of
        # reading reallocated storage. (A raw address never reaches the walk
        # at all.)
        root = self.session.root_node()
        assert root is not None
        self.session.parse("alpha:12,beta:3")
        with self.assertRaises(grammar.StaleTreeError):
            next(root.walk())

    def test_walker_step_after_reparse_raises(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        root = self.session.root_node()
        assert root is not None
        walker = root.walk()
        self.assertIsNotNone(next(walker))
        self.assertEqual(self.session.parse("alpha:12,beta:3"), 15)
        with self.assertRaises(grammar.StaleTreeError):
            next(walker)

    def test_skipping_children_on_a_stale_walker_waits_for_the_next_step(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        root = self.session.root_node()
        assert root is not None
        walker = root.walk()
        self.assertIsNotNone(next(walker))
        self.assertEqual(self.session.parse("alpha:12,beta:3"), 15)
        # skip_children is a pure host-side state write: staleness is the
        # next step's answer, not this one's.
        walker.skip_children()
        with self.assertRaises(grammar.StaleTreeError):
            next(walker)

    def test_parse_with_abandoned_walker_succeeds(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        root = self.session.root_node()
        assert root is not None
        walker = root.walk()
        # Parsing never raises merely because a walker is open; the
        # abandoned walker fails at its next step instead.
        self.assertEqual(self.session.parse("alpha:12,beta:3"), 15)
        with self.assertRaises(grammar.StaleTreeError):
            next(walker)
        fresh = self.session.root_node()
        assert fresh is not None
        self.assertGreater(len(list(fresh.walk())), 1)

    def test_failed_parse_invalidates_walkers(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        root = self.session.root_node()
        assert root is not None
        walker = root.walk()
        self.assertIsNotNone(next(walker))
        with self.assertRaises(grammar.GalleyError):
            self.session.parse("alpha:")
        with self.assertRaises(grammar.StaleTreeError):
            next(walker)

    def test_walker_step_during_a_parse_reports_in_use(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        # The parse holds the session exclusively: a step from another
        # thread mid-parse is refused as in use, never a silent stop.
        root = self.session.root_node()
        assert root is not None
        walker = root.walk()
        self.assertIsNotNone(next(walker))
        first_hook_done = threading.Event()
        probes_done = threading.Event()
        codes: list[int] = []

        def reduction_Pair(args: grammar.ProcedureArguments) -> None:
            if not first_hook_done.is_set():
                first_hook_done.set()
                self.assertTrue(probes_done.wait(30))

        self.session.install_procedure("reduction_Pair", reduction_Pair)
        thread = threading.Thread(target=lambda: self.session.parse("alpha:12,beta:3"))
        thread.start()
        try:
            self.assertTrue(first_hook_done.wait(30))
            with self.assertRaises(grammar.GalleyError) as refusal:
                next(walker)
            codes.append(refusal.exception.code)
        finally:
            probes_done.set()
            thread.join(30)
        self.session.clear_procedures()
        self.assertEqual(codes, [grammar.Status.ERROR_SESSION_IN_USE])

    def test_walk_step_after_removing_current_node_raises(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        root = self.session.root_node()
        assert root is not None
        walker = root.walk()
        leaf: grammar.Node | None = None
        for step in walker:
            if step.depth >= 1 and len(step.node) == 0:
                leaf = step.node
                break
        self.assertIsNotNone(leaf)
        assert leaf is not None
        self.session.remove_self(leaf)
        # The step has no live position to advance from: invalid node, and
        # the cursor never moves past the failure.
        with self.assertRaisesRegex(grammar.GalleyError, "invalid node"):
            next(walker)
        with self.assertRaises(grammar.GalleyError):
            next(walker)

    def test_walk_step_after_removing_current_node_with_children_raises(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        root = self.session.root_node()
        assert root is not None
        walker = root.walk()
        # Advance to an interior node with children beneath it.
        interior: grammar.Node | None = None
        for step in walker:
            if step.depth == 1:
                interior = step.node
                break
        self.assertIsNotNone(interior)
        assert interior is not None
        self.assertGreater(len(interior), 0)
        self.session.remove_self(interior)
        # Removal clears the parent link but keeps first_child, so the very
        # next step must fail rather than descend into the detached subtree;
        # stepping again fails the same way, so nothing under the removed
        # node is ever yielded.
        with self.assertRaisesRegex(grammar.GalleyError, "invalid node"):
            next(walker)
        with self.assertRaisesRegex(grammar.GalleyError, "invalid node"):
            next(walker)

    def test_walk_steps_see_edits_between_steps(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        root = self.session.root_node()
        assert root is not None
        baseline = [(step.node.address, step.depth) for step in root.walk()]
        self.assertGreater(len(baseline), 1)

        walker = root.walk()
        first = next(walker)
        self.assertEqual(first.node, root)
        removed = self.session.first_child(root)
        assert removed is not None
        self.assertEqual(removed.address, baseline[1][0])
        head = self.session.remove_self(removed)
        self.assertIsNotNone(head)
        # The remainder follows the live links: the removed subtree — and
        # only it — is gone from the sequence.
        skip = 2
        while skip < len(baseline) and baseline[skip][1] > baseline[1][1]:
            skip += 1
        remaining = [(step.node.address, step.depth) for step in walker]
        self.assertEqual(remaining, baseline[skip:])
        # Re-inserting the removed subtree brings it back into the walk.
        assert head is not None
        self.session.append_children(root, head)
        restored = [(step.node.address, step.depth) for step in root.walk()]
        self.assertEqual(len(restored), len(baseline))
        self.assertIn((removed.address, baseline[1][1]), restored)

    def test_node_after_reparse_raises(self) -> None:
        root = self.session.root_node()
        assert root is not None
        self.assertGreater(self.session.child_count(root), 0)
        self.session.parse("alpha:12,beta:3")
        with self.assertRaises(grammar.StaleTreeError):
            self.session.child_count(root)
        with self.assertRaises(grammar.StaleTreeError):
            root.text()
        fresh = self.session.root_node()
        assert fresh is not None
        self.assertGreater(self.session.child_count(fresh), 0)

    def test_walk_step_after_moving_an_ancestor_under_the_walk_root_raises(
        self,
    ) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        # R->A->B->C below a walk root R that has a next sibling S, cursor
        # at C (depth 3). Moving B directly under R makes the climb reach R
        # one level early and steer onto S -- so the step refuses instead of
        # leaving the walk's subtree.
        root = self.session.root_node()
        assert root is not None
        pair_list = self.session.first_child(root)
        assert pair_list is not None
        pair = self.session.first_child(pair_list)  # R: Pair alpha
        assert pair is not None
        self.assertIsNotNone(self.session.next_sibling(pair))  # S exists

        walker = pair.walk()
        step = None
        for step in walker:
            # C: the leaf digit '2' at depth 3 (its NumberTail parent
            # matches the same text one level up, so the depth disambiguates).
            if step.node.text() == b"2" and step.depth == 3:
                break
        assert step is not None
        self.assertEqual(step.node.text(), b"2")
        self.assertEqual(step.depth, 3)
        node_c = step.node
        node_b = self.session.parent(node_c)
        node_a = self.session.parent(node_b) if node_b else None
        assert node_b is not None and node_a is not None
        self.assertEqual(self.session.parent(node_a), pair)  # R -> A -> B -> C

        head = self.session.remove_self(node_b)
        assert head is not None
        self.session.append_children(pair, head)  # B directly under R
        with self.assertRaisesRegex(grammar.GalleyError, "invalid node"):
            next(walker)
        # And again: nothing below the moved position is ever yielded.
        with self.assertRaisesRegex(grammar.GalleyError, "invalid node"):
            next(walker)

    def test_walk_step_after_moving_an_ancestor_under_a_foreign_node_raises(
        self,
    ) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        root = self.session.root_node()
        assert root is not None
        pair_list = self.session.first_child(root)
        assert pair_list is not None
        pair = self.session.first_child(pair_list)  # walk root
        assert pair is not None
        key = self.session.first_child(pair)  # an ancestor of the cursor
        assert key is not None
        first_letter = self.session.first_child(key)
        assert first_letter is not None

        walker = pair.walk()
        step = None
        for step in walker:
            if step.node.address == first_letter.address:
                break
        assert step is not None

        # Reparent the ancestor under a node the walk never entered: the
        # climb from its child lands outside the subtree, not on the root.
        head = self.session.remove_self(key)
        assert head is not None
        self.session.append_children(root, head)  # foreign: Document itself
        with self.assertRaisesRegex(grammar.GalleyError, "invalid node"):
            next(walker)
        with self.assertRaisesRegex(grammar.GalleyError, "invalid node"):
            next(walker)

    def test_walk_sees_a_child_inserted_under_a_not_yet_visited_node(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        root = self.session.root_node()
        assert root is not None
        pair_list = self.session.first_child(root)
        assert pair_list is not None
        pair_alpha = self.session.first_child(pair_list)
        assert pair_alpha is not None
        tail = self.session.next_sibling(pair_alpha)  # PairListTail
        assert tail is not None
        first_tail_child = self.session.first_child(tail)
        assert first_tail_child is not None
        inner_list = self.session.next_sibling(first_tail_child)  # second PairList
        assert inner_list is not None
        pair_beta = self.session.first_child(inner_list)  # not yet visited below
        assert pair_beta is not None
        key_alpha = self.session.first_child(pair_alpha)  # the subtree to insert
        assert key_alpha is not None
        old_depth = 3  # Document -> PairList -> Pair alpha -> Key

        walker = root.walk()
        first = next(walker)
        self.assertEqual(first.depth, 0)  # the edit happens at the root step

        head = self.session.remove_self(key_alpha)
        assert head is not None
        self.session.append_children(pair_beta, head)

        steps = [(step.node.address, step.depth) for step in walker]
        new_depth = 5  # Document -> PairList -> PairListTail -> PairList -> beta -> Key
        self.assertNotIn((key_alpha.address, old_depth), steps)
        self.assertIn((key_alpha.address, new_depth), steps)

    def test_completed_walk_raises_stale_tree_after_a_reparse(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        root = self.session.root_node()
        assert root is not None
        walker = root.walk()
        self.assertGreater(len(list(walker)), 0)
        with self.assertRaises(StopIteration):
            next(walker)
        # A walker belongs to the parse of the tree it was created over: the
        # generation check comes before "done", so a reparse turns even a
        # finished walk into a stale-tree error, and it stays one.
        self.session.parse("alpha:12,beta:3")
        for _ in range(2):
            with self.assertRaises(grammar.StaleTreeError):
                next(walker)

    def test_hook_walk_prunes_semantic_error_subtrees(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        # Error marks exist only in the in-flight tree: a semantic-failed
        # parse publishes nothing, so a walk inside the final hook is the
        # binding-side view that prunes a marked subtree where the plain
        # walk yields it.
        recorded: list[tuple[list[tuple[int, int, bool]], list[tuple[int, int]]]] = []

        def reduction_Number(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            assert node is not None
            text = node.text()
            assert text is not None
            if int(text) > 99:
                args.report_semantic_error("value out of range")

        def reduction_Document(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            assert node is not None
            full = [
                (step.node.address, step.depth, step.is_semantic_error)
                for step in node.walk()
            ]
            pruned = [
                (step.node.address, step.depth)
                for step in node.walk(skip_semantic_errors=True)
            ]
            recorded.append((full, pruned))

        self.session.install_procedure("reduction_Number", reduction_Number)
        self.session.install_procedure("reduction_Document", reduction_Document)
        try:
            with self.assertRaises(grammar.GalleyError) as raised:
                self.session.parse("alpha:1,beta:2000")
        finally:
            self.session.clear_procedures()
        self.assertEqual(raised.exception.code, grammar.Status.ERROR_SEMANTIC)

        self.assertGreater(len(recorded), 0)
        full, pruned = recorded[-1]
        flagged = {address for address, _, has_error in full if has_error}
        self.assertGreater(len(flagged), 0)  # the plain walk saw a mark
        self.assertLess(len(pruned), len(full))  # and the pruned walk dropped it
        self.assertTrue(flagged.isdisjoint({address for address, _ in pruned}))


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

    def test_edits_refuse_nodes_from_another_session(self) -> None:
        # A node crosses as a bare address and the native side only
        # bounds-checks it, so a node from another session would alias
        # whatever node holds that index here. Every entry that takes a
        # node refuses one from another session, not only the Node
        # convenience methods.
        other = grammar.Session()
        try:
            other.parse("alpha:12")
            other_root = other.root_node()
            self.assertIsNotNone(other_root)
            assert other_root is not None
            with self.assertRaisesRegex(ValueError, "different session"):
                self.root.append_children(other_root)
            with self.assertRaisesRegex(ValueError, "different session"):
                other_root.append_children(self.root)
            with self.assertRaisesRegex(ValueError, "different session"):
                self.session.append_children(self.root, other_root)
            with self.assertRaisesRegex(ValueError, "different session"):
                self.session.insert_before(self.root, other_root)
            with self.assertRaisesRegex(ValueError, "different session"):
                self.session.insert_after(self.root, other_root)
            with self.assertRaisesRegex(ValueError, "different session"):
                self.session.insert_children_at(self.root, 0, other_root)
            with self.assertRaisesRegex(ValueError, "different session"):
                self.session.text(other_root)
            with self.assertRaisesRegex(ValueError, "different session"):
                other.append_children(other_root, self.root)
        finally:
            other.close()

    def test_a_stale_node_cannot_edit_the_tree_that_replaced_it(self) -> None:
        # The edit gate is the read gate on the exclusive door: every edit
        # carrying a parse-1 node refuses, whichever node the other argument
        # is, so a dead tree is never edited by mistake.
        stale = self.root
        self.session.parse("alpha:12,beta:3")
        fresh = self.session.root_node()
        assert fresh is not None
        for edit in (
            lambda: stale.clean_children(),
            lambda: stale.append_children(fresh),
            lambda: fresh.append_children(stale),
            lambda: self.session.remove_self(stale),
            lambda: self.session.remove_siblings(stale, 1),
            lambda: self.session.insert_before(stale, fresh),
            lambda: self.session.insert_after(stale, fresh),
            lambda: self.session.insert_after(fresh, stale),
            lambda: self.session.insert_children_at(stale, 0, fresh),
            lambda: self.session.insert_children_at(fresh, 0, stale),
            lambda: self.session.remove_children_at(stale, 0, 1),
        ):
            with self.assertRaises(grammar.StaleTreeError):
                edit()
        # The fresh tree is untouched by every refusal.
        self.assertGreater(self.session.child_count(fresh), 0)

    def test_hook_refuses_nodes_of_an_earlier_parse(self) -> None:
        # A node of the previous parse against a node of the running parse,
        # both directions; the refusal must fire inside the hook.
        refusals: list[str] = []
        saved_procedures = grammar.list_procedures()

        def reduction_Pair(args: grammar.ProcedureArguments) -> None:
            hook_node = args.current_node()
            assert hook_node is not None
            for append in (
                lambda: self.root.append_children(hook_node),
                lambda: hook_node.append_children(self.root),
            ):
                try:
                    append()
                except grammar.StaleTreeError as error:
                    refusals.append(error.code)

        self.session.install_procedure("reduction_Pair", reduction_Pair)
        try:
            self.session.parse("alpha:12,beta:3")
        finally:
            _restore_procedures(saved_procedures)
        self.assertEqual(refusals, [grammar.Status.ERROR_STALE_TREE] * 4)

    def test_hook_door_refuses_a_node_of_an_earlier_parse_on_every_capability(
        self,
    ) -> None:
        # The core checks the generation inside every hook-door call: a node
        # of the previous parse raises the one stale-tree error on a read, a
        # link, a count, an edit and a walk step, and nothing answers None.
        self.session.parse("alpha:12,beta:3")
        previous = self.session.root_node()
        assert previous is not None
        previous_child = previous.first_child()
        assert previous_child is not None
        outcomes: list[str] = []
        live: list[bytes] = []

        def reduction_Pair(args: grammar.ProcedureArguments) -> None:
            current = args.current_node()
            assert current is not None
            session = self.session
            for call in (
                previous.text,
                previous.symbol_name,
                previous.span,
                previous.line_column,
                previous.first_child,
                previous.last_child,
                previous.next_sibling,
                previous.prior_sibling,
                previous.parent,
                lambda: len(previous),
                lambda: session.child_count(previous),
                lambda: session.variable_index(previous),
                lambda: list(previous.walk()),
                lambda: previous.append_children(current),
                lambda: current.append_children(previous),
                # Both nodes of the previous parse: the host's own
                # mixed-generation check passes, so the core's decides.
                lambda: previous.append_children(previous_child),
                lambda: session.insert_before(previous, previous_child),
                lambda: session.insert_after(previous, previous_child),
                lambda: session.insert_children_at(previous, 0, previous_child),
                lambda: session.remove_siblings(previous, 1),
                lambda: session.remove_children_at(previous, 0, 1),
                lambda: session.clean_children(previous),
                lambda: session.remove_self(previous),
                lambda: args.set_current_node(previous),
            ):
                try:
                    call()
                except grammar.StaleTreeError as error:
                    outcomes.append(error.code)
                else:
                    outcomes.append("answered")
            # A node of the running parse still reads and edits, and sets as
            # the current node.
            assert args.current_node() == current  # the refused set changed nothing
            args.set_current_node(current)
            assert args.current_node() == current
            text = current.text()
            assert text is not None
            live.append(text)
            detached = current.clean_children()
            if detached is not None:
                current.append_children(detached)

        self.session.install_procedure("reduction_Pair", reduction_Pair)
        try:
            self.session.parse("alpha:12,beta:3")
        finally:
            self.session.clear_procedures()
        self.assertEqual(outcomes, [grammar.Status.ERROR_STALE_TREE] * (24 * 2))
        self.assertEqual(live, [b"alpha:12", b"beta:3"])

    def test_chain_detached_in_one_hook_attaches_in_a_later_hook(self) -> None:
        # A chain detached in one hook can be attached in a later hook of
        # the same parse: both nodes carry the running parse's generation.
        outcomes: list[str] = []
        stash: list[grammar.Node] = []
        saved_procedures = grammar.list_procedures()

        def reduction_Pair(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            assert node is not None
            if not stash:
                head = node.clean_children()
                assert head is not None
                stash.append(head)
                return
            try:
                node.append_children(stash[0])
                outcomes.append("ok")
            except ValueError as error:
                outcomes.append(str(error))

        self.session.install_procedure("reduction_Pair", reduction_Pair)
        try:
            self.session.parse("alpha:12,beta:3")
        finally:
            _restore_procedures(saved_procedures)
        self.assertEqual(outcomes, ["ok"])

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

    def test_out_of_range_index_raises_instead_of_crashing(self) -> None:
        original = self.session.child_count(self.root)
        head = self.session.clean_children(self.root)
        assert head is not None
        for index in (1, original + 1, -1):
            with self.assertRaises(grammar.GalleyError):
                self.session.insert_children_at(self.root, index, head)
        self.session.insert_children_at(self.root, 0, head)
        for index in (original, -1):
            with self.assertRaises(grammar.GalleyError):
                self.session.remove_children_at(self.root, index, 1)
        with self.assertRaises(grammar.GalleyError):
            self.session.remove_children_at(self.root, 0, original + 1)
        self.assertEqual(self.session.child_count(self.root), original)


class GenerationTests(unittest.TestCase):
    """A node is the owning session, the core's parse generation and an
    address. Hosts read the generation from the core and choose the door
    per call: from inside a hook dispatch on the dispatching thread a node
    crosses the parse's hook door, anywhere else the session door."""

    session: grammar.Session
    saved_procedures: dict[str, Any]

    def setUp(self) -> None:
        self.session = grammar.Session()
        self.saved_procedures = grammar.list_procedures()

    def tearDown(self) -> None:
        self.session.close()
        _restore_procedures(self.saved_procedures)

    def _stash_pairs_while_parsing(self, text: str) -> list[grammar.Node]:
        stashed: list[grammar.Node] = []

        def reduction_Pair(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            assert node is not None
            stashed.append(node)

        self.session.install_procedure("reduction_Pair", reduction_Pair)
        try:
            self.session.parse(text)
        finally:
            self.session.clear_procedures()
        return stashed

    def test_refused_parse_leaves_running_hook_nodes_and_the_published_tree_valid(
        self,
    ) -> None:
        # The core refuses a parse of a session that is already parsing and
        # changes nothing: a node stashed by hook 1 still reads in hook 2,
        # and the tree the running parse publishes is readable afterwards.
        stashed: list[grammar.Node] = []
        first_hook_done = threading.Event()
        refused_parse_done = threading.Event()
        later_reads: list[bytes | None] = []

        def reduction_Pair(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            assert node is not None
            if not stashed:
                stashed.append(node)
                first_hook_done.set()
                self.assertTrue(refused_parse_done.wait(30))
            else:
                later_reads.append(stashed[0].text())

        self.session.install_procedure("reduction_Pair", reduction_Pair)
        outcomes: list[int] = []
        thread = threading.Thread(
            target=lambda: outcomes.append(self.session.parse("alpha:12,beta:3"))
        )
        thread.start()
        try:
            self.assertTrue(first_hook_done.wait(30))
            with self.assertRaises(grammar.GalleyError) as refusal:
                self.session.parse("gamma:1")
            self.assertEqual(
                refusal.exception.code, grammar.Status.ERROR_SESSION_IN_USE
            )
        finally:
            refused_parse_done.set()
            thread.join(30)
        self.assertEqual(outcomes, [15])
        self.assertEqual(later_reads, [b"alpha:12"])
        root = self.session.root_node()
        assert root is not None
        self.assertEqual(self.session.text(root), b"alpha:12,beta:3")
        self.assertEqual(stashed[0].text(), b"alpha:12")

    def test_a_hook_that_parses_its_own_session_is_refused_and_keeps_its_nodes(
        self,
    ) -> None:
        refusals: list[int] = []
        reads: list[bytes | None] = []
        stashed: list[grammar.Node] = []

        def reduction_Pair(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            assert node is not None
            if not stashed:
                stashed.append(node)
                try:
                    self.session.parse("gamma:1")
                except grammar.GalleyError as error:
                    refusals.append(error.code)
            reads.append(stashed[0].text())

        self.session.install_procedure("reduction_Pair", reduction_Pair)
        self.session.parse("alpha:12,beta:3")
        self.assertEqual(refusals, [grammar.Status.ERROR_SESSION_IN_USE])
        self.assertEqual(reads, [b"alpha:12", b"alpha:12"])
        self.assertEqual(stashed[0].text(), b"alpha:12")

    def test_hook_node_after_a_successful_parse_reads_through_the_session(self) -> None:
        stashed = self._stash_pairs_while_parsing("alpha:12,beta:3")
        self.assertEqual(len(stashed), 2)
        first = stashed[0]
        self.assertEqual(first.text(), b"alpha:12")
        self.assertEqual(self.session.text(first), b"alpha:12")
        self.assertEqual(self.session.child_count(first), len(first))
        root = self.session.root_node()
        assert root is not None
        found: grammar.Node | None = None
        for step in root.walk():
            if step.node.address == first.address:
                found = step.node
                break
        self.assertIsNotNone(found)
        assert found is not None
        self.assertEqual(found, first)
        self.assertEqual(hash(found), hash(first))
        self.assertEqual({found: "session"}[first], "session")

    def test_hook_node_of_a_parse_that_publishes_nothing_is_refused_afterwards(
        self,
    ) -> None:
        stashed: list[grammar.Node] = []

        def reduction_Number(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            assert node is not None
            stashed.append(node)

        # One error is the limit, so the failing parse raises instead of
        # recovering and publishes nothing: its nodes die with it.
        strict = grammar.Session(max_errors=1)
        try:
            strict.install_procedure("reduction_Number", reduction_Number)
            with self.assertRaises(grammar.GalleyError):
                strict.parse("alpha:12,beta:")
            self.assertGreaterEqual(len(stashed), 1)
            with self.assertRaises(grammar.StaleTreeError):
                stashed[0].text()
            with self.assertRaises(grammar.StaleTreeError):
                strict.text(stashed[0])
            strict.clear_procedures()
            strict.parse("alpha:12,beta:3")
            with self.assertRaises(grammar.StaleTreeError):
                stashed[0].text()
        finally:
            strict.close()

    def test_hook_node_of_a_published_failure_lives_until_the_next_parse(self) -> None:
        stashed: list[grammar.Node] = []

        def reduction_Number(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            assert node is not None
            stashed.append(node)

        # The parser recovers from the missing Number, so the failure
        # publishes its tree and the nodes its hooks saw stay valid.
        self.session.install_procedure("reduction_Number", reduction_Number)
        with self.assertRaises(grammar.GalleyError):
            self.session.parse("alpha:12,beta:")
        self.session.clear_procedures()
        self.assertGreaterEqual(len(stashed), 1)
        self.assertEqual(stashed[0].text(), b"12")
        self.session.parse("alpha:12,beta:3")
        with self.assertRaises(grammar.StaleTreeError):
            stashed[0].text()

    def test_hook_node_used_from_another_thread_is_refused_by_the_session_door(
        self,
    ) -> None:
        # The hook door takes no lock, so it is reachable only from the thread
        # running the hook. Any other thread crosses the session door, which
        # the core refuses while the parse runs.
        stashed: list[grammar.Node] = []
        first_hook_done = threading.Event()
        probes_done = threading.Event()
        probe_codes: list[int] = []

        def reduction_Pair(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            assert node is not None
            if not stashed:
                stashed.append(node)
                first_hook_done.set()
                self.assertTrue(probes_done.wait(30))

        self.session.install_procedure("reduction_Pair", reduction_Pair)
        thread = threading.Thread(target=lambda: self.session.parse("alpha:12,beta:3"))
        thread.start()
        try:
            self.assertTrue(first_hook_done.wait(30))
            for probe in (
                lambda: stashed[0].text(),
                lambda: stashed[0].children(),
                lambda: self.session.text(stashed[0]),
                lambda: stashed[0].clean_children(),
            ):
                with self.assertRaises(grammar.GalleyError) as refusal:
                    probe()
                probe_codes.append(refusal.exception.code)
        finally:
            probes_done.set()
            thread.join(30)
        self.assertEqual(probe_codes, [grammar.Status.ERROR_SESSION_IN_USE] * 4)
        self.assertEqual(stashed[0].text(), b"alpha:12")

    def test_node_of_an_earlier_parse_is_not_the_node_at_the_same_address(self) -> None:
        self.session.parse("alpha:12")
        first_root = self.session.root_node()
        assert first_root is not None
        self.session.parse("alpha:12")
        second_root = self.session.root_node()
        assert second_root is not None
        self.assertEqual(first_root.address, second_root.address)
        self.assertNotEqual(first_root, second_root)
        self.assertEqual(len({first_root, second_root}), 2)
        with self.assertRaises(grammar.StaleTreeError):
            first_root.text()
        self.assertEqual(second_root.text(), b"alpha:12")

    def test_walk_inside_a_hook_equals_the_post_parse_walk(self) -> None:
        # A walk created and stepped inside a hook goes through the parse's
        # own door over the in-flight tree; replayed after the parse
        # publishes, the same root yields the identical sequence.
        recorded: list[tuple[list[tuple[int, int]], grammar.Node]] = []

        def reduction_Pair(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            assert node is not None
            steps = [(step.node.address, step.depth) for step in node.walk()]
            recorded.append((steps, node))

        self.session.install_procedure("reduction_Pair", reduction_Pair)
        self.session.parse("alpha:12,beta:3")
        self.session.clear_procedures()
        self.assertGreater(len(recorded), 0)
        for steps, hook_root in recorded:
            replayed = [(step.node.address, step.depth) for step in hook_root.walk()]
            self.assertEqual(replayed, steps)

        root = self.session.root_node()
        assert root is not None
        # walk() always hands back a walker, never None.
        self.assertIsNotNone(root.walk())

    def test_node_equality_ignores_the_door(self) -> None:
        # The same node reached inside the hook and from the session after
        # the parse is one node.
        stashed = self._stash_pairs_while_parsing("alpha:12")
        root = self.session.root_node()
        assert root is not None
        wrapper = self.session.first_child(root)
        assert wrapper is not None
        pair = self.session.first_child(wrapper)
        assert pair is not None
        self.assertEqual(stashed[0], pair)
        self.assertEqual(hash(stashed[0]), hash(pair))


class BorrowedMemoryTests(unittest.TestCase):
    """Text and input pointers the core returns are borrowed.

    They are valid until the next parse (inside a hook, until it returns), and
    the session reuses two buffers for its input, so the third parse after a
    read rewrites the memory the read came from. Every accessor must copy
    before it returns; each read below is kept across such parses and must
    still hold what it held when it was made.
    """

    FIRST = "alpha:12,beta:3"
    # Same length as FIRST, so each one lands in a buffer FIRST used.
    CHURN = ("qqqqq:88,wwww:7", "xxxxx:77,yyyy:6", "ppppp:66,rrrr:5")

    def setUp(self) -> None:
        self.session = grammar.Session(max_errors=10)
        self.saved_procedures = grammar.list_procedures()

    def tearDown(self) -> None:
        self.session.close()
        _restore_procedures(self.saved_procedures)

    def churn(self) -> None:
        for text in self.CHURN:
            self.session.parse(text)

    def test_node_text_and_input_are_copies(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        self.session.parse(self.FIRST)
        root = self.session.root_node()
        assert root is not None
        nodes = [step.node for step in root.walk()]
        texts = [node.text() for node in nodes]
        names = [node.symbol_name() for node in nodes]
        via_session = [self.session.text(node) for node in nodes]
        names_via_session = [self.session.symbol_name(node) for node in nodes]
        last_input = self.session.last_input()
        self.churn()
        self.assertEqual(self.session.last_input(), self.CHURN[-1].encode())
        self.assertEqual(last_input, self.FIRST.encode())
        self.assertEqual(texts[0], self.FIRST.encode())
        self.assertIn(b"alpha:12", texts)
        self.assertIn(b"beta:3", texts)
        self.assertEqual(via_session, texts)
        self.assertEqual(names.count(b"Pair"), 2)
        self.assertEqual(names_via_session, names)

    def test_hook_text_is_a_copy(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        seen: list[tuple[bytes, bytes]] = []

        def reduction_Pair(args: grammar.ProcedureArguments) -> None:
            node = args.current_node()
            assert node is not None
            seen.append((node.text(), node.symbol_name()))

        self.session.install_procedure("reduction_Pair", reduction_Pair)
        self.session.parse(self.FIRST)
        self.churn()
        self.assertEqual(seen[:2], [(b"alpha:12", b"Pair"), (b"beta:3", b"Pair")])

    def test_diagnostics_are_copies(self) -> None:
        with self.assertRaises(grammar.GalleyError) as raised:
            self.session.parse("alpha:")
        failure = raised.exception.diagnostic
        assert failure is not None
        current = self.session.diagnostic()
        assert current is not None
        recorded = self.session.diagnostics()

        def fields(diagnostic: Any) -> tuple[Any, ...]:
            return (
                diagnostic.message,
                diagnostic.message_ansi,
                diagnostic.unexpected_token,
                diagnostic.expected_tokens,
                diagnostic.context,
                diagnostic.semantic,
                diagnostic.recovery_terminal,
                diagnostic.recovery_lhs_variable,
                diagnostic.recovery_production,
                diagnostic.recovery_occurrence,
            )

        before = (fields(failure), fields(current), [fields(item) for item in recorded])
        self.assertTrue(failure.expected_tokens)
        # Failures of the same shape rewrite the input buffers and the
        # rendered message; successes release the diagnostic memory.
        for text in ("beta:?", "gamma:", "alpha:12,beta:3", "delta:", "alpha:12,beta:3"):
            try:
                self.session.parse(text)
            except grammar.GalleyError:
                pass
        self.assertEqual(
            (fields(failure), fields(current), [fields(item) for item in recorded]),
            before,
        )


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
        walker = root.walk()
        self.assertIsNotNone(next(walker))
        session.close()
        with self.assertRaises(ValueError):
            next(walker)
        with self.assertRaises(ValueError):
            walker.skip_children()

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
    grammars: same content, separate parser objects — which is exactly
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

    def test_nul_artifact_path_is_rejected_loudly(self) -> None:
        with self.assertRaises(ValueError):
            galley.load("no-such-grammar\0.so")

    def test_same_path_returns_same_parser(self) -> None:
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
        parser = galley.load(impl)
        self.assertFalse(hasattr(parser, "procedures"))
        self.assertEqual(parser.list_procedures(), {})
        with parser.Session() as session:
            session.parse("alpha:12")
        self.assertEqual(parser.list_procedures(), {})

    def test_manual_dict_install_fires(self) -> None:
        parser = galley.load(self._copy_impl())
        fired: list[bytes] = []

        def reduction_Number(args: Any) -> None:
            node = args.current_node()
            assert node is not None
            text = node.text()
            assert text is not None
            fired.append(text)

        parser.install_procedures({"reduction_Number": reduction_Number})
        try:
            self.assertIn("reduction_Number", parser.list_procedures())
            with parser.Session() as session:
                session.parse("alpha:12")
            self.assertEqual(fired, [b"12"])
        finally:
            parser.clear_procedures()

    def test_near_miss_hook_names_warn(self) -> None:
        parser = galley.load(self._copy_impl())

        def reductionPair(args: Any) -> None:
            pass

        try:
            with self.assertWarns(RuntimeWarning):
                installed = parser.install_procedures({"reductionPair": reductionPair})
            self.assertEqual(installed, 0)
            self.assertNotIn("reductionPair", parser.list_procedures())
        finally:
            parser.clear_procedures()

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


class GeneratedPackageInitTests(unittest.TestCase):
    """The generated init: one import, no file discovery.

    Packages are assembled from the prebuilt fixture extension and
    ``emit_package_init``'s own output — the init is what's under test,
    so no rebuild runs.
    """

    def setUp(self) -> None:
        from galley.build import GENERATED_MARKER, emit_package_init

        self.generated_marker = GENERATED_MARKER
        self.emit_package_init = emit_package_init
        self.directory = Path(tempfile.mkdtemp(prefix="galley-init-test-"))
        self.addCleanup(shutil.rmtree, self.directory, True)

    def _make_package(self, name: str, procedures: str | None = None) -> Path:
        package = self.directory / name
        package.mkdir()
        suffix = sysconfig.get_config_var("EXT_SUFFIX")
        shutil.copy2(_fixture_impl_file(), package / f"galley_impl{suffix}")
        self.emit_package_init(package)
        if procedures is not None:
            (package / "procedures.py").write_text(procedures, encoding="utf-8")
        sys.path.insert(0, str(self.directory))
        self.addCleanup(sys.path.remove, str(self.directory))
        for key in (name, f"{name}.procedures", f"{name}.galley_impl"):
            self.addCleanup(sys.modules.pop, key, None)
        return package

    def test_missing_procedures_module_is_stubbed_and_kept(self) -> None:
        package = self.directory / "stublang"
        package.mkdir()
        self.emit_package_init(package)
        stub = package / "procedures.py"
        self.assertIn(self.generated_marker, stub.read_text(encoding="utf-8"))
        # A hand-written module survives a regeneration untouched.
        stub.write_text(
            "def reduction_Number(args) -> None:\n    pass\n", encoding="utf-8"
        )
        self.emit_package_init(package)
        self.assertIn("reduction_Number", stub.read_text(encoding="utf-8"))

    def test_import_wires_hooks_with_no_file_discovery(self) -> None:
        self._make_package(
            "wiredlang",
            "seen: list[bytes] = []\n"
            "def reduction_Number(args) -> None:\n"
            "    node = args.current_node()\n"
            "    assert node is not None\n"
            "    text = node.text()\n"
            "    assert text is not None\n"
            "    seen.append(text)\n",
        )
        import wiredlang

        with wiredlang.Session() as session:
            session.parse("alpha:12")
        from wiredlang import procedures

        self.assertEqual(procedures.seen, [b"12"])
        # Importable, but not part of the package's public surface.
        self.assertNotIn("procedures", dir(wiredlang))

    def test_hookless_package_imports_silently(self) -> None:
        import contextlib
        import io

        self._make_package("silentlang")  # no procedures.py: the build's stub
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            import silentlang  # noqa: F401

        self.assertEqual(stderr.getvalue(), "")
        self.assertEqual(silentlang.list_procedures(), {})


class SessionHookTests(unittest.TestCase):
    """Hooks belong to the session: a copy of the defaults at open."""

    def setUp(self) -> None:
        self.saved_procedures = grammar.list_procedures()
        grammar.clear_procedures()

    def tearDown(self) -> None:
        _restore_procedures(self.saved_procedures)

    def test_sessions_own_their_hooks(self) -> None:
        first_calls: list[int] = []
        second_calls: list[int] = []
        with grammar.Session() as first, grammar.Session() as second:
            first.install_procedure("reduction_Pair", lambda: first_calls.append(1))
            second.install_procedure("reduction_Number", lambda: second_calls.append(1))
            first.parse("alpha:12,beta:3")
            self.assertEqual((len(first_calls), len(second_calls)), (2, 0))
            second.parse("alpha:12,beta:3")
            self.assertEqual((len(first_calls), len(second_calls)), (2, 2))
            self.assertIn("reduction_Pair", first.list_procedures())
            self.assertNotIn("reduction_Number", first.list_procedures())
            self.assertIsNone(second.procedure_hook("reduction_Pair"))

    def test_defaults_reach_only_later_sessions(self) -> None:
        calls: list[int] = []
        with grammar.Session() as earlier:
            grammar.install_procedure("reduction_Pair", lambda: calls.append(1))
            with grammar.Session() as later:
                earlier.parse("alpha:12,beta:3")
                self.assertEqual(len(calls), 0)
                later.parse("alpha:12,beta:3")
                self.assertEqual(len(calls), 2)
                grammar.clear_procedures()
                later.parse("alpha:12,beta:3")
                self.assertEqual(len(calls), 4)
                self.assertEqual(grammar.list_procedures(), {})

    def test_session_install_procedures_follows_the_naming_rules(self) -> None:
        with grammar.Session() as session:
            with warnings.catch_warnings(record=True) as caught:
                warnings.simplefilter("always")
                installed = session.install_procedures(
                    {
                        "reduction_Pair": lambda: None,
                        "reductionPair": lambda: None,
                        "myHelper": lambda: None,
                    }
                )
            self.assertEqual(installed, 1)
            self.assertEqual(list(session.list_procedures()), ["reduction_Pair"])
            messages = [str(item.message) for item in caught]
            self.assertTrue(any('"reductionPair"' in message for message in messages))
            self.assertFalse(any("myHelper" in message for message in messages))
            with self.assertRaises(TypeError):
                session.install_procedure("reduction_Pair", "not callable")

    def test_hooks_naming_no_grammar_hook_are_listed_but_never_fire(self) -> None:
        with grammar.Session() as session:
            session.install_procedure(
                "reduction_Nonexistent", lambda: self.fail("fired")
            )
            self.assertIn("reduction_Nonexistent", session.list_procedures())
            session.parse("alpha:12")

    def test_hooks_closing_over_their_session_do_not_leak_it(self) -> None:
        class Sentinel:
            pass

        sentinel = Sentinel()
        session = grammar.Session()
        # session -> hooks -> lambda -> session: a cycle only collection frees.
        session.install_procedure("reduction_Pair", lambda: (session, sentinel))
        session.parse("alpha:12")
        reference = weakref.ref(sentinel)
        del session, sentinel
        gc.collect()
        self.assertIsNone(reference())

    def test_closed_session_refuses_hook_changes(self) -> None:
        session = grammar.Session()
        session.close()
        for change in (
            lambda: session.install_procedure("reduction_Pair", lambda: None),
            session.clear_procedures,
            session.list_procedures,
        ):
            with self.assertRaises(ValueError):
                change()


_SECOND_FIXTURE_DIRECTORY = BINDINGS_DIRECTORY / "test_fixture_second"


class _Worker:
    """One session's configuration and what its hooks saw."""

    def __init__(
        self,
        parser: Any,
        text: str,
        hooks: tuple[str, ...],
        barrier: threading.Barrier | None,
    ) -> None:
        self.parser = parser
        self.text = text
        self.hooks = hooks
        self.barrier = barrier
        self.calls: dict[str, int] = {}
        self.wrong_thread = 0
        self.arrivals = 0
        self.barrier_failure: BaseException | None = None
        self.refusal: BaseException | None = None
        self.foreign_text = 0
        self.thread: threading.Thread | None = None
        self.session: Any = None

    def open(self) -> None:
        self.session = self.parser.Session()
        for hook in self.hooks:
            self.session.install_procedure(hook, self._hook(hook))

    def _hook(self, hook: str) -> Any:
        def on_hook(args: Any) -> None:
            if threading.current_thread() is not self.thread:
                self.wrong_thread += 1
            self.calls[hook] = self.calls.get(hook, 0) + 1
            node = args.current_node()
            if node is None or not node.text():
                self.foreign_text += 1
            if self.barrier is not None and self.arrivals == 0:
                self.arrivals += 1
                try:
                    self.barrier.wait(timeout=20)
                except threading.BrokenBarrierError as failure:
                    self.barrier_failure = failure
                # Still inside the parse: changing hooks must be refused.
                try:
                    self.session.clear_procedures()
                except Exception as failure:  # noqa: BLE001 - recorded for the assertion
                    self.refusal = failure

        return on_hook

    def reset(self) -> None:
        self.calls = {}
        self.wrong_thread = 0
        self.arrivals = 0
        self.barrier_failure = None
        self.refusal = None
        self.foreign_text = 0

    def run(self) -> None:
        self.thread = threading.current_thread()
        self.session.parse(self.text)


def _run_threads(workers: list[_Worker]) -> None:
    threads = [threading.Thread(target=worker.run) for worker in workers]
    for worker, thread in zip(workers, threads):
        worker.thread = thread
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=60)
        assert not thread.is_alive(), "a parse did not finish"


class ConcurrencyTests(unittest.TestCase):
    """Two parsers, two sessions each, four threads parsing at the same time.

    The first hook of every parse waits at a four-way barrier, so the test
    passes only if all four parses are in flight at once. Each session
    carries its own hooks, and every hook checks that it runs on its own
    session's thread and reads its own session's nodes.
    """

    ITEMS = 150
    STRESS_ROUNDS = 100

    @classmethod
    def setUpClass(cls) -> None:
        suffix = sysconfig.get_config_var("EXT_SUFFIX")
        impl = _SECOND_FIXTURE_DIRECTORY / f"galley_impl{suffix}"
        if not impl.is_file():
            raise FileNotFoundError(
                f"build {_SECOND_FIXTURE_DIRECTORY} first (python -m galley)"
            )
        cls.second = galley.load(impl)

    def _expected(self, worker: _Worker, first: bool) -> None:
        specific = "hook_print" if first else "hook_tally"
        reduction = "reduction_Pair" if first else "reduction_Word"
        self.assertEqual(
            worker.calls.get(specific, 0), self.ITEMS if specific in worker.hooks else 0
        )
        self.assertEqual(
            worker.calls.get(reduction, 0),
            self.ITEMS if reduction in worker.hooks else 0,
        )
        self.assertEqual(worker.wrong_thread, 0)
        self.assertEqual(worker.foreign_text, 0)

    def test_two_parsers_two_sessions_each_four_threads_at_once(self) -> None:
        keyvalue = ",".join(f"k{i}:{i % 97}" for i in range(self.ITEMS))
        words = "+".join("word" for _ in range(self.ITEMS))
        barrier = threading.Barrier(4)
        saved = grammar.list_procedures()
        grammar.clear_procedures()
        self.addCleanup(_restore_procedures, saved)
        workers = [
            _Worker(grammar, keyvalue, ("reduction_Pair", "hook_print"), barrier),
            _Worker(grammar, keyvalue, ("hook_print",), barrier),
            _Worker(self.second, words, ("reduction_Word", "hook_tally"), barrier),
            _Worker(self.second, words, ("reduction_Word",), barrier),
        ]
        for worker in workers:
            worker.open()
            self.addCleanup(worker.session.close)

        # Four parses held at one barrier: all four in flight at once.
        _run_threads(workers)
        for index, worker in enumerate(workers):
            self.assertIsNone(worker.barrier_failure, "the four parses did not overlap")
            self._expected(worker, first=index < 2)
            self.assertIsInstance(worker.refusal, worker.parser.GalleyError)
            self.assertEqual(
                worker.refusal.code, worker.parser.Status.ERROR_SESSION_IN_USE
            )
            self.assertEqual(len(worker.session.list_procedures()), len(worker.hooks))

        # Stress: the same four sessions parse again and again without the
        # barrier; every round reproduces the expected counts.
        for worker in workers:
            worker.barrier = None
        for _ in range(self.STRESS_ROUNDS):
            for worker in workers:
                worker.reset()
            _run_threads(workers)
            for index, worker in enumerate(workers):
                self._expected(worker, first=index < 2)

    def test_parse_releases_the_gil(self) -> None:
        # A parse reading from a FIFO blocks inside native code until the
        # main thread writes. If the parse held the GIL the main thread
        # could never run, so a held GIL shows up as a timeout here.
        script = (
            "import os, sys, tempfile, threading\n"
            f"sys.path.insert(0, {str(BINDINGS_DIRECTORY)!r})\n"
            "import test_fixture as grammar\n"
            "grammar.clear_procedures()\n"
            "fifo = os.path.join(tempfile.mkdtemp(), 'input.kv')\n"
            "os.mkfifo(fifo)\n"
            "result = []\n"
            "def parse():\n"
            "    with grammar.Session() as session:\n"
            "        result.append(session.parse_file(fifo))\n"
            "thread = threading.Thread(target=parse)\n"
            "thread.start()\n"
            "with open(fifo, 'wb') as writer:\n"
            "    writer.write(b'alpha:12,beta:3')\n"
            "thread.join()\n"
            "assert result == [15], result\n"
        )
        completed = subprocess.run(
            [sys.executable, "-c", script], timeout=60, capture_output=True, text=True
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)


class BuildGuardTests(unittest.TestCase):
    """Contracts of the clobber guard.

    The guard is a pure function of file content, so it is tested
    directly: no generator, no rebuild. Foreign files are a loud fatal
    and left in place; marked and absent paths pass through.
    """

    def test_guard_refuses_foreign_files(self) -> None:
        from galley import build as build_module

        with tempfile.TemporaryDirectory(prefix="galley-guard-test-") as tmp:
            foreign = Path(tmp) / "foreign.zig"
            foreign.write_text("// hand-written shim\n", encoding="utf-8")
            with self.assertRaises(SystemExit):
                build_module.assert_generated_or_absent(foreign)
            self.assertTrue(foreign.is_file())
            marked = Path(tmp) / "__init__.pyi"
            marked.write_text(f"# {build_module.GENERATED_MARKER}\n", encoding="utf-8")
            build_module.assert_generated_or_absent(marked)
            build_module.assert_generated_or_absent(Path(tmp) / "absent.zig")
            # Legacy output predates the banner: a bare copy of the stub
            # source passes, while a foreign file does not.
            legacy = Path(tmp) / "legacy.pyi"
            legacy.write_text(
                '"""\nType stubs for a Galley language package.\n"""\n',
                encoding="utf-8",
            )
            build_module.assert_generated_or_absent(
                legacy, build_module.STUB_LEGACY_HEAD
            )
            with self.assertRaises(SystemExit):
                build_module.assert_generated_or_absent(
                    foreign, build_module.STUB_LEGACY_HEAD
                )


class BuildOptimizeTests(unittest.TestCase):
    """`python -m galley` forwards `-Doptimize` to the consumer build only
    when a mode was chosen. The real entry point runs with a fake generator
    and a fake zig that records its arguments and fails, so nothing builds."""

    def consumer_build_arguments(self, extra_arguments: "list[str]") -> "list[str]":
        from unittest import mock

        from galley import build as build_module

        with tempfile.TemporaryDirectory(prefix="galley-optimize-test-") as tmp:
            root = Path(tmp)
            checkout = root / "checkout"
            checkout.mkdir()
            (checkout / "build.zig").write_text("", encoding="utf-8")
            language_dir = root / "language"
            language_dir.mkdir()
            (language_dir / "ll.grm").write_text("", encoding="utf-8")
            generator = root / "generator"
            generator.write_text(
                '#!/bin/sh\n[ "$1" = --help ] && echo --emit-host-procedures\nexit 0\n',
                encoding="utf-8",
            )
            recorded = root / "recorded.txt"
            fake_zig = root / "zig"
            fake_zig.write_text(
                f'#!/bin/sh\nprintf "%s\\n" "$@" > "{recorded}"\nexit 1\n',
                encoding="utf-8",
            )
            generator.chmod(0o755)
            fake_zig.chmod(0o755)
            environment = {
                "GALLEY_CHECKOUT": str(checkout),
                "GALLEY_CLI": str(generator),
                "ZIG_EXECUTABLE": str(fake_zig),
            }
            arguments = ["galley", str(language_dir), *extra_arguments]
            with (
                mock.patch.dict(os.environ, environment),
                mock.patch.object(sys, "argv", arguments),
                mock.patch("builtins.print"),
            ):
                with self.assertRaises(SystemExit):
                    build_module.main()
            return recorded.read_text(encoding="utf-8").splitlines()

    def test_no_option_passes_no_optimize_argument(self) -> None:
        arguments = self.consumer_build_arguments([])
        self.assertIn("--build-file", arguments)
        self.assertEqual(
            [argument for argument in arguments if argument.startswith("-Doptimize")],
            [],
        )

    def test_empty_mode_counts_as_not_chosen(self) -> None:
        arguments = self.consumer_build_arguments(["--optimize", ""])
        self.assertEqual(
            [argument for argument in arguments if argument.startswith("-Doptimize")],
            [],
        )

    def test_chosen_mode_is_passed_through_verbatim(self) -> None:
        self.assertIn(
            "-Doptimize=Debug", self.consumer_build_arguments(["--optimize", "Debug"])
        )


class PublishedFailureTests(unittest.TestCase):
    """A parse that fails after running to its end publishes its tree.

    Semantic errors mark nodes, recovered syntax errors leave flagged nodes
    over the damaged input, and ``parse`` still raises. A parse the parser
    cannot recover from publishes nothing.
    """

    # Recovery skips `x,beta:` to resynchronize, then `2`: two recovered nodes.
    RECOVERED = "alpha:x,beta:2"
    # Parses, but a hook reports one semantic error on the Number `2000`.
    SEMANTIC = "alpha:1,beta:2000"

    def setUp(self) -> None:
        if not grammar.has_ast():
            self.skipTest("no AST build")
        self.session = grammar.Session(max_errors=10)

    def tearDown(self) -> None:
        self.session.close()

    def steps(self, **options: bool) -> list[tuple[str, int, int, Any]]:
        root = self.session.root_node()
        assert root is not None
        return [
            (
                step.node.symbol_name().decode(),
                *step.node.span(),
                step,
            )
            for step in root.walk(**options)
        ]

    def test_semantic_only_failure_publishes_its_tree(self) -> None:
        with self.assertRaises(grammar.GalleyError) as raised:
            self.session.parse(self.SEMANTIC)
        self.assertEqual(raised.exception.code, grammar.Status.ERROR_SEMANTIC)

        full = self.steps()
        marked = [entry for entry in full if entry[3].is_semantic_error]
        self.assertEqual(len(marked), 1)
        self.assertEqual(marked[0][:3], ("Number", 13, 4))
        self.assertFalse(any(entry[3].is_recovered for entry in full))

        pruned = self.steps(skip_semantic_errors=True)
        self.assertLess(len(pruned), len(full))
        self.assertFalse(any(entry[3].is_semantic_error for entry in pruned))
        # Nothing is recovered, so skipping recovered nodes changes nothing.
        self.assertEqual(len(self.steps(skip_recovered=True)), len(full))

        snapshot = self.session.snapshot()
        self.assertEqual(sum(snapshot.is_semantic_error), 1)
        self.assertFalse(any(snapshot.is_recovered))
        self.assertEqual(self.session.last_input(), self.SEMANTIC.encode())
        self.assertEqual(self.session.last_position(), (1, len(self.SEMANTIC) + 2))

        # The next parse retires the errored tree's nodes.
        stale = self.session.root_node()
        assert stale is not None
        self.session.parse("alpha:12,beta:3")
        with self.assertRaises(grammar.StaleTreeError):
            stale.text()

    def test_recovered_syntax_error_publishes_its_tree(self) -> None:
        with self.assertRaises(grammar.GalleyError) as raised:
            self.session.parse(self.RECOVERED)
        self.assertEqual(raised.exception.code, grammar.Status.ERROR_SYNTAX)

        full = self.steps()
        recovered = [entry for entry in full if entry[3].is_recovered]
        self.assertEqual(len(recovered), 2)
        self.assertFalse(any(entry[3].is_semantic_error for entry in full))
        # The damaged Number covers the input recovery skipped: `x,beta:`.
        self.assertEqual(recovered[0][:3], ("Number", 6, 7))

        # Skipping them leaves only undamaged nodes, none inside the damage.
        undamaged = self.steps(skip_recovered=True)
        self.assertEqual(len(undamaged), len(full) - 2)
        for _, start, _, step in undamaged:
            self.assertFalse(step.is_recovered)
            self.assertTrue(start < 6 or start >= 13)

        # The snapshot column reads what the walk reports, node for node.
        snapshot = self.session.snapshot()
        flagged = [i for i, flag in enumerate(snapshot.is_recovered) if flag]
        self.assertEqual(
            flagged, [entry[3].node.address for entry in full if entry[3].is_recovered]
        )

        self.assertEqual(self.session.last_input(), self.RECOVERED.encode())
        self.assertIsNotNone(self.session.last_position())

        stale = self.session.root_node()
        assert stale is not None
        self.session.parse("alpha:12,beta:3")
        with self.assertRaises(grammar.StaleTreeError):
            stale.text()

    def test_unrecovered_syntax_error_publishes_nothing(self) -> None:
        # One error is the limit, so the parser raises instead of recovering.
        strict = grammar.Session(max_errors=1)
        try:
            with self.assertRaises(grammar.GalleyError):
                strict.parse(self.RECOVERED)
            self.assertIsNone(strict.root_node())
            for read in (strict.last_input, strict.last_position, strict.node_count):
                with self.assertRaises(grammar.StaleTreeError):
                    read()
        finally:
            strict.close()

    def test_last_input_and_position_refuse_before_any_parse(self) -> None:
        for read in (self.session.last_input, self.session.last_position):
            with self.assertRaises(grammar.StaleTreeError):
                read()

    def test_a_failure_without_a_root_still_publishes_its_input(self) -> None:
        # Recovery skips all of the input before the grammar's first symbol:
        # the parse publishes, but there is no tree to hold a root.
        with self.assertRaises(grammar.GalleyError):
            self.session.parse("?")
        self.assertIsNone(self.session.root_node())
        self.assertEqual(self.session.last_input(), b"?")


if __name__ == "__main__":
    unittest.main(verbosity=2)
