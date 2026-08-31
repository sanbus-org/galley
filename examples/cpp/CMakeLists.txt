cmake_minimum_required(VERSION 3.20)
project(galley_cpp_example CXX)

# Self-sufficient Galley consumer: fetching Galley, generating the parser
# from this directory's ll.grm, and compiling it into a shared C-API library
# all happen here automatically.
#
# Generation options live in config.zig next to ll.grm — edit it and
# rebuild consumers to pick them up. Requires `zig` and `git` on PATH; nothing from any
# parent directory is used. Benchmarking submodules of Galley are not needed
# and are skipped; GIT_SHALLOW assumes GALLEY_TAG names a branch.
#
# Set GALLEY_CHECKOUT to a local Galley working tree to skip fetching (useful
# when developing Galley itself).
set(GALLEY_REPOSITORY "https://github.com/sanbus-org/galley.git"
    CACHE STRING "Galley repository to fetch")
set(GALLEY_TAG "main"
    CACHE STRING "Galley revision to fetch")

find_program(ZIG_EXECUTABLE NAMES zig REQUIRED)

set(GALLEY_CHECKOUT "" CACHE PATH
    "Existing Galley checkout to use instead of fetching one")

if(NOT GALLEY_CHECKOUT STREQUAL "" AND NOT EXISTS "${GALLEY_CHECKOUT}/build.zig")
    message(FATAL_ERROR
        "GALLEY_CHECKOUT='${GALLEY_CHECKOUT}' is not a Galley repository checkout "
        "(no build.zig). Point it at the repository root.")
endif()

if(GALLEY_CHECKOUT STREQUAL "")
    include(ExternalProject)
    ExternalProject_Add(galley_sources
        GIT_REPOSITORY "${GALLEY_REPOSITORY}"
        GIT_TAG "${GALLEY_TAG}"
        GIT_SUBMODULES ""
        GIT_SHALLOW TRUE
        SOURCE_DIR "${CMAKE_BINARY_DIR}/galley-src"
        CONFIGURE_COMMAND ""
        BUILD_COMMAND ""
        INSTALL_COMMAND ""
    )
    set(GALLEY_SOURCE_DIR "${CMAKE_BINARY_DIR}/galley-src")
else()
    add_custom_target(galley_sources)
    set(GALLEY_SOURCE_DIR "${GALLEY_CHECKOUT}")
endif()

set(GALLEY_CLI        "${GALLEY_SOURCE_DIR}/zig-out/bin/galley")
set(CAPI_PREFIX       "${CMAKE_BINARY_DIR}/galley-capi")
set(GALLEY_INCLUDE_DIR "${CAPI_PREFIX}/include")
set(GENERATED_PARSER  "${CMAKE_CURRENT_SOURCE_DIR}/_ll-parser.zig")
if(APPLE)
    set(GALLEY_LIBRARY "${CAPI_PREFIX}/lib/libkeyvalue-c.dylib")
else()
    set(GALLEY_LIBRARY "${CAPI_PREFIX}/lib/libkeyvalue-c.so")
endif()

