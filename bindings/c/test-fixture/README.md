# C binding test fixture

Verbatim keyvalue `procedures.c` copied from `examples/c`; `ll.grm`
and `config.zig` are symlinks to the one shared grammar in
`bindings/test-fixture`. No rewrites: the hooks only ever include
`galley.h` and libc.

`CMakeLists.txt` generates the parser and builds the fixture library
(`libgalley-c-fixture.*`) next to the grammar, then compiles the one
shared suite (`../tests/test_bindings.c`) as C and as C++ (the C++ leg
builds from a build-tree copy so the C target keeps compiling as C):

    cmake -S bindings/c/test-fixture -B /tmp/build-c-fixture \
      -DCMAKE_BUILD_TYPE=Release -DGALLEY_CHECKOUT=$PWD
    cmake --build /tmp/build-c-fixture
    ctest --test-dir /tmp/build-c-fixture --output-on-failure

Edit these sources and the C/C++ suites pick the change up on their
next run.
