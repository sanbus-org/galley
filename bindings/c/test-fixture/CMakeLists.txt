cmake_minimum_required(VERSION 3.20)
project(galley_c_test_fixture C CXX)

# C binding test fixture: generates the parser from this directory's own
# keyvalue grammar and runs the one shared suite in bindings/c/tests
# against it — as C and as C++. Never examples/.
#
# Requires `zig` on PATH and GALLEY_CHECKOUT pointing at a Galley working
# tree (for convenience, GALLEY_CHECKOUT=$(examples/scripts/fetch-galley.sh)
# fetches one — that cache is examples-only, not part of the bindings);
# nothing from any parent directory is used.
find_program(ZIG_EXECUTABLE NAMES zig REQUIRED)

set(GALLEY_CHECKOUT "" CACHE PATH
    "Existing Galley checkout to use (required)")

if(GALLEY_CHECKOUT STREQUAL "")
    message(FATAL_ERROR
        "GALLEY_CHECKOUT is not set; point it at a Galley checkout "
        "(examples/scripts/fetch-galley.sh can fetch one).")
endif()
if(NOT EXISTS "${GALLEY_CHECKOUT}/build.zig")
    message(FATAL_ERROR
        "GALLEY_CHECKOUT='${GALLEY_CHECKOUT}' is not a Galley repository checkout "
        "(no build.zig). Point it at the repository root.")
endif()
set(GALLEY_SOURCE_DIR "${GALLEY_CHECKOUT}")

set(GALLEY_CLI        "${GALLEY_SOURCE_DIR}/zig-out/bin/galley")
set(GALLEY_INCLUDE_DIR "${GALLEY_SOURCE_DIR}/bindings/c")
set(GENERATED_PARSER  "${CMAKE_CURRENT_SOURCE_DIR}/_ll-parser.zig")
if(APPLE)
    set(GALLEY_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/libgalley-c-fixture.dylib")
    set(GALLEY_LIB_FILENAME "libgalley-c-fixture.dylib")
else()
    set(GALLEY_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/libgalley-c-fixture.so")
    set(GALLEY_LIB_FILENAME "libgalley-c-fixture.so")
endif()

# 1. Build the Galley generator CLI.
add_custom_command(
    OUTPUT "${GALLEY_CLI}"
    COMMAND "${ZIG_EXECUTABLE}" build -Doptimize=ReleaseFast install
    WORKING_DIRECTORY "${GALLEY_SOURCE_DIR}"
    VERBATIM
)

# 2. Generate the parser from ll.grm. All generation-time options come from
#    this directory's config.zig; the boilerplate modules and _ll-parser.zig
#    are generated in place and gitignored.
add_custom_command(
    OUTPUT "${GENERATED_PARSER}"
    COMMAND "${GALLEY_CLI}" --emit-metadata "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS "${GALLEY_CLI}" "${CMAKE_CURRENT_SOURCE_DIR}/ll.grm" "${CMAKE_CURRENT_SOURCE_DIR}/config.zig"
    VERBATIM
)

# 3. Compile parser + runtime + C API into a shared library via Galley's
#    generic consumer build file, directly next to the grammar. procedures.c
#    next to the grammar is inferred automatically.
add_custom_command(
    OUTPUT "${GALLEY_LIBRARY}"
    COMMAND "${ZIG_EXECUTABLE}" build
            --build-file "${GALLEY_SOURCE_DIR}/bindings/c/consumer/build.zig"
            "-Dparser-source=${GENERATED_PARSER}"
            "-Dlib-name=galley-c-fixture"
            "-Doutput=${GALLEY_LIB_FILENAME}"
            "-Doptimize=ReleaseFast"
            --prefix "${CMAKE_CURRENT_SOURCE_DIR}"
            install
    WORKING_DIRECTORY "${GALLEY_SOURCE_DIR}"
    DEPENDS "${GENERATED_PARSER}"
    VERBATIM
)
add_custom_target(galley_c_fixture DEPENDS
    "${GALLEY_LIBRARY}"
)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

# One suite, both native legs: the shared suite compiled as C and as C++.
# The C++ leg builds from a build-tree copy so the C target keeps
# compiling as C (LANGUAGE is per source file, not per target).
enable_testing()
add_executable(test_bindings_c "${CMAKE_CURRENT_SOURCE_DIR}/../tests/test_bindings.c")
set_target_properties(test_bindings_c PROPERTIES BUILD_RPATH "${CMAKE_CURRENT_SOURCE_DIR}")
target_include_directories(test_bindings_c PRIVATE "${GALLEY_INCLUDE_DIR}")
target_link_libraries(test_bindings_c PRIVATE "${GALLEY_LIBRARY}")
add_dependencies(test_bindings_c galley_c_fixture)
add_test(NAME bindings-c COMMAND test_bindings_c)

configure_file("${CMAKE_CURRENT_SOURCE_DIR}/../tests/test_bindings.c"
    "${CMAKE_CURRENT_BINARY_DIR}/test_bindings.cpp" COPYONLY)
add_executable(test_bindings_cpp "${CMAKE_CURRENT_BINARY_DIR}/test_bindings.cpp")
set_target_properties(test_bindings_cpp PROPERTIES BUILD_RPATH "${CMAKE_CURRENT_SOURCE_DIR}")
target_include_directories(test_bindings_cpp PRIVATE "${GALLEY_INCLUDE_DIR}")
target_link_libraries(test_bindings_cpp PRIVATE "${GALLEY_LIBRARY}")
add_dependencies(test_bindings_cpp galley_c_fixture)
add_test(NAME bindings-cpp COMMAND test_bindings_cpp)