# 1. Build the Galley generator CLI.
add_custom_command(
    OUTPUT "${GALLEY_CLI}"
    COMMAND "${ZIG_EXECUTABLE}" build -Doptimize=ReleaseFast install
    WORKING_DIRECTORY "${GALLEY_SOURCE_DIR}"
    DEPENDS galley_sources
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
#    generic consumer build file. All language-owned sources next to the
#    parser (config.zig, procedures.zig, procedures.cpp) are inferred
#    automatically — only the parser location and family are explicit.
#    Override with -Dconfig-zig-source / -Dprocedures-zig-source /
#    -Dprocedures-c-source / -Derror-messages-zig-source for non-standard
#    layouts.
add_custom_command(
    OUTPUT "${GALLEY_LIBRARY}" "${GALLEY_INCLUDE_DIR}/galley.h"
    COMMAND "${ZIG_EXECUTABLE}" build
            --build-file "${GALLEY_SOURCE_DIR}/bindings/c/consumer/build.zig"
            "-Dparser-source=${GENERATED_PARSER}"
            "-Dparser-type=ll"
            "-Dlib-name=keyvalue-c"
            "-Doptimize=ReleaseFast"
            --prefix "${CAPI_PREFIX}"
            install
    WORKING_DIRECTORY "${GALLEY_SOURCE_DIR}"
    DEPENDS galley_sources "${GENERATED_PARSER}"
    VERBATIM
)
add_custom_target(galley_c_api DEPENDS
    "${GALLEY_LIBRARY}"
    "${GALLEY_INCLUDE_DIR}/galley.h"
)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

add_executable(demo demo.cpp)
set_target_properties(demo PROPERTIES BUILD_RPATH "${CAPI_PREFIX}/lib")
target_include_directories(demo PRIVATE "${GALLEY_INCLUDE_DIR}")
target_link_libraries(demo PRIVATE "${GALLEY_LIBRARY}")
add_dependencies(demo galley_c_api)

# Throughput benchmark: a second parser (languages/json, all
# generation-time features off) compiled into a second library.
set(BENCHMARK_DIR "${CMAKE_CURRENT_SOURCE_DIR}/benchmark")
set(BENCHMARK_PARSER "${BENCHMARK_DIR}/_ll-parser.zig")
set(BENCHMARK_PREFIX "${CMAKE_BINARY_DIR}/galley-benchmark-capi")
set(BENCHMARK_SAMPLE "${GALLEY_SOURCE_DIR}/languages/json/samples/code-01.json")
if(APPLE)
    set(BENCHMARK_LIBRARY "${BENCHMARK_PREFIX}/lib/libbenchmark-cpp.dylib")
else()
    set(BENCHMARK_LIBRARY "${BENCHMARK_PREFIX}/lib/libbenchmark-cpp.so")
endif()

add_custom_command(
    OUTPUT "${BENCHMARK_PARSER}"
    COMMAND "${GALLEY_CLI}" --emit-metadata "${BENCHMARK_DIR}"
    DEPENDS "${GALLEY_CLI}" "${BENCHMARK_DIR}/ll.grm" "${BENCHMARK_DIR}/config.zig"
    VERBATIM
)

add_custom_command(
    OUTPUT "${BENCHMARK_LIBRARY}" "${BENCHMARK_PREFIX}/include/galley.h"
    COMMAND "${ZIG_EXECUTABLE}" build
            --build-file "${GALLEY_SOURCE_DIR}/bindings/c/consumer/build.zig"
            "-Dparser-source=${BENCHMARK_PARSER}"
            "-Dparser-type=ll"
            "-Dlib-name=benchmark-cpp"
            "-Doptimize=ReleaseFast"
            --prefix "${BENCHMARK_PREFIX}"
            install
    WORKING_DIRECTORY "${GALLEY_SOURCE_DIR}"
    DEPENDS galley_sources "${BENCHMARK_PARSER}" "${GALLEY_LIBRARY}"
    VERBATIM
)
add_custom_target(galley_benchmark_c_api DEPENDS
    "${BENCHMARK_LIBRARY}"
    "${BENCHMARK_PREFIX}/include/galley.h"
)

add_executable(benchmark benchmark.cpp)
set_target_properties(benchmark PROPERTIES BUILD_RPATH "${BENCHMARK_PREFIX}/lib")
target_include_directories(benchmark PRIVATE "${BENCHMARK_PREFIX}/include")
target_link_libraries(benchmark PRIVATE "${BENCHMARK_LIBRARY}")
target_compile_definitions(benchmark PRIVATE "GALLEY_JSON_SAMPLE=\"${BENCHMARK_SAMPLE}\"")
add_dependencies(benchmark galley_benchmark_c_api)
