# Shared binding test-fixture grammar

The one keyvalue grammar (`ll.grm`) and generation options
(`config.zig`) every binding test suite parses. Each binding's fixture
directory links these two files in and adds its own `procedures.*`
(they are genuinely different files — one per host language):

- `bindings/c/test-fixture/`
- `bindings/go/testfixture/`
- `bindings/python/test-fixture/`
- `bindings/java/test-fixture/`
- `bindings/rust/test-fixture/`
- `bindings/js/test-fixture/`

Edit these two files and every binding suite picks the change up on
its next run. The bindings-consistency CI job enforces that the links
stay links.
