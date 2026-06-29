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

features:
  - icon: 🚀
    title: LL(k) and LR/LALR Engines
    details: Generate top-down LL(k) recursive-descent or bottom-up LR/LALR recursive-ascent parsers from a single grammar.
  - icon: ⚡
    title: Scannerless Parsing
    details: Parse directly from character streams to ASTs without a separate tokenization phase. Merges lexical and syntactic analysis.
  - icon: 🛠️
    title: Native Zig Code
    details: Emits clean, dependency-free Zig source code that integrates into standard build.zig pipelines.
---

<style>
@media (min-width: 640px) {
  .VPHero .text {
    font-size: 48px;
  }
}
</style>
