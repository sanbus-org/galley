import importlib.util
import io
import os
import pathlib
import sys
import unittest
from unittest import mock


SCRIPT_PATH = pathlib.Path(__file__).with_name("benchmark.py")
SPEC = importlib.util.spec_from_file_location("galley_benchmark", SCRIPT_PATH)
benchmark = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = benchmark
SPEC.loader.exec_module(benchmark)


class ProgressFormattingTests(unittest.TestCase):
    def test_wide_progress_includes_bar_global_count_suite_and_card_count(self):
        line = benchmark.format_progress_line(
            completed=18,
            total=42,
            suite_label="JSON · No AST · 2^16 · API",
            card_index=2,
            card_total=4,
            terminal_width=120,
        )

        self.assertIn("Global [", line)
        self.assertIn("] 18/42 (42%)", line)
        self.assertIn("JSON · No AST · 2^16 · API", line)
        self.assertTrue(line.endswith("Card 2/4"))
        self.assertLessEqual(len(line), 120)

    def test_narrow_progress_degrades_to_bounded_counters(self):
        line = benchmark.format_progress_line(
            completed=18,
            total=42,
            suite_label="JSON · No AST · 2^16 · API",
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
            ast_mode="no-ast",
            input_size_dir="size16",
            term_ast="no-ast-for-terminals",
            input_size=16,
            procedures_enabled=False,
            variant_name="no-ast-no-procedures-size16",
        )
        suite = benchmark.BenchmarkSuite(
            name="json",
            variant=variant,
            cards=(
                benchmark.BenchmarkCard("small", "LL", 2, None, None),
                benchmark.BenchmarkCard(
                    "large", "LL", 2**16, ">= 2^16", "input size limit"
                ),
            ),
        )

        self.assertEqual(1, suite.runnable_count)
        self.assertEqual(2, len(suite.cards))
        line = benchmark.format_progress_line(
            completed=suite.runnable_count,
            total=suite.runnable_count,
            suite_label=benchmark.suite_progress_label(suite, "api"),
            card_index=len(suite.cards),
            card_total=len(suite.cards),
            terminal_width=100,
        )
        self.assertIn("1/1 (100%)", line)
        self.assertTrue(line.endswith("Card 2/2"))


class InteractiveProgressTests(unittest.TestCase):
    def test_updates_overwrite_reserved_bottom_line_without_newlines(self):
        output = io.StringIO()
        with mock.patch.object(
            benchmark.shutil,
            "get_terminal_size",
            return_value=os.terminal_size((100, 24)),
        ), mock.patch.object(sys, "stdout", output):
            progress = benchmark.GlobalProgress(total=2, enabled=True)
            progress.begin_card("JSON · No AST · API", 1, 2)
            progress.complete_card()
            progress.clear()

        rendered = output.getvalue()
        self.assertEqual(1, rendered.count("\033[1;23r"))
        self.assertEqual(2, rendered.count("\033[24;1H\033[2KGlobal "))
        self.assertEqual(2, rendered.count("\n"))
        self.assertTrue(rendered.endswith("\033[24;1H\n"))
        self.assertFalse(progress.active)

    def test_finish_leaves_completed_line_then_restores_terminal(self):
        output = io.StringIO()
        with mock.patch.object(
            benchmark.shutil,
            "get_terminal_size",
            return_value=os.terminal_size((100, 24)),
        ), mock.patch.object(sys, "stdout", output):
            progress = benchmark.GlobalProgress(total=3, enabled=True)
            progress.begin_card("JSON · No AST · API", 3, 3)
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
        with mock.patch.object(
            benchmark.shutil, "get_terminal_size", side_effect=terminal_sizes
        ), mock.patch.object(sys, "stdout", output):
            progress = benchmark.GlobalProgress(total=1, enabled=True)
            progress.begin_card("JSON · No AST · API", 1, 1)

        rendered = output.getvalue()
        self.assertIn("\033[1;23r", rendered)
        self.assertIn("\0337\033[1;19r\0338", rendered)
        self.assertIn("\033[20;1H\033[2KGlobal ", rendered)


if __name__ == "__main__":
    unittest.main()
