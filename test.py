# Written by Gemini 3.5 Flash (High)
#!/usr/bin/env python3
import argparse
import os
import shlex
import subprocess
import sys

# Global environment generator command
GENERATOR_COMMAND = os.environ.get(
    "GENERATOR_COMMAND",
    "uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/",
)


def parse_zig_output(stdout_str):
    """
    Parses key-value metric lines from the zig build output.
    """
    metrics = {}
    for line in stdout_str.splitlines():
        line = line.strip()
        if ":" in line:
            key, val = line.split(":", 1)
            metrics[key.strip()] = val.strip()
    return metrics


def format_card(name, metrics, width=34, no_color=False, error_msg=None):
    """
    Formats a single benchmark result block into a list of strings representing card lines.
    """
    if no_color:
        RESET = ""
        BOLD = ""
        DIM = ""
        CYAN = ""
        GREEN = ""
        YELLOW = ""
        RED = ""
        GRAY = ""
        border_color = ""
    else:
        RESET = "\033[0m"
        BOLD = "\033[1m"
        DIM = "\033[2m"
        CYAN = "\033[36m"
        GREEN = "\033[32m"
        YELLOW = "\033[33m"
        RED = "\033[31m"
        GRAY = "\033[90m"
        border_color = GRAY

    TL, TR = "╭", "╮"
    BL, BR = "╰", "╯"
    HL, VL = "─", "│"
    SEP_L, SEP_R = "├", "┤"

    inner_width = width - 4  # Margins of 2 chars on each side: "│ " and " │"

    if error_msg:

        def make_centered_line(text_visible, text_styled):
            pad_total = inner_width - text_visible
            if pad_total < 0:
                pad_total = 0
            pad_left = pad_total // 2
            pad_right = pad_total - pad_left
            return f"{border_color}{VL}{RESET}{' ' * (pad_left + 1)}{text_styled}{' ' * (pad_right + 1)}{border_color}{VL}{RESET}"

        lines = []
        lines.append(f"{border_color}{TL}{HL * (width - 2)}{TR}{RESET}")

        name_display = name
        if len(name) > inner_width:
            name_display = "..." + name[-(inner_width - 3) :]
        name_styled = f"{BOLD}{CYAN}{name_display}{RESET}"
        lines.append(
            f"{border_color}{VL}{RESET} {name_styled}{' ' * (inner_width - len(name_display))} {border_color}{VL}{RESET}"
        )

        lines.append(f"{border_color}{SEP_L}{HL * (width - 2)}{SEP_R}{RESET}")
        lines.append(
            f"{border_color}{VL}{RESET}{' ' * (inner_width + 2)}{border_color}{VL}{RESET}"
        )

        skipped_visible = "SKIPPED (TOO LARGE)"
        skipped_styled = (
            f"{YELLOW}{BOLD}{skipped_visible}{RESET}"
            if not no_color
            else skipped_visible
        )
        lines.append(make_centered_line(len(skipped_visible), skipped_styled))

        msg_visible = error_msg
        msg_styled = f"{DIM}{msg_visible}{RESET}" if not no_color else msg_visible
        lines.append(make_centered_line(len(msg_visible), msg_styled))

        lines.append(
            f"{border_color}{VL}{RESET}{' ' * (inner_width + 2)}{border_color}{VL}{RESET}"
        )
        lines.append(f"{border_color}{BL}{HL * (width - 2)}{BR}{RESET}")
        return lines

    def make_line(label, value_styled, value_visible):
        label_visible = label + " "
        label_styled = f"{DIM}{label}{RESET} "

        total_visible = len(label_visible) + len(value_visible)
        pad_len = inner_width - total_visible
        if pad_len < 0:
            pad_len = 0

        return f"{border_color}{VL}{RESET} {label_styled}{value_styled}{' ' * pad_len} {border_color}{VL}{RESET}"

    lines = []

    # Top border
    lines.append(f"{border_color}{TL}{HL * (width - 2)}{TR}{RESET}")

    # Name line
    name_display = name
    if len(name) > inner_width:
        name_display = "..." + name[-(inner_width - 3) :]
    name_styled = f"{BOLD}{CYAN}{name_display}{RESET}"

    lines.append(
        f"{border_color}{VL}{RESET} {name_styled}{' ' * (inner_width - len(name_display))} {border_color}{VL}{RESET}"
    )

    # Separator
    lines.append(f"{border_color}{SEP_L}{HL * (width - 2)}{SEP_R}{RESET}")

    # Parse metrics
    parsed_bytes = metrics.get("Parsed bytes", "N/A")
    duration_raw = metrics.get("Duration", "N/A")
    throughput = metrics.get("Throughput", "N/A")
    nodes_alloc = metrics.get("Nodes allocated", "N/A")

    # Format Duration
    duration_str = duration_raw
    if "ns" in duration_raw:
        try:
            ns_val = int(duration_raw.replace("ns", "").replace(",", "").strip())
            if ns_val >= 1_000_000_000:
                duration_str = f"{ns_val / 1_000_000_000:.3f} s"
            elif ns_val >= 1_000_000:
                duration_str = f"{ns_val / 1_000_000:.2f} ms"
            elif ns_val >= 1_000:
                duration_str = f"{ns_val / 1_000:.1f} µs"
            else:
                duration_str = f"{ns_val} ns"
        except ValueError:
            pass

    bytes_styled = f"{BOLD}{parsed_bytes}{RESET}"
    duration_styled = f"{BOLD}{duration_str}{RESET}"
    throughput_styled = f"{BOLD}{throughput}{RESET}"

    # Highlight nodes allocated (0 is green, non-zero is yellow/orange)
    nodes_visible = str(nodes_alloc)
    try:
        nodes_num = int(nodes_alloc.replace(",", "").strip())
        if nodes_num == 0:
            nodes_styled = f"{GREEN}{nodes_visible}{RESET}"
        else:
            nodes_styled = f"{YELLOW}{BOLD}{nodes_visible}{RESET}"
    except ValueError:
        nodes_styled = f"{BOLD}{nodes_visible}{RESET}"

    lines.append(make_line("Parsed bytes:", bytes_styled, parsed_bytes))
    lines.append(make_line("Duration:", duration_styled, duration_str))
    lines.append(make_line("Throughput:", throughput_styled, throughput))
    lines.append(make_line("Nodes alloc:", nodes_styled, nodes_visible))

    # Bottom border
    lines.append(f"{border_color}{BL}{HL * (width - 2)}{BR}{RESET}")
    return lines


