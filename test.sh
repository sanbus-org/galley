#!/usr/bin/env bash
set -euo pipefail

GENERATOR_COMMAND="${GENERATOR_COMMAND:-"uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/"}"

grammar_benchmark() {
  local gen_command="${GENERATOR_COMMAND}grammar"
  local mode=$1
  local iterations=$([ "$mode" = "Debug" ] && echo "1" || echo "200000")
  shift
  local gen_opts=("$@")
  local print_command

  $gen_command --parser-type LL "${gen_opts[@]}"

  if [ "$mode" = "Debug" ]; then
    print_command=":"
  else
    print_command="echo"
  fi

  $print_command "--------------------"
  $print_command -e "grammar --parser-type LL \e[1m${gen_opts[*]}\e[0m"

  for input in "grammar/ll.grm" "grammar/lr.grm" "json/ll.grm" "sanbus-logic/lr.grm" "test-ll/ll.grm" "test-ll1/ll.grm"; do
    $print_command -e "-----"
    $print_command -e "\e[3m${input}\e[0m"
    zig build -Doptimize=$mode grammar -- languages/$input --verbosity 0 --iterations $iterations
  done
}

run_all_modes() {
  local benchmark_fn="$1"

  for ast_mode in "--no-ast" "--no-procedures"; do
    for size in 16 32; do
      for term_ast in "--ast-for-terminals" "--no-ast-for-terminals"; do
        for mode in "Debug" "ReleaseFast"; do
          "$benchmark_fn" "$mode" "$ast_mode" "--input-size" "$size" "$term_ast"
        done
      done
    done
  done
}

run_all_modes grammar_benchmark

# # printf "\ngrammar (lr)\n--------------------\n"
# # uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/grammar --parser-type LR
# # printf "\ngrammar/ll.grm\n"
# # zig build -Doptimize=ReleaseFast grammar -- languages/grammar/ll.grm --verbosity 0 --iterations 2000
# # printf "\ngrammar/lr.grm\n"
# # zig build -Doptimize=ReleaseFast grammar -- languages/grammar/lr.grm --verbosity 0 --iterations 2000
# # printf "\njson/ll.grm\n"
# # zig build -Doptimize=ReleaseFast grammar -- languages/json/ll.grm --verbosity 0 --iterations 2000
# # printf "\nsanbus-logic/lr.grm\n"
# # zig build -Doptimize=ReleaseFast grammar -- languages/sanbus-logic/lr.grm --verbosity 0 --iterations 1000
# # printf "\ntest-ll/ll.grm\n"
# # zig build -Doptimize=ReleaseFast grammar -- languages/test-ll/ll.grm --verbosity 0 --iterations 1000
# # printf "\ntest-ll1/ll.grm\n"
# # zig build -Doptimize=ReleaseFast grammar -- languages/test-ll1/ll.grm --verbosity 0 --iterations 1000
#
# # printf "\nsanbus\n--------------------\n"
# # uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/sanbus-logic --parser-type LR
# # printf "\ntodo.lgc\n"
# # zig build -Doptimize=ReleaseFast sanbus-logic -- ../tests/reducer/todo.lgc --verbosity 0 --iterations 2000
#
# printf "\ntest-ll\n--------------------\n"
# uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/test-ll --parser-type LL
# printf "\nsample-code\n"
# zig build -Doptimize=ReleaseFast test-ll -- languages/test-ll/sample-code --verbosity 0 --iterations 200000
# printf "\nlarge-sample-code\n"
# zig build -Doptimize=ReleaseFast test-ll -- languages/test-ll/large-sample-code --verbosity 0 --iterations 2000
#
# printf "\ntest-ll1\n--------------------\n"
# uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/test-ll1 --parser-type LL
# printf "\nsample-code\n"
# zig build -Doptimize=ReleaseFast test-ll1 -- languages/test-ll1/sample-code --verbosity 0 --iterations 2000
