# Shared binding test-fixture grammar

The one keyvalue grammar (`ll.grm`) and generation options
(`config.zig`) every binding test suite parses. Each binding's fixture
directory links these two files in and adds its own `procedures.*`
(they are genuinely different files — one per host language):

- `bindings/c/test-fixture/`
- `bindings/go/testfixture/`
- `bindings/python/test_fixture/`
- `bindings/java/test-fixture/`
- `bindings/rust/test-fixture/`
- `bindings/js/test-fixture/`

Edit these two files and every binding suite picks the change up on
its next run. The bindings-consistency CI job enforces that the links
stay links.

## Second grammar

`second/` holds a second small grammar (plus-separated words, with its own
hook list) and links the same `config.zig`. The concurrency suites build it
beside the keyvalue grammar, so two different parsers run side by side, two
sessions each, on four threads:

- `bindings/c/tests/test_concurrency.c` (CMake target `test_concurrency_c`)
- `bindings/java/test-fixture-second/`
- `bindings/python/test_fixture_second/`
- the JavaScript suites build it into a temp workdir
  (`core/build/fixture.mjs`, `second: true`)
