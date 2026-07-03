const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const clap = b.dependency("clap", .{});

    const languages_path = "languages";
    const generator_common_mod = b.addModule("generator_common", .{
        .root_source_file = b.path("src/generator/common.zig"),
        .target = target,
        .optimize = optimize,
    });
    const ll_generator_mod = b.addModule("ll_generator", .{
        .root_source_file = b.path("src/generator/ll.zig"),
        .target = target,
        .optimize = optimize,
    });
    ll_generator_mod.addImport("generator_common", generator_common_mod);
    const lr_generator_mod = b.addModule("lr_generator", .{
        .root_source_file = b.path("src/generator/lr.zig"),
        .target = target,
        .optimize = optimize,
    });
    lr_generator_mod.addImport("generator_common", generator_common_mod);
    const generator_grammar_mod = b.addModule("generator_grammar", .{
        .root_source_file = b.path("src/generator/grammar.zig"),
        .target = target,
        .optimize = optimize,
    });
    const galley_generator_mod = b.addModule("galley_generator", .{
        .root_source_file = b.path("src/generator/api.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "generator_common", .module = generator_common_mod },
            .{ .name = "generator_grammar", .module = generator_grammar_mod },
            .{ .name = "ll_generator", .module = ll_generator_mod },
            .{ .name = "lr_generator", .module = lr_generator_mod },
        },
    });
    const public_galley_mod = b.addModule("galley", .{
        .root_source_file = b.path("src/galley.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "generator_common", .module = generator_common_mod },
            .{ .name = "galley_generator", .module = galley_generator_mod },
            .{ .name = "ll_generator", .module = ll_generator_mod },
            .{ .name = "lr_generator", .module = lr_generator_mod },
        },
    });

    const cli_options = b.addOptions();
    cli_options.addOption([]const u8, "galley_root", b.pathFromRoot("."));
    cli_options.addOption([]const u8, "clap_source", b.pathFromRoot("zig-pkg/clap-0.12.0-oBajB7foAQDqlSwaSG5g0yq7xGbQARUsBk5T64gAOqP5/clap.zig"));

    const generator_cli_mod = b.createModule(.{
        .root_source_file = b.path("src/generator_cli.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "build_options", .module = cli_options.createModule() },
            .{ .name = "galley_generator", .module = galley_generator_mod },
        },
    });
    const generator_cli_exe = b.addExecutable(.{
        .name = "galley",
        .root_module = generator_cli_mod,
    });
    const install_generator_cli = b.addInstallArtifact(generator_cli_exe, .{});
    b.getInstallStep().dependOn(&install_generator_cli.step);

    const generator_cli_step = b.step("galley", "Build the Galley generator");
    generator_cli_step.dependOn(&install_generator_cli.step);

    var dir = try b.build_root.handle.openDir(b.graph.io, languages_path, .{ .iterate = true });
    defer dir.close(b.graph.io);

    var walker = try dir.walk(b.allocator);
    defer walker.deinit();

    const test_step = b.step("test", "Run tests");
    const generator_tests = b.addTest(.{
        .root_module = galley_generator_mod,
    });
    const run_generator_tests = b.addRunArtifact(generator_tests);
    test_step.dependOn(&run_generator_tests.step);

    const public_galley_tests = b.addTest(.{
        .root_module = public_galley_mod,
    });
    const run_public_galley_tests = b.addRunArtifact(public_galley_tests);
    test_step.dependOn(&run_public_galley_tests.step);

    var ll_galley_exe: ?*std.Build.Step.Compile = null;
    var lr_galley_exe: ?*std.Build.Step.Compile = null;

    while (try walker.next(b.graph.io)) |entry| {
        if (entry.kind != .directory and entry.kind != .sym_link) continue;

        inline for ([_][]const u8{ "ll", "lr" }) |parser_type| {
            const parser_path = try std.fs.path.join(
                b.allocator,
                &[_][]const u8{ languages_path, entry.path, "_" ++ parser_type ++ "-" ++ "parser.zig" },
            );
            defer b.allocator.free(parser_path);

            const procedures_path = try std.fs.path.join(
                b.allocator,
                &[_][]const u8{ languages_path, entry.path, "procedures.zig" },
            );
            defer b.allocator.free(procedures_path);

            const config_path = try std.fs.path.join(
                b.allocator,
                &[_][]const u8{ languages_path, entry.path, "config.zig" },
            );
            defer b.allocator.free(config_path);

            // Check if file exists in this subdirectory
            const exists = b.build_root.handle.access(b.graph.io, parser_path, .{});
            if (exists) |_| {
                const procedures_mod = b.addModule("procedures", .{
                    .root_source_file = b.path(procedures_path),
                    .target = target,
                });

                const config_mod = b.addModule("config", .{
                    .root_source_file = b.path(config_path),
                    .target = target,
                });

                const parser_mod = b.addModule("parser", .{
                    .root_source_file = b.path(parser_path),
                    .target = target,
                });

                const parser_name = try std.mem.concat(
                    b.allocator,
                    u8,
                    &[_][]const u8{ parser_type, "-", entry.path },
                );
                const galley_mod = b.createModule(.{
                    .root_source_file = b.path("src/main.zig"),
                    .target = target,
                    .optimize = optimize,
                    .link_libc = true,
                    .imports = &.{
                        .{ .name = "clap", .module = clap.module("clap") },
                        .{ .name = "procedures", .module = procedures_mod },
                        .{ .name = "config", .module = config_mod },
                        .{ .name = "parser", .module = parser_mod },
                    },
                });
                galley_mod.addImport("galley", galley_mod);
                procedures_mod.addImport("galley", galley_mod);
                procedures_mod.addImport("ll_generator", ll_generator_mod);
                procedures_mod.addImport("lr_generator", lr_generator_mod);
                config_mod.addImport("galley", galley_mod);
                parser_mod.addImport("galley", galley_mod);

                const exe = b.addExecutable(.{
                    .name = parser_name,
                    // .use_llvm = false,
                    // .use_lld = false,
                    .root_module = galley_mod,
                });
                if (std.mem.eql(u8, entry.path, "galley")) {
                    if (std.mem.eql(u8, parser_type, "ll")) {
                        ll_galley_exe = exe;
                    } else if (std.mem.eql(u8, parser_type, "lr")) {
                        lr_galley_exe = exe;
                    }
                }

                const install_artifact = b.addInstallArtifact(exe, .{});

                const result = try std.mem.concat(
                    b.allocator,
                    u8,
                    &[_][]const u8{ "Run the ", entry.path, " compiler" },
                );
                defer b.allocator.free(result);

                const build_step = b.step(parser_name, result);
                build_step.dependOn(&install_artifact.step);

                const run_step_name = try std.mem.concat(
                    b.allocator,
                    u8,
                    &[_][]const u8{ "run-", parser_name },
                );
                defer b.allocator.free(run_step_name);
                const run_step = b.step(run_step_name, result);

                const run_cmd = b.addRunArtifact(exe);
                run_step.dependOn(&run_cmd.step);

                run_cmd.step.dependOn(&install_artifact.step);

                if (b.args) |args| {
                    run_cmd.addArgs(args);
                }

                const exe_tests = b.addTest(.{
                    .root_module = exe.root_module,
                });

                const run_exe_tests = b.addRunArtifact(exe_tests);
                test_step.dependOn(&run_exe_tests.step);
            } else |err| {
                // File doesn't exist in this subdir - ignore
                if (err != error.FileNotFound) return err;
            }
        }
    }

    if (ll_galley_exe) |ll_exe| {
        if (lr_galley_exe) |lr_exe| {
            const parity_step = b.step("test-galley-bootstrap-parity", "Compare parser output generated by ll-galley and lr-galley");
            try addGalleyBootstrapParityCase(b, parity_step, ll_exe, lr_exe, "json-ll-no-ast", "languages/json/ll.grm", "_ll-parser.zig", &.{"--no-ast"});
            try addGalleyBootstrapParityCase(b, parity_step, ll_exe, lr_exe, "json-lr-no-ast", "languages/json/lr.grm", "_lr-parser.zig", &.{"--no-ast"});
            try addGalleyBootstrapParityCase(b, parity_step, ll_exe, lr_exe, "json-ll-with-ast", "languages/json/ll.grm", "_ll-parser.zig", &.{"--with-ast"});
            try addGalleyBootstrapParityCase(b, parity_step, ll_exe, lr_exe, "json-lr-with-ast", "languages/json/lr.grm", "_lr-parser.zig", &.{"--with-ast"});
            test_step.dependOn(parity_step);
        }
    }
}

