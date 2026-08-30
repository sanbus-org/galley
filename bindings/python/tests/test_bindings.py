"""Behavioral tests for the Galley Python bindings.

The suite imports the built extension module as `galley`; point PYTHONPATH
at a language directory produced by `python -m galley_bindings` (the example
works out of the box):

    PYTHONPATH=examples/python python3 bindings/python/tests/test_bindings.py
"""

from __future__ import annotations

import unittest

import galley


class ModuleSurfaceTests(unittest.TestCase):
    def test_version_returns_non_empty_string(self):
        self.assertIsInstance(galley.version(), str)
        self.assertNotEqual(galley.version(), "")

    def test_parser_metadata_flags_are_consistent(self):
        self.assertIn(
            galley.parser_type(), (galley.PARSER_TYPE_LL, galley.PARSER_TYPE_LR)
        )
        self.assertTrue(galley.has_ast())
        self.assertIsInstance(galley.has_procedures(), bool)
        self.assertIsInstance(galley.allows_no_ast_tree_procedures(), bool)
        self.assertIsInstance(galley.source_retention_enabled(), bool)
        self.assertIsInstance(galley.has_position_tracking(), bool)
        self.assertIsInstance(galley.has_input_streaming(), bool)
        self.assertIsInstance(galley.uses_verbatim(), bool)
        self.assertIsInstance(galley.stack_overflow_recovery_available(), bool)
        self.assertIn(
            galley.error_recovery_mode(),
            (
                galley.RECOVERY_MODE_DISABLED,
                galley.RECOVERY_MODE_AUTOMATIC,
                galley.RECOVERY_MODE_EXPLICIT,
            ),
        )

    def test_status_string_renders_known_codes(self):
        rendered = galley.status_string(-2)
        self.assertIsInstance(rendered, str)
        assert rendered is not None
        self.assertIn("syntax", rendered.lower())
        self.assertIsNone(galley.status_string(999999))

    def test_diagnostic_type_is_not_directly_constructible(self):
        with self.assertRaises(TypeError):
            galley.Diagnostic()

    def test_error_class_survives_procedures_importing_galley(self):
        # procedures.py does `import galley` while the extension auto-loads
        # it during PyInit_galley. That must be the same module, or
        # `except galley.Error` misses parse failures.
        import procedures

        self.assertIs(procedures.galley.Error, galley.Error)
        with galley.Session() as session:
            with self.assertRaises(galley.Error) as raised:
                session.parse("alpha:")
            self.assertIs(type(raised.exception), galley.Error)


class SessionTests(unittest.TestCase):
    session: galley.Session

    def setUp(self) -> None:
        self.session = galley.Session(max_errors=10)

    def tearDown(self) -> None:
        self.session.close()

    def test_procedure_hook_can_read_node_text(self) -> None:
        seen: list[bytes] = []

        def reduction_Pair(args: galley.ProcedureArguments) -> None:
            node = args.current_node()
            self.assertIsNotNone(node)
            assert node is not None
            self.assertIs(args.session, self.session)
            text = node.text()
            self.assertIsInstance(text, bytes)
            assert text is not None
            self.assertGreater(len(text), 0)
            seen.append(text)

        galley.install_procedure("reduction_Pair", reduction_Pair)
        try:
            self.session.parse("alpha:12,beta:3")
        finally:
            galley.clear_procedures()
        self.assertEqual(len(seen), 2)

    def test_parse_accepts_str_bytes_and_buffers(self):
        sample = "alpha:12,beta:3"
        parsed_str = self.session.parse(sample)
        self.assertEqual(parsed_str, len(sample))
        self.assertEqual(self.session.parse(sample.encode()), len(sample))
        self.assertEqual(self.session.parse(bytearray(sample.encode())), len(sample))
        self.assertEqual(self.session.parse(memoryview(sample.encode())), len(sample))

    def test_parse_sentinel_matches_parse_for_nul_free_input(self):
        sample = "alpha:12,beta:3"
        sentinel = self.session.parse_sentinel(sample)
        direct = self.session.parse(sample)
        self.assertEqual(sentinel, direct)

    def test_parse_sentinel_rejects_other_types(self):
        with self.assertRaises(TypeError):
            self.session.parse_sentinel(bytearray(b"alpha:12"))

    def test_syntax_error_raises_error_with_code_and_diagnostic(self):
        diagnostic: galley.Diagnostic | None = None
        try:
            self.session.parse("alpha:")
        except galley.Error as error:
            self.assertEqual(error.code, -2)  # galley_error_syntax
            diagnostic = error.diagnostic
        else:
            self.fail("expected the broken sample to raise")
        self.assertTrue(self.session.has_diagnostic())
        self.assertIsNotNone(self.session.diagnostic())
        self.assertIsNotNone(diagnostic)
        assert diagnostic is not None
        self.assertEqual(diagnostic.kind, galley.KIND_SYNTAX)
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
        session = galley.Session()
        try:
            with self.assertRaises(galley.Error):
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


