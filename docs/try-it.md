# Try it

Four live parsers in your browser: JSON, Lisp, Lua, and Galley
itself. Type below or
drop in a file — parsing runs locally in WebAssembly, nothing is
uploaded. The JSON tab measures four ways: a raw parse, hooks that
fire during the parse, the AST snapshot materialized, or the snapshot
walked to totals — one row shows what the chosen workload costs, once
or across a run count. Raw and Hooks run one build, so the gap between
them is the hooks alone; the AST buttons run the build that constructs
a tree as it parses. Try real files: the
[JSON samples](https://github.com/sanbus-org/galley/tree/main/languages/json/samples),
[Lisp samples](https://github.com/sanbus-org/galley/tree/main/languages/lisp/samples),
[Lua samples](https://github.com/sanbus-org/galley/tree/main/languages/lua/samples)
and [Galley samples](https://github.com/sanbus-org/galley/tree/main/languages/galley/samples)
in this repo, or the [datasets](https://github.com/sanbus-org/parser-benchmark/tree/main/datasets)
(twitter, github events, canada, …) in the benchmark repo.

<ClientOnly>
  <TryIt />
</ClientOnly>

<script setup>
import TryIt from './.vitepress/components/TryIt.vue'
</script>