fn addGalleyBootstrapParityCase(
    b: *std.Build,
    parity_step: *std.Build.Step,
    ll_galley_exe: *std.Build.Step.Compile,
    lr_galley_exe: *std.Build.Step.Compile,
    name: []const u8,
    grammar_path: []const u8,
    output_name: []const u8,
    options: []const []const u8,
) !void {
    const base_dir = try std.fs.path.join(b.allocator, &.{ ".zig-cache", "galley-bootstrap-parity", name });
    const ll_dir = try std.fs.path.join(b.allocator, &.{ base_dir, "ll" });
    const lr_dir = try std.fs.path.join(b.allocator, &.{ base_dir, "lr" });
    const grammar_name = std.fs.path.basename(grammar_path);
    const ll_input = try std.fs.path.join(b.allocator, &.{ ll_dir, grammar_name });
    const lr_input = try std.fs.path.join(b.allocator, &.{ lr_dir, grammar_name });
    const ll_output = try std.fs.path.join(b.allocator, &.{ ll_dir, output_name });
    const lr_output = try std.fs.path.join(b.allocator, &.{ lr_dir, output_name });

    const setup = b.addSystemCommand(&.{ "mkdir", "-p", ll_dir, lr_dir });
    setup.has_side_effects = true;

    const copy_ll_input = b.addSystemCommand(&.{ "cp", grammar_path, ll_input });
    copy_ll_input.has_side_effects = true;
    copy_ll_input.step.dependOn(&setup.step);

    const copy_lr_input = b.addSystemCommand(&.{ "cp", grammar_path, lr_input });
    copy_lr_input.has_side_effects = true;
    copy_lr_input.step.dependOn(&setup.step);

    const run_ll_galley = b.addRunArtifact(ll_galley_exe);
    run_ll_galley.has_side_effects = true;
    run_ll_galley.addArg(ll_input);
    run_ll_galley.addArgs(options);
    run_ll_galley.step.dependOn(&copy_ll_input.step);

    const run_lr_galley = b.addRunArtifact(lr_galley_exe);
    run_lr_galley.has_side_effects = true;
    run_lr_galley.addArg(lr_input);
    run_lr_galley.addArgs(options);
    run_lr_galley.step.dependOn(&copy_lr_input.step);

    const compare_outputs = b.addSystemCommand(&.{ "diff", "-u", ll_output, lr_output });
    compare_outputs.has_side_effects = true;
    compare_outputs.step.dependOn(&run_ll_galley.step);
    compare_outputs.step.dependOn(&run_lr_galley.step);
    parity_step.dependOn(&compare_outputs.step);
}
