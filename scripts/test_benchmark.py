import importlib.util
import itertools
import io
import os
import pathlib
import sys
import unittest
from types import SimpleNamespace
from unittest import mock

SCRIPT_PATH = pathlib.Path(__file__).with_name("benchmark.py")
SPEC = importlib.util.spec_from_file_location("galley_benchmark", SCRIPT_PATH)
benchmark = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = benchmark
SPEC.loader.exec_module(benchmark)


class ProgressFormattingTests(unittest.TestCase):
    def test_wide_progress_includes_bar_total_count_suite_and_card_count(self):
        line = benchmark.format_progress_line(
            completed=18,
            total=42,
            suite_label="JSON · No AST",
            card_index=2,
            card_total=4,
            terminal_width=120,
        )

        self.assertIn("Total [", line)
        self.assertIn("] 18/42 (42%)", line)
        self.assertIn("JSON · No AST", line)
        self.assertTrue(line.endswith("Card 2/4"))
        self.assertLessEqual(len(line), 120)

    def test_narrow_progress_degrades_to_bounded_counters(self):
        line = benchmark.format_progress_line(
            completed=18,
            total=42,
            suite_label="JSON · No AST",
            card_index=2,
            card_total=4,
            terminal_width=18,
        )

        self.assertNotIn("█", line)
        self.assertNotIn("░", line)
        self.assertLessEqual(len(line), 18)
        self.assertIn("18/42", line)

    def test_skipped_cards_stay_in_suite_total_but_not_global_total(self):
        variant = benchmark.BenchmarkVariant(
            ast=False,
            procedures=False,
            term_ast="no-ast-for-terminals",
        )
        suite = benchmark.BenchmarkSuite(
            name="json",
            variant=variant,
            cards=(
                benchmark.BenchmarkCard("small", "LL", 2, None, None),
                benchmark.BenchmarkCard(
                    "large", "LL", 2**16, "> 1 MB", "procedures enabled"
                ),
            ),
        )

        self.assertEqual(1, suite.runnable_count)
        self.assertEqual(2, len(suite.cards))
        line = benchmark.format_progress_line(
            completed=suite.runnable_count,
            total=suite.runnable_count,
            suite_label=benchmark.suite_progress_label(suite),
            card_index=len(suite.cards),
            card_total=len(suite.cards),
            terminal_width=100,
        )
        self.assertIn("1/1 (100%)", line)
        self.assertTrue(line.endswith("Card 2/2"))


class BenchmarkPlanningTests(unittest.TestCase):
    @staticmethod
    def args(**overrides):
        values = {
            "no_ast": False,
            "with_ast": False,
            "ast_for_terminals": False,
            "no_ast_for_terminals": False,
            "parser_type": None,
        }
        values.update(overrides)
        return SimpleNamespace(**values)

    def test_default_matrix_covers_ast_and_no_ast_without_procedures(self):
        configurations = []
        benchmark.run_all_modes(
            lambda gen_opts, _: configurations.append(tuple(gen_opts)), self.args()
        )

        self.assertEqual(
            [
                ("--no-ast", "--no-ast-for-terminals"),
                ("--with-ast", "--no-ast-for-terminals"),
            ],
            configurations,
        )
        self.assertFalse(
            any("--with-procedures" in options for options in configurations)
        )

    def test_ast_mode_flags_restrict_the_matrix(self):
        no_ast = []
        benchmark.run_all_modes(
            lambda gen_opts, _: no_ast.append(tuple(gen_opts)),
            self.args(no_ast=True),
        )
        self.assertEqual(
            [("--no-ast", "--no-ast-for-terminals")],
            no_ast,
        )

        with_ast = []
        benchmark.run_all_modes(
            lambda gen_opts, _: with_ast.append(tuple(gen_opts)),
            self.args(with_ast=True),
        )
        self.assertEqual(
            [
                ("--with-ast", "--no-ast-for-terminals"),
            ],
            with_ast,
        )

    def test_explicit_inputs_replace_language_samples(self):
        inputs = ["custom/first.input", "custom/second.input"]
        with (
            mock.patch.object(
                benchmark, "get_parser_types_for_language", return_value=["LL"]
            ),
            mock.patch.object(
                benchmark,
                "sample_inputs",
                side_effect=AssertionError("samples consulted"),
            ),
        ):
            suite = benchmark.prepare_benchmark_suite(
                "custom",
                ["--no-ast", "--no-ast-for-terminals"],
                self.args(),
                inputs,
            )

        self.assertEqual(inputs, [card.input_file for card in suite.cards])


