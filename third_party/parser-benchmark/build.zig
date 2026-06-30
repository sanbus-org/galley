const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = false,
    });

    const exe = b.addExecutable(.{
        .name = "benchmark",
        .root_module = root_module,
    });

    // Tree-sitter Core
    exe.root_module.addIncludePath(b.path("tree-sitter/lib/include"));
    exe.root_module.addIncludePath(b.path("tree-sitter/lib/src"));
    exe.root_module.addCSourceFile(.{
        .file = b.path("tree-sitter/lib/src/lib.c"),
        .flags = &.{ "-std=c99", "-D_GNU_SOURCE" },
    });

    // Tree-sitter JSON Parser
    exe.root_module.addIncludePath(b.path("tree-sitter-json/src"));
    exe.root_module.addCSourceFile(.{
        .file = b.path("tree-sitter-json/src/parser.c"),
        .flags = &.{"-std=c99"},
    });

    // Bison/Flex generated C Parser files
    exe.root_module.addCSourceFile(.{
        .file = b.path("src/parser.c"),
        .flags = &.{"-std=c99"},
    });
    exe.root_module.addCSourceFile(.{
        .file = b.path("src/lexer.c"),
        .flags = &.{"-std=c99"},
    });

    // LALRPOP (Rust) static library
    const cargo_build = b.addSystemCommand(&.{ "cargo", "build", "--release" });
    cargo_build.setCwd(b.path("lalrpop-bench"));
    exe.step.dependOn(&cargo_build.step);
    exe.root_module.addObjectFile(b.path("lalrpop-bench/target/release/liblalrpop_bench.a"));

    // Build simdjson + RapidJSON as a shared library using system clang++.
    // This avoids triggering Zig 0.16's broken libcxx sub-compilation on macOS.
    const build_cpplib = b.addSystemCommand(&.{
        "clang++",
        "-O3", "-std=c++17",
        "-Wno-deprecated-literal-operator",
        "-Wno-nullability-completeness",
        "-dynamiclib",
        "-Isrc",
        "-Irapidjson/include",
        "src/simdjson/simdjson.cpp",
        "src/simdjson_wrapper.cpp",
        "src/rapidjson_wrapper.cpp",
        "-o", "libparsers.dylib",
    });
    build_cpplib.setCwd(b.path("."));
    exe.step.dependOn(&build_cpplib.step);

    exe.root_module.addLibraryPath(b.path("."));
    exe.root_module.linkSystemLibrary("parsers", .{});

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the benchmark");
    run_step.dependOn(&run_cmd.step);
}


