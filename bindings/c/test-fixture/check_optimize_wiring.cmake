# Configures this fixture twice, with and without GALLEY_OPTIMIZE, and checks that
# the recorded library build command carries -Doptimize only when a mode was chosen.
# Run as: cmake -DSOURCE_DIR=... -DWORK_DIR=... -DGALLEY_CHECKOUT=... -DGENERATOR=... -P this-file

function(configure_and_collect label mode output_variable)
    set(build_dir "${WORK_DIR}/${label}")
    file(REMOVE_RECURSE "${build_dir}")
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -S "${SOURCE_DIR}" -B "${build_dir}" -G "${GENERATOR}"
                "-DGALLEY_CHECKOUT=${GALLEY_CHECKOUT}" "-DGALLEY_OPTIMIZE=${mode}"
        RESULT_VARIABLE result
        OUTPUT_QUIET
        ERROR_VARIABLE error_output)
    if(NOT result EQUAL 0)
        message(FATAL_ERROR "configure with GALLEY_OPTIMIZE='${mode}' failed:\n${error_output}")
    endif()
    file(GLOB_RECURSE build_files "${build_dir}/*build.make" "${build_dir}/build.ninja")
    set(combined "")
    foreach(build_file IN LISTS build_files)
        file(READ "${build_file}" contents)
        string(APPEND combined "${contents}")
    endforeach()
    file(READ "${build_dir}/galley-optimize-mode.txt" stamp)
    # Only the library build line: the generator CLI build keeps its own explicit mode.
    string(REGEX MATCH "[^\n]*-Dlib-name=galley-c-fixture[^\n]*" library_line "${combined}")
    set(${output_variable} "${library_line}" PARENT_SCOPE)
    set(${output_variable}_stamp "${stamp}" PARENT_SCOPE)
endfunction()

configure_and_collect(default "" default_commands)
if(default_commands STREQUAL "")
    message(FATAL_ERROR "the library build command was not found in the generated build files")
endif()
if(default_commands MATCHES "-Doptimize=")
    message(FATAL_ERROR "no mode chosen, but -Doptimize was passed")
endif()

configure_and_collect(debug "Debug" debug_commands)
if(NOT debug_commands MATCHES "-Doptimize=Debug")
    message(FATAL_ERROR "GALLEY_OPTIMIZE=Debug did not reach the library build command")
endif()
if(default_commands_stamp STREQUAL debug_commands_stamp)
    message(FATAL_ERROR "the mode stamp did not change with GALLEY_OPTIMIZE, so libraries would not rebuild")
endif()