def get_terminal_cols(width, spacing=2):
    """
    Computes the maximum columns of cards that can fit in the terminal.
    """
    try:
        terminal_columns = os.get_terminal_size().columns
    except OSError:
        terminal_columns = 80
    cols = (terminal_columns + spacing) // (width + spacing)
    return max(1, cols)


def print_grid(cards, cols=None, spacing=2):
    """
    Renders multiple cards in a grid side-by-side.
    If cols is None, it is automatically calculated based on screen width.
    """
    if not cards:
        return
    if cols is None:
        import re

        ansi_escape = re.compile(r"\x1b\[[0-9;]*m")
        card_width = len(ansi_escape.sub("", cards[0][0]))
        cols = get_terminal_cols(card_width, spacing)
    for i in range(0, len(cards), cols):
        row_cards = cards[i : i + cols]
        num_lines = len(row_cards[0])
        for line_idx in range(num_lines):
            row_line = (" " * spacing).join(card[line_idx] for card in row_cards)
            print(row_line)
        print()


def draw_card_in_row(card_lines, col_idx, width=34, spacing=2):
    """
    Draws card_lines at the horizontal offset determined by col_idx,
    assuming the cursor is currently at the top-left of the row.
    """
    col_offset = col_idx * (width + spacing)
    for line_idx, line in enumerate(card_lines):
        move_down = f"\033[{line_idx}B" if line_idx > 0 else ""
        move_up = f"\033[{line_idx}A" if line_idx > 0 else ""
        move_to_col = f"\r\033[{col_offset}C" if col_offset > 0 else "\r"
        sys.stdout.write(f"{move_down}{move_to_col}{line}{move_up}")
    sys.stdout.flush()


def format_placeholder_card(name, width=34, no_color=False):
    """
    Formats a placeholder card with 'Running...' text.
    """
    if no_color:
        RESET = ""
        BOLD = ""
        DIM = ""
        CYAN = ""
        border_color = ""
    else:
        RESET = "\033[0m"
        BOLD = "\033[1m"
        DIM = "\033[2m"
        CYAN = "\033[36m"
        border_color = "\033[90m"

    TL, TR = "╭", "╮"
    BL, BR = "╰", "╯"
    HL, VL = "─", "│"
    SEP_L, SEP_R = "├", "┤"

    inner_width = width - 4

    lines = []
    lines.append(f"{border_color}{TL}{HL * (width - 2)}{TR}{RESET}")

    name_display = name
    if len(name) > inner_width:
        name_display = "..." + name[-(inner_width - 3) :]
    name_styled = f"{BOLD}{CYAN}{name_display}{RESET}"
    lines.append(
        f"{border_color}{VL}{RESET} {name_styled}{' ' * (inner_width - len(name_display))} {border_color}{VL}{RESET}"
    )

    lines.append(f"{border_color}{SEP_L}{HL * (width - 2)}{SEP_R}{RESET}")

    running_visible = "Running..."
    running_styled = f"{DIM}{running_visible}{RESET}"
    pad_len = inner_width - len(running_visible)
    lines.append(
        f"{border_color}{VL}{RESET} {running_styled}{' ' * pad_len} {border_color}{VL}{RESET}"
    )

    for _ in range(3):
        lines.append(
            f"{border_color}{VL}{RESET} {' ' * inner_width} {border_color}{VL}{RESET}"
        )

    lines.append(f"{border_color}{BL}{HL * (width - 2)}{BR}{RESET}")
    return lines


