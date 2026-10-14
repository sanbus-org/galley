# Languages

Each directory here is one language: a grammar (`ll.grm`, `lr.grm` or both), a `config.zig`, optional procedures and error messages, and a `samples/` directory.

## Every change to a language shows up in its samples

A change to a language is not done until its `samples/` files show it, in the same commit. That covers a new construct, a fixed bug and a removed limitation alike. A grammar change with no sample change is incomplete.

Samples are what the benchmarks parse, what the documentation links to, and what the next person reads to learn what the grammar accepts. A construct that no sample shows is untested in practice and invisible to the next reader.

When you change a language:

1. Add the construct to each sample file under a short comment that says what it demonstrates. Keep the existing content, so the benchmark history stays comparable apart from the new section.
2. Parse every sample with the changed grammar before committing: `zig build -Doptimize=ReleaseFast run-ll-<language> -- languages/<language>/samples/<file> --iterations 1`.
3. If the grammar's header comment lists the thing you fixed as a limitation, delete it from the list. If your change adds a rule that editors must know, put it in that header.
4. Update any copy of the grammar. `docs/try-it/lang/python/ll.grm` mirrors `languages/python/ll.grm` apart from its `@count` hooks.

Samples are benchmark inputs, so adding to them changes the throughput that benchmarks report for that language. Say so in the commit message.