class WalkTests(unittest.TestCase):
    session: galley.Session

    def setUp(self) -> None:
        self.session = galley.Session()
        self.session.parse("alpha:12,beta:3")

    def tearDown(self) -> None:
        self.session.close()

    def test_root_and_navigation_links(self) -> None:
        root = self.session.root_node()
        self.assertIsNotNone(root)
        assert root is not None
        self.assertTrue(self.session.node_valid(root))
        self.assertIsNone(self.session.parent(root))
        self.assertFalse(self.session.node_valid(0xFFFFFFFFFFFFFFFF))

        first = self.session.first_child(root)
        last = self.session.last_child(root)
        self.assertIsNotNone(first)
        self.assertIsNotNone(last)
        assert first is not None
        assert last is not None
        self.assertIsNone(self.session.next_sibling(last))
        self.assertIsNone(self.session.prior_sibling(first))
        self.assertEqual(self.session.parent(first), root)

        visited: list[galley.Node] = []
        child = first
        while child is not None:
            visited.append(child)
            child = self.session.next_sibling(child)
        self.assertEqual(len(visited), self.session.child_count(root))

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
        def contains_terminal_only(node: galley.Node) -> galley.Node | None:
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
        invalid = 0xFFFFFFFFFFFFFFFF
        self.assertIsNone(self.session.symbol_name(invalid))
        self.assertIsNone(self.session.text(invalid))
        self.assertIsNone(self.session.span(invalid))
        self.assertIsNone(self.session.line_column(invalid))
        self.assertIsNone(self.session.variable_index(invalid))
        self.assertEqual(self.session.child_count(invalid), 0)


class EditTests(unittest.TestCase):
    session: galley.Session
    root: galley.Node

    def setUp(self) -> None:
        self.session = galley.Session()
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
        active: list[galley.Node] = []
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
    session: galley.Session

    def setUp(self) -> None:
        self.session = galley.Session()

    def tearDown(self) -> None:
        self.session.close()

    def test_symbol_and_variable_tables(self):
        self.assertGreater(galley.symbol_count(), 0)
        self.assertGreater(galley.variable_count(), 0)
        first_name = self.session.symbol_name_at(0)
        self.assertIsInstance(first_name, bytes)
        self.assertIsInstance(self.session.symbol_is_terminal(0), bool)
        variable_name = self.session.variable_name_at(0)
        self.assertIsInstance(variable_name, bytes)
        self.assertIsNone(self.session.symbol_name_at(10**9))
        self.assertIsNone(self.session.variable_name_at(10**9))


class ReservationTests(unittest.TestCase):
    def test_reserve_and_report_capacity(self):
        session = galley.Session()
        try:
            capacity = session.node_capacity()
            session.reserve_nodes(capacity + 1024)
            self.assertGreaterEqual(session.node_capacity(), capacity + 1024)
        finally:
            session.close()


class LifetimeTests(unittest.TestCase):
    def test_close_is_idempotent_and_closed_sessions_raise(self):
        session = galley.Session()
        session.parse("alpha:12")
        session.close()
        session.close()
        with self.assertRaises(ValueError):
            session.parse("alpha:12")
        with self.assertRaises(ValueError):
            session.root_node()

    def test_context_manager_closes_session(self):
        with galley.Session() as session:
            self.assertGreater(session.parse("alpha:12"), 0)
        with self.assertRaises(ValueError):
            session.parse("alpha:12")

    def test_options_round_trip(self):
        session = galley.Session(
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
