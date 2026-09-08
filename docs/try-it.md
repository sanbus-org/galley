# Try it

Three live parsers in your browser: JSON, Lisp, and Lua. Type below or
drop in a file — parsing runs locally in WebAssembly, nothing is
uploaded. The JSON tab counts values two ways: hooks that fire during
the parse, or one AST snapshot plus a host walk — pick either and
compare parse time against time-to-totals. Try real files: the
[JSON samples](https://github.com/sanbus-org/galley/tree/main/languages/json/samples),
[Lisp samples](https://github.com/sanbus-org/galley/tree/main/languages/lisp/samples)
and [Lua samples](https://github.com/sanbus-org/galley/tree/main/languages/lua/samples)
in this repo, or the [datasets](https://github.com/sanbus-org/parser-benchmark/tree/main/datasets)
(twitter, github events, canada, …) in the benchmark repo.

<ClientOnly>
  <TryIt />
</ClientOnly>

<script setup>
import TryIt from './.vitepress/components/TryIt.vue'
</script>
