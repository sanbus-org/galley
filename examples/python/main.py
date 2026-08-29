#!/usr/bin/env python3
"""Parses a small key/value document through the Galley Python bindings,
mirroring examples/c, examples/cpp, examples/rust, and examples/go
byte-for-byte in output."""

import sys

import galley

VALID_SAMPLE = "alpha:12,beta:3"
BROKEN_SAMPLE = "alpha:"
SAMPLE_PATH = "/tmp/galley-python-example.json"


def print_tree(node, depth):
    """Prints one node and recurses into its children."""
    name = node.symbol_name()
    text = node.text()
    if name is None or text is None:
        raise SystemExit(1)
    line = 0
    position = node.line_column()
    if position is not None:
        line = position[0]
    print("  " * depth + f"{name.decode()} [line {line}, {len(text)} bytes]")
    for child in node:
        print_tree(child, depth + 1)


def main():
    print(f"galley version: {galley.version()}")
    try:
        # max_errors is explicit; zero would select the same default.
        session = galley.Session(max_errors=10)
    except galley.Error:
        print("failed to create a parser session", file=sys.stderr)
        return 1
    with session:
        try:
            session.set_message_override(
                "Number", "expected a number after ':' (digits only) at line {line}"
            )
        except galley.Error:
            print("failed to register the message override", file=sys.stderr)
            return 1

        # With a path argument: parse the file and nothing else.
        arguments = sys.argv[1:]
        if len(arguments) > 0:
            try:
                parsed = session.parse_file(arguments[0])
            except galley.Error as error:
                diagnostic = error.diagnostic
                line = diagnostic.line if diagnostic else 0
                column = diagnostic.column if diagnostic else 0
                message = diagnostic.message if diagnostic else ""
                print(f"{arguments[0]}:{line}:{column}: {message}", file=sys.stderr)
                return 1
            print(f"parsed {parsed} bytes")
            return 0

        # Successful parse: walk the tree.
        try:
            parsed = session.parse_sentinel(VALID_SAMPLE)
        except galley.Error as error:
            print(f"unexpected failure: {error} ({error.code})", file=sys.stderr)
            return 1
        print(f"parsed {parsed} bytes, {session.node_count()} AST nodes")
        if not galley.has_ast():
            print("AST construction disabled; skipping tree walk")
        else:
            root = session.root_node()
            if root is not None:
                print_tree(root, 1)

        # Failed parse: inspect the diagnostic.
        try:
            session.parse_sentinel(BROKEN_SAMPLE)
            print("expected the broken sample to fail", file=sys.stderr)
            return 1
        except galley.Error as error:
            diagnostic = error.diagnostic
        if diagnostic is None:
            print("expected a diagnostic for the broken sample", file=sys.stderr)
            return 1
        print(
            f"diagnostic at {diagnostic.line}:{diagnostic.column}: {diagnostic.message}"
        )

        expected = "expected one of: "
        for index, token in enumerate(diagnostic.expected_tokens):
            if index != 0:
                expected += ", "
            expected += f"'{token.decode()}'"
        print(expected)

        context = "while parsing (innermost first):"
        for name in diagnostic.context:
            context += f" {name}"
        print(context)

        # Multi-error parse: every recorded diagnostic stays addressable.
        try:
            session.parse_sentinel("alpha:13x,beta:,gamma:q")
            print("expected the multi-error sample to fail", file=sys.stderr)
            return 1
        except galley.Error:
            pass
        recorded = session.diagnostics()
        print(f"recorded diagnostics: {len(recorded)}")
        for index, diag in enumerate(recorded):
            kind_name = (
                "syntax"
                if diag.kind == galley.KIND_SYNTAX
                else "indentation"
                if diag.kind == galley.KIND_INDENTATION
                else "none"
            )
            unexpected = diag.unexpected_token.decode() if diag.unexpected_token else ""
            print(
                f"  [{index}] {kind_name} at {diag.line}:{diag.column} near '{unexpected}'"
            )

        # File parsing.
        try:
            with open(SAMPLE_PATH, "wb") as file:
                file.write(VALID_SAMPLE.encode())
        except OSError:
            print(f"failed to write {SAMPLE_PATH}", file=sys.stderr)
            return 1
        try:
            parsed = session.parse_file(SAMPLE_PATH)
        except galley.Error as error:
            print(f"file parse failed: {error} ({error.code})", file=sys.stderr)
            return 1
        end_line, end_column = session.last_position()
        print(f"file parse: {parsed} bytes, ended at {end_line}:{end_column}")

        # Tree editing: detach the root's children, then reattach them.
        if galley.has_ast():
            root = session.root_node()
            if root is None:
                print("expected the root to have children", file=sys.stderr)
                return 1
            children_before = len(root)
            head = root.clean_children()
            if head is None:
                print("expected the root to have children", file=sys.stderr)
                return 1
            root.append_children(head)
            print(
                f"tree edit: {children_before} children before, {len(root)} after reattach"
            )

        return 0


if __name__ == "__main__":
    raise SystemExit(main())
