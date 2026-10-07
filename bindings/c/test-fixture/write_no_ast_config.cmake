# Writes the shared fixture config with AST construction switched off.
# Usage: cmake -DSOURCE=<config.zig> -DDESTINATION=<config.zig> -P write_no_ast_config.cmake
file(READ "${SOURCE}" content)
string(REPLACE "pub const ast = true;" "pub const ast = false;" changed "${content}")
if(changed STREQUAL content)
    message(FATAL_ERROR "write_no_ast_config: no `pub const ast = true;` in ${SOURCE}")
endif()
file(WRITE "${DESTINATION}" "${changed}")