def run_benchmark_suite(name, parser_type, inputs, mode, gen_opts, args, target=None):
    """
    Runs parser generator and compiles/runs benchmarks for all input files.
    """
    if target is None:
        target = name
    # 1. Run parser generator command
    gen_command_str = f"{GENERATOR_COMMAND}{name}"
    cmd_args = (
        shlex.split(gen_command_str) + ["--parser-type", parser_type] + list(gen_opts)
    )

    try:
        subprocess.run(
            cmd_args,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        print(
            f"\n\033[31mError running parser generator command:\033[0m {' '.join(cmd_args)}"
        )
        print(f"\033[33mCommand Output:\033[0m\n{e.stdout}")
        sys.exit(1)

    # Extract input size from gen_opts (defaults to None if not specified)
    input_size = None
    if "--input-size" in gen_opts:
        try:
            size_idx = gen_opts.index("--input-size")
            input_size = int(gen_opts[size_idx + 1])
        except (ValueError, IndexError):
            pass

    RESET = "" if args.no_color else "\033[0m"
    BOLD = "" if args.no_color else "\033[1m"
    CYAN = "" if args.no_color else "\033[36m"
    MAGENTA = "" if args.no_color else "\033[35m"
    GRAY = "" if args.no_color else "\033[90m"

    if mode == "Debug":
        print(
            f"\n{GRAY}------------------------------------------------------------{RESET}"
        )
        print(
            f"{MAGENTA}{name}{RESET} --parser-type {CYAN}{parser_type}{RESET} {BOLD}{' '.join(gen_opts)}{RESET}"
        )
        print(
            f"{GRAY}------------------------------------------------------------{RESET}"
        )
        # Verification run in Debug mode
        for input_file in inputs:
            file_path = f"languages/{input_file}"
            if input_size is not None and os.path.exists(file_path):
                if os.path.getsize(file_path) >= (2**input_size):
                    continue

            cmd = [
                "zig",
                "build",
                "-Doptimize=Debug",
                target,
                "--",
                f"languages/{input_file}",
                "--verbosity",
                "0",
                "--iterations",
                "1",
            ]
            try:
                subprocess.run(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    check=True,
                )
            except subprocess.CalledProcessError as e:
                print(
                    f"\n\033[31mError building/running {target} in Debug mode for {input_file}:\033[0m"
                )
                print(f"\033[33mCommand Output:\033[0m\n{e.stdout}")
                sys.exit(1)
        return

    # ReleaseFast mode - print beautiful headers and cards grid

    # Determine if we should render interactively
    is_interactive = sys.stdout.isatty() and not args.no_color

    # Determine the number of columns to use dynamically
    cols = get_terminal_cols(args.width, spacing=2)

    for i in range(0, len(inputs), cols):
        row_inputs = inputs[i : i + cols]
        row_cards = []

        # If interactive, pre-allocate space for the row
        if is_interactive:
            for _ in range(8):
                print()
            sys.stdout.write("\033[8A\033[1G")
            sys.stdout.flush()

        for col_idx, input_file in enumerate(row_inputs):
            # Check if file size >= 2^input_size
            file_path = f"languages/{input_file}"
            is_too_large = False
            file_size = 0
            if os.path.exists(file_path):
                file_size = os.path.getsize(file_path)
                if input_size is not None and file_size >= (2**input_size):
                    is_too_large = True

            # Calculate iterations proportional to the input file size
            # Total parsed bytes target is ~100MB (100 * 1024 * 1024 bytes)
            target_bytes = 200 * 1024 * 1024
            if file_size > 0:
                iterations = max(1, int(target_bytes / file_size))
            else:
                iterations = 200000  # fallback

            # Render placeholder only when this specific card starts running and is not skipped
            if is_interactive and not is_too_large:
                placeholder = format_placeholder_card(
                    input_file, width=args.width, no_color=args.no_color
                )
                draw_card_in_row(placeholder, col_idx, width=args.width, spacing=2)

            if is_too_large:
                msg = f"Size >= 2^{input_size}"
                card_lines = format_card(
                    input_file,
                    {},
                    width=args.width,
                    no_color=args.no_color,
                    error_msg=msg,
                )
                if is_interactive:
                    draw_card_in_row(card_lines, col_idx, width=args.width, spacing=2)
                else:
                    row_cards.append(card_lines)
                continue

            cmd = [
                "zig",
                "build",
                "-Doptimize=ReleaseFast",
                target,
                "--",
                f"languages/{input_file}",
                "--verbosity",
                "0",
                "--iterations",
                str(iterations),
            ]

            try:
                result = subprocess.run(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    check=True,
                )
                metrics = parse_zig_output(result.stdout)
                card_lines = format_card(
                    input_file, metrics, width=args.width, no_color=args.no_color
                )

                if is_interactive:
                    draw_card_in_row(card_lines, col_idx, width=args.width, spacing=2)
                else:
                    row_cards.append(card_lines)
            except subprocess.CalledProcessError as e:
                if is_interactive:
                    sys.stdout.write("\033[8B\033[1G")
                    sys.stdout.flush()
                print(
                    f"\n\033[31mError running benchmark command for {input_file}:\033[0m"
                )
                print(f"\033[33mCommand Output:\033[0m\n{e.stdout}")
                sys.exit(1)

        if is_interactive:
            # Move cursor past the completed cards row
            sys.stdout.write("\033[8B\033[1G")
            print()  # Row separator space
            sys.stdout.flush()
        else:
            print_grid(row_cards, cols=cols)


def grammar_benchmark(mode, gen_opts, args):
    inputs = [
        "grammar/ll.grm",
        "grammar/lr.grm",
        "json/ll.grm",
        "test-ll/ll.grm",
        "test-ll1/ll.grm",
    ]
    run_benchmark_suite("grammar", "LL", inputs, mode, gen_opts, args)


def json_benchmark(mode, gen_opts, args):
    inputs = [
        "json/sample-code.json",
        "json/large-sample-code.json",
    ]
    run_benchmark_suite("json", "LL", inputs, mode, gen_opts, args)


def augmented_json_benchmark(mode, gen_opts, args):
    inputs = [
        "json/sample-code.json",
        "json/large-sample-code.json",
        "augmented-json/large-sample-code-interweaved.json",
    ]
    run_benchmark_suite("json", "LL", inputs, mode, gen_opts, args)


def test_ll_benchmark(mode, gen_opts, args):
    inputs = [
        "test-ll/sample-code",
        "test-ll/large-sample-code",
    ]
    run_benchmark_suite("test-ll", "LL", inputs, mode, gen_opts, args)


def test_ll1_benchmark(mode, gen_opts, args):
    inputs = [
        "test-ll1/sample-code",
    ]
    run_benchmark_suite("test-ll1", "LL", inputs, mode, gen_opts, args)


def run_all_modes(benchmark_fn, args):
    """
    Iterates through all feature modes, input sizes, and optimize modes.
    """
    ast_modes = ["--no-ast", "--no-procedures"]
    sizes = [16, 32]
    term_asts = ["--no-ast-for-terminals", "--ast-for-terminals"]
    modes = ["Debug", "ReleaseFast"]

    for ast_mode in ast_modes:
        for size in sizes:
            for term_ast in term_asts:
                if ast_mode == "--no-ast" and term_ast == "--ast-for-terminals":
                    continue
                for mode in modes:
                    benchmark_fn(
                        mode, [ast_mode, "--input-size", str(size), term_ast], args
                    )


BENCHMARKS = {
    "grammar": grammar_benchmark,
    "augmented-json": augmented_json_benchmark,
    "json": json_benchmark,
    "test-ll": test_ll_benchmark,
    "test-ll1": test_ll1_benchmark,
}


def main():
    parser = argparse.ArgumentParser(
        description="Parser Generator Benchmarking Grid Runner"
    )
    parser.add_argument(
        "--width",
        type=int,
        default=28,
        help="Width of each card in characters (default: 28)",
    )
    parser.add_argument(
        "--no-color",
        action="store_true",
        help="Disable colored output and progress carriage returns",
    )
    parser.add_argument(
        "--benchmark",
        choices=list(BENCHMARKS.keys()),
        default="grammar",
        help="Benchmark to run (default: grammar)",
    )

    args = parser.parse_args()

    benchmark_fn = BENCHMARKS[args.benchmark]

    try:
        run_all_modes(benchmark_fn, args)
    except KeyboardInterrupt:
        print("\n\033[31mBenchmark suite cancelled by user.\033[0m")
        sys.exit(1)


if __name__ == "__main__":
    main()
