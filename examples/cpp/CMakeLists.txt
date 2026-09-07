cmake_minimum_required(VERSION 3.20)
project(galley_cpp_example CXX)

# Galley C++ consumer example: generating the parser from this directory's
# ll.grm and compiling it into a shared C-API library next to the grammar.
#
# Generation options live in config.zig next to ll.grm — edit it and
# rebuild consumers to pick them up. Requires `zig` on PATH and
# GALLEY_CHECKOUT pointing at a Galley working tree (for convenience,
# GALLEY_CHECKOUT=$(examples/scripts/fetch-galley.sh) fetches one — that
# cache is examples-only, not part of the bindings); nothing from any
# parent directory is used.
#
# Set GALLEY_CHECKOUT to a local Galley working tree (required).
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
    set(GALLEY_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/libkeyvalue-c.dylib")
    set(GALLEY_LIB_FILENAME "libkeyvalue-c.dylib")
else()
    set(GALLEY_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/libkeyvalue-c.so")
    set(GALLEY_LIB_FILENAME "libkeyvalue-c.so")
endif()

# 1. Build the Galley generator CLI.
add_custom_command(
    OUTPUT "${GALLEY_CLI}"
    COMMAND "${ZIG_EXECUTABLE}" build -Doptimize=ReleaseFast install
    WORKING_DIRECTORY "${GALLEY_SOURCE_DIR}"
    VERBATIM
)

# 2. Generate the parser from ll.grm. All generation-time options come from
#    this directory's config.zig (created from documented defaults when
#    missing); the boilerplate modules and _ll-parser.zig are generated in
#    place and gitignored.
add_custom_command(
    OUTPUT "${GENERATED_PARSER}"
    COMMAND "${GALLEY_CLI}" --emit-metadata "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS "${GALLEY_CLI}" "${CMAKE_CURRENT_SOURCE_DIR}/ll.grm" "${CMAKE_CURRENT_SOURCE_DIR}/config.zig"
    VERBATIM
)

# 3. Compile parser + runtime + C API into a shared library via Galley's
#    generic consumer build file, directly next to the grammar. All
#    language-owned sources next to the parser (config.zig, procedures.zig,
#    procedures.cpp) are inferred automatically — only the parser location
#    and family are explicit. The header comes from the checkout
#    (bindings/c/galley.h), not from the build output.
#    Override with -Dconfig-zig-source / -Dprocedures-zig-source /
#    -Dprocedures-c-source / -Derror-messages-zig-source for non-standard
#    layouts.
add_custom_command(
    OUTPUT "${GALLEY_LIBRARY}"
    COMMAND "${ZIG_EXECUTABLE}" build
            --build-file "${GALLEY_SOURCE_DIR}/bindings/c/consumer/build.zig"
            "-Dparser-source=${GENERATED_PARSER}"
            "-Dlib-name=keyvalue-c"
            "-Doutput=${GALLEY_LIB_FILENAME}"
            "-Doptimize=ReleaseFast"
            --prefix "${CMAKE_CURRENT_SOURCE_DIR}"
            install
    WORKING_DIRECTORY "${GALLEY_SOURCE_DIR}"
    DEPENDS "${GENERATED_PARSER}"
    VERBATIM
)
add_custom_target(galley_c_api DEPENDS
    "${GALLEY_LIBRARY}"
)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

add_executable(demo demo.cpp)
set_target_properties(demo PROPERTIES BUILD_RPATH "${CMAKE_CURRENT_SOURCE_DIR}")
target_include_directories(demo PRIVATE "${GALLEY_INCLUDE_DIR}")
target_link_libraries(demo PRIVATE "${GALLEY_LIBRARY}")
add_dependencies(demo galley_c_api)

# Throughput benchmark: a second parser (languages/json, all
# generation-time features off) compiled into a second library.
set(BENCHMARK_DIR "${CMAKE_CURRENT_SOURCE_DIR}/benchmark")
set(BENCHMARK_PARSER "${BENCHMARK_DIR}/_ll-parser.zig")
if(APPLE)
    set(BENCHMARK_LIBRARY "${BENCHMARK_DIR}/libbenchmark-cpp.dylib")
    set(BENCHMARK_LIB_FILENAME "libbenchmark-cpp.dylib")
else()
    set(BENCHMARK_LIBRARY "${BENCHMARK_DIR}/libbenchmark-cpp.so")
    set(BENCHMARK_LIB_FILENAME "libbenchmark-cpp.so")
endif()

add_custom_command(
    OUTPUT "${BENCHMARK_PARSER}"
    COMMAND "${GALLEY_CLI}" --emit-metadata "${BENCHMARK_DIR}"
    DEPENDS "${GALLEY_CLI}" "${BENCHMARK_DIR}/ll.grm" "${BENCHMARK_DIR}/config.zig"
    VERBATIM
)

add_custom_command(
    OUTPUT "${BENCHMARK_LIBRARY}"
    COMMAND "${ZIG_EXECUTABLE}" build
            --build-file "${GALLEY_SOURCE_DIR}/bindings/c/consumer/build.zig"
            "-Dparser-source=${BENCHMARK_PARSER}"
            "-Dlib-name=benchmark-cpp"
            "-Doutput=${BENCHMARK_LIB_FILENAME}"
            "-Doptimize=ReleaseFast"
            --prefix "${BENCHMARK_DIR}"
            install
    WORKING_DIRECTORY "${GALLEY_SOURCE_DIR}"
    DEPENDS "${BENCHMARK_PARSER}" "${GALLEY_LIBRARY}"
    VERBATIM
)
add_custom_target(galley_benchmark_c_api DEPENDS
    "${BENCHMARK_LIBRARY}"
)

add_executable(benchmark benchmark.cpp)
set_target_properties(benchmark PROPERTIES BUILD_RPATH "${BENCHMARK_DIR}")
target_include_directories(benchmark PRIVATE "${GALLEY_INCLUDE_DIR}")
target_link_libraries(benchmark PRIVATE "${BENCHMARK_LIBRARY}")
target_compile_definitions(benchmark PRIVATE "GALLEY_SOURCE_DIR=\"${GALLEY_SOURCE_DIR}\"")
add_dependencies(benchmark galley_benchmark_c_api)
