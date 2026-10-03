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

set(GALLEY_OPTIMIZE "" CACHE STRING
    "Zig build mode of the parser libraries (Debug, ReleaseSafe, ReleaseFast, ReleaseSmall); empty keeps the consumer build's ReleaseFast default. Debug enables the runtime's misuse checks; release builds do not check.")
set(GALLEY_OPTIMIZE_ARGUMENT "")
if(NOT GALLEY_OPTIMIZE STREQUAL "")
    set(GALLEY_OPTIMIZE_ARGUMENT "-Doptimize=${GALLEY_OPTIMIZE}")
endif()
# The libraries depend on this stamp, so changing the mode rebuilds them.
set(GALLEY_OPTIMIZE_STAMP "${CMAKE_BINARY_DIR}/galley-optimize-mode.txt")
file(CONFIGURE OUTPUT "${GALLEY_OPTIMIZE_STAMP}" CONTENT "${GALLEY_OPTIMIZE}\n")

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

# Every source the library compiles from: a change to any of them rebuilds
# the libraries below.
file(GLOB_RECURSE GALLEY_LIBRARY_SOURCES CONFIGURE_DEPENDS
    "${GALLEY_SOURCE_DIR}/src/runtime/*.zig"
    "${GALLEY_SOURCE_DIR}/bindings/c/capi.zig"
    "${GALLEY_SOURCE_DIR}/bindings/c/consumer/build.zig")

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
            ${GALLEY_OPTIMIZE_ARGUMENT}
            --prefix "${CMAKE_CURRENT_SOURCE_DIR}"
            install
    WORKING_DIRECTORY "${GALLEY_SOURCE_DIR}"
    DEPENDS "${GALLEY_OPTIMIZE_STAMP}" "${GENERATED_PARSER}" ${GALLEY_LIBRARY_SOURCES}
    VERBATIM
)
add_custom_target(galley_c_fixture DEPENDS
    "${GALLEY_LIBRARY}"
)

# 4. Concurrency fixture: two parsers, the keyvalue grammar and the second
#    shared grammar, each built in the build tree as its own host-shim
#    library (hooks forward to the host through the session). The
#    concurrency test loads both side by side.
function(galley_host_shim_library name grammar_directory library_variable)
    set(directory "${CMAKE_BINARY_DIR}/concurrency/${name}")
    if(APPLE)
        set(filename "libgalley-concurrency-${name}.dylib")
    else()
        set(filename "libgalley-concurrency-${name}.so")
    endif()
    add_custom_command(
        OUTPUT "${directory}/_ll-parser.zig" "${directory}/host_procedures.zig"
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${directory}"
        COMMAND "${CMAKE_COMMAND}" -E copy
                "${grammar_directory}/ll.grm" "${grammar_directory}/config.zig" "${directory}"
        COMMAND "${GALLEY_CLI}" --emit-host-procedures "${directory}"
        DEPENDS "${GALLEY_CLI}" "${grammar_directory}/ll.grm" "${grammar_directory}/config.zig"
        VERBATIM
    )
    add_custom_command(
        OUTPUT "${directory}/${filename}"
        COMMAND "${ZIG_EXECUTABLE}" build
                --build-file "${GALLEY_SOURCE_DIR}/bindings/c/consumer/build.zig"
                "-Dparser-source=${directory}/_ll-parser.zig"
                "-Dprocedures-zig-source=${directory}/host_procedures.zig"
                "-Dlib-name=galley-concurrency-${name}"
                "-Doutput=${filename}"
                ${GALLEY_OPTIMIZE_ARGUMENT}
                --prefix "${directory}"
                install
        WORKING_DIRECTORY "${GALLEY_SOURCE_DIR}"
        DEPENDS "${GALLEY_OPTIMIZE_STAMP}" "${directory}/_ll-parser.zig" "${directory}/host_procedures.zig" ${GALLEY_LIBRARY_SOURCES}
        VERBATIM
    )
    set(${library_variable} "${directory}/${filename}" PARENT_SCOPE)
endfunction()

galley_host_shim_library(first "${CMAKE_CURRENT_SOURCE_DIR}/../../test-fixture" CONCURRENCY_FIRST_LIBRARY)
galley_host_shim_library(second "${CMAKE_CURRENT_SOURCE_DIR}/../../test-fixture/second" CONCURRENCY_SECOND_LIBRARY)
add_custom_target(galley_concurrency_fixture DEPENDS
    "${CONCURRENCY_FIRST_LIBRARY}"
    "${CONCURRENCY_SECOND_LIBRARY}"
)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

# One suite, both native legs: the shared suite compiled as C and as C++.
# The C++ leg builds from a build-tree copy so the C target keeps
# compiling as C (LANGUAGE is per source file, not per target).
enable_testing()
find_package(Threads REQUIRED)
add_executable(test_bindings_c "${CMAKE_CURRENT_SOURCE_DIR}/../tests/test_bindings.c")
set_target_properties(test_bindings_c PROPERTIES BUILD_RPATH "${CMAKE_CURRENT_SOURCE_DIR}")
target_include_directories(test_bindings_c PRIVATE "${GALLEY_INCLUDE_DIR}")
target_link_libraries(test_bindings_c PRIVATE "${GALLEY_LIBRARY}" Threads::Threads)
add_dependencies(test_bindings_c galley_c_fixture)
add_test(NAME bindings-c COMMAND test_bindings_c)

configure_file("${CMAKE_CURRENT_SOURCE_DIR}/../tests/test_bindings.c"
    "${CMAKE_CURRENT_BINARY_DIR}/test_bindings.cpp" COPYONLY)
add_executable(test_bindings_cpp "${CMAKE_CURRENT_BINARY_DIR}/test_bindings.cpp")
set_target_properties(test_bindings_cpp PROPERTIES BUILD_RPATH "${CMAKE_CURRENT_SOURCE_DIR}")
target_include_directories(test_bindings_cpp PRIVATE "${GALLEY_INCLUDE_DIR}")
target_link_libraries(test_bindings_cpp PRIVATE "${GALLEY_LIBRARY}" Threads::Threads)
add_dependencies(test_bindings_cpp galley_c_fixture)
add_test(NAME bindings-cpp COMMAND test_bindings_cpp)

# Two parsers, two sessions each, four threads at once. dlopen keeps the two
# libraries' identical symbol names apart.
add_executable(test_concurrency_c "${CMAKE_CURRENT_SOURCE_DIR}/../tests/test_concurrency.c")
target_include_directories(test_concurrency_c PRIVATE "${GALLEY_INCLUDE_DIR}")
target_link_libraries(test_concurrency_c PRIVATE Threads::Threads ${CMAKE_DL_LIBS})
add_dependencies(test_concurrency_c galley_concurrency_fixture)
add_test(NAME concurrency-c
    COMMAND test_concurrency_c "${CONCURRENCY_FIRST_LIBRARY}" "${CONCURRENCY_SECOND_LIBRARY}")

# GALLEY_OPTIMIZE reaches the library build command only when set.
add_test(NAME optimize-wiring
    COMMAND "${CMAKE_COMMAND}"
            "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
            "-DWORK_DIR=${CMAKE_BINARY_DIR}/optimize-wiring"
            "-DGALLEY_CHECKOUT=${GALLEY_CHECKOUT}"
            "-DGENERATOR=${CMAKE_GENERATOR}"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/check_optimize_wiring.cmake")
