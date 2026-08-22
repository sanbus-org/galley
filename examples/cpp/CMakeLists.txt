cmake_minimum_required(VERSION 3.20)
project(galley_cpp_example CXX)

# Builds the keyvalue example against a Galley-generated parser.
#
# This build does NOT generate anything. Generate the parser yourself first
# (see README-style instructions below), then configure:
#
#   # 1. From a Galley checkout (or a fetched copy):
#   cd /path/to/galley && zig build -Doptimize=ReleaseFast install
#
#   # 2. Generate the parser from ll.grm (this directory becomes the
#   #    language directory; boilerplate modules are created on first run):
#   /path/to/galley/zig-out/bin/galley \
#       --parser-type ll --with-ast --with-position-tracking \
#       --no-procedures --no-bootstrap-zig-project \
#       /path/to/this/dir
#   # → _ll-parser.zig next to ll.grm
#
#   # 3. Build and run:
#   cmake -S . -B build -DGALLEY_CHECKOUT=/path/to/galley
#   cmake --build build
#   ./build/bin/example
#
# GALLEY_CHECKOUT may be omitted to fetch Galley instead; when fetching,
# point -Dparser-source at the copy you generated wherever you ran the CLI.
#
# Requires `zig` and `git` on PATH. Benchmarking submodules of Galley are
# not needed and are skipped; GIT_SHALLOW assumes GALLEY_TAG names a branch.
set(GALLEY_REPOSITORY "https://github.com/sanbus-org/galley.git"
    CACHE STRING "Galley repository to fetch")
set(GALLEY_TAG "main"
    CACHE STRING "Galley revision to fetch")

find_program(ZIG_EXECUTABLE NAMES zig REQUIRED)

set(PARSER_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/_ll-parser.zig" CACHE FILEPATH
    "Generated parser Zig source (see generation instructions above)")

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

if(NOT EXISTS "${PARSER_SOURCE}")
    message(FATAL_ERROR
        "Parser source '${PARSER_SOURCE}' not found.\n"
        "Generate it first with the Galley CLI (see the instructions at the "
        "top of this file), or pass -Dparser-source=/path/to/_ll-parser.zig.")
endif()

set(CAPI_PREFIX     "${CMAKE_BINARY_DIR}/galley-capi")
set(GALLEY_INCLUDE_DIR "${CAPI_PREFIX}/include")
if(APPLE)
    set(GALLEY_LIBRARY "${CAPI_PREFIX}/lib/libkeyvalue-c.dylib")
else()
    set(GALLEY_LIBRARY "${CAPI_PREFIX}/lib/libkeyvalue-c.so")
endif()

# Compile parser + runtime + C API into a shared library via Galley's
# generic consumer build file.
add_custom_command(
    OUTPUT "${GALLEY_LIBRARY}" "${GALLEY_INCLUDE_DIR}/galley.h"
    COMMAND "${ZIG_EXECUTABLE}" build
            --build-file "${GALLEY_SOURCE_DIR}/bindings/c/consumer/build.zig"
            "-Dparser-source=${PARSER_SOURCE}"
            "-Dparser-type=ll"
            "-Dlib-name=keyvalue-c"
            "-Doptimize=ReleaseFast"
            --prefix "${CAPI_PREFIX}"
            install
    WORKING_DIRECTORY "${GALLEY_SOURCE_DIR}"
    DEPENDS galley_sources "${PARSER_SOURCE}"
    VERBATIM
)
add_custom_target(galley_c_api DEPENDS
    "${GALLEY_LIBRARY}"
    "${GALLEY_INCLUDE_DIR}/galley.h"
)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

add_executable(example main.cpp)
set_target_properties(example PROPERTIES BUILD_RPATH "${CAPI_PREFIX}/lib")
target_include_directories(example PRIVATE "${GALLEY_INCLUDE_DIR}")
target_link_libraries(example PRIVATE "${GALLEY_LIBRARY}")
add_dependencies(example galley_c_api)
