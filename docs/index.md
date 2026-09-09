---
layout: home

hero:
  name: Galley
  text: |
    Directly encoded speed.
    Zero boilerplate.
  tagline: High-Performance parser generators for Zig
  actions:
    - theme: brand
      text: Getting Started
      link: /getting_started
    - theme: alt
      text: Grammar Guidelines
      link: /grammar_guidelines
    - theme: brand
      text: Try it live
      link: /try-it

features:
  - icon: 🚀
    title: LL(k) and LR/LALR Engines
    details: Generate top-down LL(k) recursive-descent or bottom-up LR/LALR recursive-ascent parsers from a single grammar.
  - icon: ⚡
    title: Scannerless Parsing
    details: Parse directly from character streams to ASTs without a separate tokenization phase. Merges lexical and syntactic analysis.
  - icon: 🛠️
    title: Native Zig Code
    details: Emits clean Zig parser source. Consume it with addParserModule in the application's build.zig.
---

## Try it live

Four live parsers in your browser — parsing runs locally in WebAssembly,
nothing is uploaded. Type below or drop in a file.

<ClientOnly>
  <TryIt />
</ClientOnly>

<script setup>
import TryIt from './.vitepress/components/TryIt.vue'
</script>

<style>
@media (min-width: 640px) {
  .VPHero .text {
    font-size: 48px;
  }
}
</style>
