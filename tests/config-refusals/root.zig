const parser = @import("parser-under-test");

// Resolving the runtime module runs its configuration checks.
comptime {
    _ = parser.config;
}