class ProcedureVariantTests(unittest.TestCase):
    def test_with_procedures_adds_procedures_to_the_ast_variant_only(self):
        self.assertEqual(
            ["--with-ast", "--no-ast-for-terminals", "--with-procedures"],
            benchmark.with_procedures(["--with-ast", "--no-ast-for-terminals"]),
        )
        self.assertEqual(
            ["--no-ast", "--no-ast-for-terminals"],
            benchmark.with_procedures(["--no-ast", "--no-ast-for-terminals"]),
        )

    def test_ast_and_procedures_are_independent_settings(self):
        for ast_option, procedures_option in itertools.product(
            ("--no-ast", "--with-ast"), ([], ["--with-procedures"])
        ):
            variant = benchmark.benchmark_variant(
                [ast_option, *procedures_option, "--no-ast-for-terminals"]
            )

            self.assertEqual(ast_option == "--with-ast", variant.ast)
            self.assertEqual(bool(procedures_option), variant.procedures)
            self.assertIn(f"-Dast={str(variant.ast).lower()}", variant.config_flags)
            self.assertIn(
                f"-Dprocedures={str(variant.procedures).lower()}",
                variant.config_flags,
            )

    def test_variant_names_are_the_result_path_levels(self):
        variant = benchmark.BenchmarkVariant(
            ast=True, procedures=False, term_ast="no-ast-for-terminals"
        )
        self.assertEqual(("ast", "no-procedures"), (variant.ast_name, variant.procedures_name))
        variant = benchmark.BenchmarkVariant(
            ast=False, procedures=True, term_ast="no-ast-for-terminals"
        )
        self.assertEqual(("no-ast", "procedures"), (variant.ast_name, variant.procedures_name))

    def test_details_state_both_settings_whether_on_or_off(self):
        details = {
            (ast, procedures): benchmark.BenchmarkVariant(
                ast=ast, procedures=procedures, term_ast="no-ast-for-terminals"
            ).details
            for ast, procedures in itertools.product((False, True), repeat=2)
        }

        self.assertEqual(["No AST", "No procedures"], details[(False, False)])
        self.assertEqual(["No AST", "Procedures"], details[(False, True)])
        self.assertEqual(["AST", "No procedures"], details[(True, False)])
        self.assertEqual(["AST", "Procedures"], details[(True, True)])

    def test_languages_with_procedures_plan_their_ast_variant_with_procedures(self):
        args = SimpleNamespace(parser_type=None)
        plans = {}
        with (
            mock.patch.object(
                benchmark, "get_parser_types_for_language", return_value=["LL"]
            ),
            mock.patch.object(benchmark, "sample_inputs", return_value=["sample"]),
        ):
            for name in ("python", "json"):
                for options in (
                    ["--with-ast", "--no-ast-for-terminals"],
                    ["--no-ast", "--no-ast-for-terminals"],
                ):
                    for inputs in (None, ["custom.input"]):
                        suite = benchmark.prepare_benchmark_suite(
                            name, options, args, inputs
                        )
                        plans.setdefault(name, []).append(
                            (suite.variant.ast, suite.variant.procedures)
                        )

        self.assertEqual(
            [(True, True), (True, True), (False, False), (False, False)],
            plans["python"],
        )
        self.assertEqual(
            [(True, False), (True, False), (False, False), (False, False)],
            plans["json"],
        )


class InteractiveProgressTests(unittest.TestCase):
    def test_updates_overwrite_reserved_bottom_line_without_newlines(self):
        output = io.StringIO()
        with (
            mock.patch.object(
                benchmark.shutil,
                "get_terminal_size",
                return_value=os.terminal_size((100, 24)),
            ),
            mock.patch.object(sys, "stdout", output),
        ):
            progress = benchmark.GlobalProgress(total=2, enabled=True)
            progress.begin_card("JSON · No AST", 1, 2)
            progress.complete_card()
            progress.clear()

        rendered = output.getvalue()
        self.assertEqual(1, rendered.count("\033[1;23r"))
        self.assertEqual(2, rendered.count("\033[24;1H\033[2KTotal "))
        self.assertEqual(2, rendered.count("\n"))
        self.assertTrue(rendered.endswith("\033[24;1H\n"))
        self.assertFalse(progress.active)

    def test_finish_leaves_completed_line_then_restores_terminal(self):
        output = io.StringIO()
        with (
            mock.patch.object(
                benchmark.shutil,
                "get_terminal_size",
                return_value=os.terminal_size((100, 24)),
            ),
            mock.patch.object(sys, "stdout", output),
        ):
            progress = benchmark.GlobalProgress(total=3, enabled=True)
            progress.begin_card("JSON · No AST", 3, 3)
            progress.finish()

        rendered = output.getvalue()
        self.assertIn("3/3 (100%)", rendered)
        self.assertTrue(rendered.endswith("\033[r\033[24;1H\n"))
        self.assertFalse(progress.active)

    def test_terminal_resize_replaces_the_scrolling_region(self):
        output = io.StringIO()
        terminal_sizes = iter(
            (
                os.terminal_size((100, 24)),
                os.terminal_size((80, 20)),
            )
        )
        with (
            mock.patch.object(
                benchmark.shutil, "get_terminal_size", side_effect=terminal_sizes
            ),
            mock.patch.object(sys, "stdout", output),
        ):
            progress = benchmark.GlobalProgress(total=1, enabled=True)
            progress.begin_card("JSON · No AST", 1, 1)

        rendered = output.getvalue()
        self.assertIn("\033[1;23r", rendered)
        self.assertIn("\0337\033[1;19r\0338", rendered)
        self.assertIn("\033[20;1H\033[2KTotal ", rendered)


if __name__ == "__main__":
    unittest.main()
