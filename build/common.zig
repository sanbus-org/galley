const std = @import("std");

pub const languages_path = "languages";

pub const GeneratorModules = struct {
    runtime_options_mod: *std.Build.Module,
    ast_memory_benchmark: bool,
    syntax_error_stack_depth: usize,
    /// Process-wide signal registry shared by every runtime instantiation
    /// in this build. One instance per build graph is what makes the
    /// SIGSEGV/SIGBUS disposition registry process-wide.
    signals_mod: *std.Build.Module,
    generator_common_mod: *std.Build.Module,
    generator_switch_plan_mod: *std.Build.Module,
    generator_config_file_mod: *std.Build.Module,
    ll_generator_mod: *std.Build.Module,
    lr_generator_mod: *std.Build.Module,
    galley_grammar_procedures_mod: *std.Build.Module,
    galley_grammar_library_mod: *std.Build.Module,
    galley_generator_mod: *std.Build.Module,
    /// Source of Galley's own LL parser, the bootstrap seed. See `addGalleySeedParser`.
    galley_seed_parser: std.Build.LazyPath,
};

pub const GeneratedParserModule = struct {
    runtime_mod: *std.Build.Module,
    parser_mod: *std.Build.Module,
};

/// The process-wide signal registry, registered once per build graph and
/// shared by every runtime instantiation in it. Idempotent: repeated calls
/// return the existing registration instead of silently overwriting it.
pub fn sharedSignalsModule(b: *std.Build) *std.Build.Module {
    if (b.modules.get("galley_signals")) |existing| return existing;
    const signals_mod = b.addModule("galley_signals", .{
        .root_source_file = b.path("src/runtime/process/signals.zig"),
    });
    signals_mod.addImport("c", b.createModule(.{
        .root_source_file = b.path("src/runtime/process/c.zig"),
    }));
    return signals_mod;
}

pub fn runtimeLinkLibC(target: std.Build.ResolvedTarget) ?bool {
    return switch (target.result.os.tag) {
        .linux, .macos => true,
        else => null,
    };
}

pub fn addGeneratedParserModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    runtime_module_name: []const u8,
    parser_module_name: []const u8,
    parser_source: std.Build.LazyPath,
    procedures_mod: *std.Build.Module,
    config_mod: *std.Build.Module,
    error_messages_mod: *std.Build.Module,
    runtime_options_mod: *std.Build.Module,
    signals_mod: *std.Build.Module,
) GeneratedParserModule {
    const parser_mod = b.addModule(parser_module_name, .{
        .root_source_file = parser_source,
        .target = target,
        .optimize = optimize,
    });
    const runtime_mod = b.addModule(runtime_module_name, .{
        .root_source_file = b.path("src/runtime/api.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = runtimeLinkLibC(target),
        .imports = &.{
            .{ .name = "procedures", .module = procedures_mod },
            .{ .name = "config", .module = config_mod },
            .{ .name = "error_messages", .module = error_messages_mod },
            .{ .name = "parser", .module = parser_mod },
            .{ .name = "runtime_options", .module = runtime_options_mod },
            .{ .name = "signals", .module = signals_mod },
        },
    });
    connectParserModules(runtime_mod, procedures_mod, config_mod, error_messages_mod, parser_mod);

    return .{
        .runtime_mod = runtime_mod,
        .parser_mod = parser_mod,
    };
}

/// Lets generated source and customization modules refer to the assembled
/// runtime as `@import("galley")`.
pub fn connectParserModules(
    runtime_mod: *std.Build.Module,
    procedures_mod: *std.Build.Module,
    config_mod: *std.Build.Module,
    error_messages_mod: *std.Build.Module,
    parser_mod: *std.Build.Module,
) void {
    runtime_mod.addImport("galley", runtime_mod);
    procedures_mod.addImport("galley", runtime_mod);
    config_mod.addImport("galley", runtime_mod);
    error_messages_mod.addImport("galley", runtime_mod);
    parser_mod.addImport("galley", runtime_mod);
}

pub const ParserType = enum { ll, lr };

/// Options for `addParserModule`, the public consumer entry point for
/// assembling a generated parser with Galley's runtime.
pub const AddParserModuleOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    /// Directory containing `_ll-parser.zig` / `_lr-parser.zig`, `config.zig`,
    /// and `procedures.zig`.
    language_dir: std.Build.LazyPath,
    parser_type: ParserType = .ll,
    parser_source: ?std.Build.LazyPath = null,
    procedures: ?std.Build.LazyPath = null,
    config: ?std.Build.LazyPath = null,
    error_messages: ?std.Build.LazyPath = null,
    runtime_options: ?*std.Build.Module = null,
    /// Extra imports for `procedures.zig` (Galley's own grammar needs
    /// `generator_common`).
    procedures_imports: []const std.Build.Module.Import = &.{},
};

/// Assembles a generated parser, `config.zig`, `procedures.zig`, and
/// Galley's runtime into one module. Import it from application code as
/// `@import("parser")` (or any name chosen in the consumer `build.zig`).
///
/// When `{ll,lr}_error_messages.zig` is absent, the empty CLI template is
/// used. Override any inferred path with the matching optional field.
pub fn addParserModule(
    b: *std.Build,
    galley: *std.Build.Dependency,
    options: AddParserModuleOptions,
) *std.Build.Module {
    const type_name = @tagName(options.parser_type);
    const parser_file = options.parser_source orelse
        options.language_dir.path(b, b.fmt("_{s}-parser.zig", .{type_name}));
    const procedures_file = options.procedures orelse
        options.language_dir.path(b, "procedures.zig");
    const config_file = options.config orelse
        options.language_dir.path(b, "config.zig");
    const error_file = options.error_messages orelse blk: {
        const name = b.fmt("{s}_error_messages.zig", .{type_name});
        if (lazyPathChildExists(b, options.language_dir, name)) {
            break :blk options.language_dir.path(b, name);
        }
        break :blk galley.path(b.fmt("src/cli/templates/{s}_error_messages.zig", .{type_name}));
    };

    const procedures_mod = b.createModule(.{
        .root_source_file = procedures_file,
        .target = options.target,
        .optimize = options.optimize,
        .imports = options.procedures_imports,
    });
    const config_mod = b.createModule(.{
        .root_source_file = config_file,
        .target = options.target,
        .optimize = options.optimize,
    });
    const error_messages_mod = b.createModule(.{
        .root_source_file = error_file,
        .target = options.target,
        .optimize = options.optimize,
    });
    const parser_mod = b.createModule(.{
        .root_source_file = parser_file,
        .target = options.target,
        .optimize = options.optimize,
    });
    const runtime_options_mod = options.runtime_options orelse b.createModule(.{
        .root_source_file = galley.path("src/runtime/default_runtime_options.zig"),
    });
    const signals_mod = galley.module("galley_signals");
    const runtime_mod = b.createModule(.{
        .root_source_file = galley.path("src/runtime/api.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .link_libc = runtimeLinkLibC(options.target),
        .imports = &.{
            .{ .name = "procedures", .module = procedures_mod },
            .{ .name = "config", .module = config_mod },
            .{ .name = "error_messages", .module = error_messages_mod },
            .{ .name = "parser", .module = parser_mod },
            .{ .name = "runtime_options", .module = runtime_options_mod },
            .{ .name = "signals", .module = signals_mod },
        },
    });
    connectParserModules(runtime_mod, procedures_mod, config_mod, error_messages_mod, parser_mod);
    return runtime_mod;
}

/// Declares a configure-time dependency on `relative_path` when it exists:
/// observed by contents for files and by entries for directories. Configure
/// dependencies may only reference existing paths of the matching kind, so
/// missing paths are covered by a declaration on their parent directory.
pub fn declareConfigureDependencyIfPresent(b: *std.Build, relative_path: []const u8) void {
    if (b.root.openDir(b.graph.io, relative_path, .{})) |directory| {
        directory.close(b.graph.io);
        b.dependOnDirectoryContents(b.path(relative_path));
    } else |_| {
        if (b.root.access(b.graph.io, relative_path, .{})) {
            b.dependOnFileContents(b.path(relative_path));
        } else |_| {}
    }
}

fn lazyPathChildExists(b: *std.Build, dir: std.Build.LazyPath, name: []const u8) bool {
    if (openObservableDir(b, dir)) |observable| {
        observable.close(b.graph.io);
        // The configure result depends on the child's existence; observing
        // the directory's entries re-runs the configure phase when the child
        // is created, deleted, or renamed.
        b.dependOnDirectoryContents(dir);
    } else {
        declareExistingAncestorContents(b, dir);
    }
    switch (dir) {
        .src_path => |src| {
            const joined = b.pathJoin(&.{ src.sub_path, name });
            src.owner.root.access(b.graph.io, joined, .{}) catch return false;
            return true;
        },
        .cwd_relative => |rel| {
            const joined = b.pathJoin(&.{ rel, name });
            if (std.fs.path.isAbsolute(joined)) {
                std.Io.Dir.accessAbsolute(b.graph.io, joined, .{}) catch return false;
            } else {
                std.Io.Dir.cwd().access(b.graph.io, joined, .{}) catch return false;
            }
            return true;
        },
        .dependency => |dep| {
            const joined = b.pathJoin(&.{ dep.sub_path, name });
            dep.dependency.builder.root.access(b.graph.io, joined, .{}) catch return false;
            return true;
        },
        .relative => |relative| switch (relative.base) {
            .cwd => {
                const joined = b.pathJoin(&.{ relative.sub_path, name });
                std.Io.Dir.cwd().access(b.graph.io, joined, .{}) catch return false;
                return true;
            },
            // Cache, install, and toolchain roots are not package directories.
            else => return false,
        },
        .generated => return false,
    }
}

/// Opens `dir` when configure logic may observe its entries and it exists as
/// a directory. Configure dependencies may only reference existing paths of
/// the matching kind, so callers declare a dependency only when this
/// succeeds.
fn openObservableDir(b: *std.Build, dir: std.Build.LazyPath) ?std.Io.Dir {
    return switch (dir) {
        .src_path => |src| src.owner.root.openDir(b.graph.io, src.sub_path, .{}) catch null,
        .cwd_relative => |rel| blk: {
            if (std.fs.path.isAbsolute(rel)) {
                break :blk std.Io.Dir.openDirAbsolute(b.graph.io, rel, .{}) catch null;
            }
            break :blk std.Io.Dir.cwd().openDir(b.graph.io, rel, .{}) catch null;
        },
        .dependency => |dep| dep.dependency.builder.root.openDir(b.graph.io, dep.sub_path, .{}) catch null,
        .relative => |relative| switch (relative.base) {
            .cwd => std.Io.Dir.cwd().openDir(b.graph.io, relative.sub_path, .{}) catch null,
            else => null,
        },
        // Generated paths do not exist during the configure phase.
        .generated => null,
    };
}

/// `dir` is missing or not a directory: declaring it directly would fail
/// configure, so declare the nearest existing ancestor instead — creating
/// `dir` changes that ancestor's entries, which re-runs configure and then
/// declares `dir` itself. Generated paths are skipped: they have no
/// configure-time source. Non-cwd `.relative` paths are skipped: cache,
/// install, and toolchain roots are not package directories.
fn declareExistingAncestorContents(b: *std.Build, dir: std.Build.LazyPath) void {
    var current = parentPath(dir) orelse return;
    while (true) {
        if (openObservableDir(b, current)) |ancestor| {
            ancestor.close(b.graph.io);
            b.dependOnDirectoryContents(current);
            return;
        }
        current = parentPath(current) orelse return;
    }
}

/// The directory containing `path`, or null at a path's own root (where the
/// parent is the path itself) and for paths with no observable parent.
fn parentPath(path: std.Build.LazyPath) ?std.Build.LazyPath {
    switch (path) {
        .src_path => |src| return src.owner.path(parentSubPath(src.sub_path) orelse return null),
        .cwd_relative => |rel| return .{ .cwd_relative = parentSubPath(rel) orelse return null },
        .dependency => |dep| return .{ .dependency = .{
            .dependency = dep.dependency,
            .sub_path = parentSubPath(dep.sub_path) orelse return null,
        } },
        .relative => |relative| switch (relative.base) {
            .cwd => return .{ .relative = .{
                .base = .cwd,
                .sub_path = parentSubPath(relative.sub_path) orelse return null,
            } },
            // Cache, install, and toolchain roots are not package directories.
            else => return null,
        },
        // Generated paths have no configure-time source to observe.
        .generated => return null,
    }
}

/// The parent of `sub_path`: its dirname, its own root ("." or "/") when no
/// separator remains, or null once at the root itself.
fn parentSubPath(sub_path: []const u8) ?[]const u8 {
    const parent = std.fs.path.dirname(sub_path) orelse
        if (std.fs.path.isAbsolute(sub_path)) return null else ".";
    // A path whose parent spells itself (".", or a lone root on Windows) is
    // already the root: stop instead of fixpointing the ancestor walk when
    // the root turns out to be unopenable.
    if (std.mem.eql(u8, parent, sub_path)) return null;
    return parent;
}

pub fn addGalleyGrammarProceduresModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    generator_common_mod: *std.Build.Module,
) *std.Build.Module {
    const procedures_mod = b.createModule(.{
        .root_source_file = b.path("languages/galley/procedures.zig"),
        .target = target,
        .optimize = optimize,
    });
    procedures_mod.addImport("generator_common", generator_common_mod);
    return procedures_mod;
}

const galley_seed_directory = "languages/galley";
const galley_seed_file_name = "_ll-parser.zig";

/// Galley's own LL parser bootstraps the generator, so it must exist before
/// any parser can be generated. The expanded file is gitignored because it
/// is large; the repository tracks only `_ll-parser.zig.zst`. A present
/// `_ll-parser.zig` (a local regeneration) wins; otherwise the compressed
/// seed is expanded by a small tool that needs nothing beyond Zig.
fn addGalleySeedParser(b: *std.Build) std.Build.LazyPath {
    const expanded_path = galley_seed_directory ++ "/" ++ galley_seed_file_name;
    // Whether the expanded file exists decides the source; the directory's
    // entries cover it appearing or vanishing.
    declareConfigureDependencyIfPresent(b, galley_seed_directory);
    if (b.root.access(b.graph.io, expanded_path, .{})) |_| {
        return b.path(expanded_path);
    } else |_| {}

    const expand_seed_exe = b.addExecutable(.{
        .name = "expand-seed",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/expand_seed.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
    const expand_seed = b.addRunArtifact(expand_seed_exe);
    expand_seed.addFileArg(b.path(expanded_path ++ ".zst"));
    return expand_seed.addOutputFileArg(galley_seed_file_name);
}

pub const GalleyCli = struct {
    generator_cli_mod: *std.Build.Module,
    generator_cli_exe: *std.Build.Step.Compile,
    install_generator_cli: *std.Build.Step.InstallArtifact,
    generate_parser_file_exe: ?*std.Build.Step.Compile = null,
};

pub const GalleyCliOptions = struct {
    install_default: bool = false,
    add_galley_step: bool = false,
    include_generate_parser_file: bool = false,
    galley_git_url: []const u8 = "https://github.com/sanbus-org/galley.git",
    galley_git_commit: ?[]const u8 = null,
};

pub const LanguageParser = struct {
    entry_path: []const u8,
    parser_type: []const u8,
    parser_name: []const u8,
    galley_parser_mod: *std.Build.Module,
    procedures_mod: *std.Build.Module,
    config_mod: *std.Build.Module,
    error_messages_mod: *std.Build.Module,
    parser_mod: *std.Build.Module,
};

pub fn addGeneratorModules(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) GeneratorModules {
    const ast_memory_benchmark = b.option(
        bool,
        "ast-memory-benchmark",
        "Instrument AST allocation and report final AST memory usage",
    ) orelse false;
    const syntax_error_stack_depth = b.option(
        usize,
        "syntax-error-stack-depth",
        "Override the in-progress variable stack depth used in LL syntax error messages (defaults to 5 in debug and 1 in release builds; a value above 1 enables the stack)",
    ) orelse 0;
    const runtime_options = b.addOptions();
    runtime_options.addOption(bool, "include_tests", false);
    runtime_options.addOption(bool, "ast_memory_benchmark", ast_memory_benchmark);
    runtime_options.addOption(usize, "syntax_error_stack_depth", syntax_error_stack_depth);
    const runtime_options_mod = runtime_options.createModule();
    const signals_mod = sharedSignalsModule(b);

    const generator_common_mod = b.addModule("generator_common", .{
        .root_source_file = b.path("src/generator/common.zig"),
        .target = target,
        .optimize = optimize,
    });
    const generator_switch_plan_mod = b.addModule("generator_switch_plan", .{
        .root_source_file = b.path("src/generator/switch_plan.zig"),
        .target = target,
        .optimize = optimize,
    });
    generator_switch_plan_mod.addImport("generator_common", generator_common_mod);
    const generator_emitter_common_mod = b.addModule("generator_emitter_common", .{
        .root_source_file = b.path("src/generator/emitter_common.zig"),
        .target = target,
        .optimize = optimize,
    });
    generator_emitter_common_mod.addImport("generator_common", generator_common_mod);
    generator_emitter_common_mod.addImport("generator_switch_plan", generator_switch_plan_mod);
    const generator_config_file_mod = b.addModule("generator_config_file", .{
        .root_source_file = b.path("src/generator/config_file.zig"),
        .target = target,
        .optimize = optimize,
    });
    generator_config_file_mod.addImport("generator_common", generator_common_mod);
    const ll_generator_mod = b.addModule("ll_generator", .{
        .root_source_file = b.path("src/generator/ll.zig"),
        .target = target,
        .optimize = optimize,
    });
    ll_generator_mod.addImport("generator_common", generator_common_mod);
    ll_generator_mod.addImport("generator_emitter_common", generator_emitter_common_mod);
    ll_generator_mod.addImport("generator_switch_plan", generator_switch_plan_mod);
    const lr_generator_mod = b.addModule("lr_generator", .{
        .root_source_file = b.path("src/generator/lr.zig"),
        .target = target,
        .optimize = optimize,
    });
    lr_generator_mod.addImport("generator_common", generator_common_mod);
    lr_generator_mod.addImport("generator_emitter_common", generator_emitter_common_mod);
    lr_generator_mod.addImport("generator_switch_plan", generator_switch_plan_mod);
    const galley_grammar_procedures_mod = addGalleyGrammarProceduresModule(
        b,
        target,
        optimize,
        generator_common_mod,
    );
    const galley_grammar_config_mod = b.addModule("galley_grammar_config", .{
        .root_source_file = b.path("languages/galley/config.zig"),
        .target = target,
        .optimize = optimize,
    });
    const galley_grammar_error_messages_mod = b.addModule("galley_grammar_ll_error_messages", .{
        .root_source_file = b.path("languages/galley/ll_error_messages.zig"),
        .target = target,
        .optimize = optimize,
    });
    const galley_seed_parser = addGalleySeedParser(b);
    const galley_grammar = addGeneratedParserModule(
        b,
        target,
        optimize,
        "galley_grammar",
        "galley_grammar_parser",
        galley_seed_parser,
        galley_grammar_procedures_mod,
        galley_grammar_config_mod,
        galley_grammar_error_messages_mod,
        runtime_options_mod,
        signals_mod,
    );
    const galley_grammar_library_mod = galley_grammar.runtime_mod;

    const galley_generator_mod = b.addModule("galley_generator", .{
        .root_source_file = b.path("src/generator/api.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "generator_common", .module = generator_common_mod },
            .{ .name = "generator_config_file", .module = generator_config_file_mod },
            .{ .name = "galley_grammar", .module = galley_grammar_library_mod },
            .{ .name = "ll_generator", .module = ll_generator_mod },
            .{ .name = "lr_generator", .module = lr_generator_mod },
        },
    });

    return .{
        .runtime_options_mod = runtime_options_mod,
        .ast_memory_benchmark = ast_memory_benchmark,
        .syntax_error_stack_depth = syntax_error_stack_depth,
        .signals_mod = signals_mod,
        .generator_common_mod = generator_common_mod,
        .generator_switch_plan_mod = generator_switch_plan_mod,
        .generator_config_file_mod = generator_config_file_mod,
        .ll_generator_mod = ll_generator_mod,
        .lr_generator_mod = lr_generator_mod,
        .galley_grammar_procedures_mod = galley_grammar_procedures_mod,
        .galley_grammar_library_mod = galley_grammar_library_mod,
        .galley_generator_mod = galley_generator_mod,
        .galley_seed_parser = galley_seed_parser,
    };
}

/// Declares the git state that `git rev-parse HEAD` reads so a commit change
/// re-runs the configure phase. When the checkout cannot be tracked file by
/// file, the configure cache is poisoned instead.
fn declareGitCommitDependencies(b: *std.Build) void {
    const dot_git: std.Io.Dir = b.root.openDir(b.graph.io, ".git", .{}) catch |err| switch (err) {
        // No checkout yet: the stamp stays empty until a repository appears.
        error.FileNotFound => return,
        // .git is a worktree or submodule pointer file: the ref storage lives
        // outside the build root and cannot be declared file by file.
        else => {
            b.graph.poisonCache();
            return;
        },
    };
    defer dot_git.close(b.graph.io);

    // Directory declarations cover files appearing or disappearing; file
    // declarations cover their contents changing.
    b.dependOnDirectoryContents(b.path(".git"));
    declareConfigureDependencyIfPresent(b, ".git/HEAD");
    declareConfigureDependencyIfPresent(b, ".git/packed-refs");

    const head = dot_git.readFileAlloc(b.graph.io, "HEAD", b.allocator, .limited(4096)) catch |err| switch (err) {
        error.FileNotFound => return,
        else => {
            b.graph.poisonCache();
            return;
        },
    };
    defer b.allocator.free(head);

    const ref_prefix = "ref: ";
    const trimmed_head = std.mem.trim(u8, head, " \t\r\n");
    if (std.mem.startsWith(u8, trimmed_head, ref_prefix)) {
        const ref = trimmed_head[ref_prefix.len..];
        // The loose ref may not exist while the ref is packed; its directory
        // covers it appearing, and the file covers its contents changing.
        declareConfigureDependencyIfPresent(b, b.fmt(".git/{s}", .{ref}));
        if (std.fs.path.dirname(ref)) |ref_directory| {
            declareConfigureDependencyIfPresent(b, b.fmt(".git/{s}", .{ref_directory}));
        }
    }
    // A detached HEAD is fully described by .git/HEAD itself.
}

pub fn addGalleyCli(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    generator: GeneratorModules,
    options: GalleyCliOptions,
) GalleyCli {
    const galley_git_commit = options.galley_git_commit orelse blk: {
        declareGitCommitDependencies(b);
        // Read the stamp from the build root so value and declared inputs
        // come from the same repository, not the invoker's working directory.
        const build_root_dir = b.root.openDir(b.graph.io, ".", .{}) catch break :blk "";
        defer build_root_dir.close(b.graph.io);
        const result = std.process.run(b.allocator, b.graph.io, .{
            .argv = &.{ "git", "rev-parse", "HEAD" },
            .cwd = .{ .dir = build_root_dir },
        }) catch break :blk "";
        defer b.allocator.free(result.stdout);
        defer b.allocator.free(result.stderr);
        if (result.term != .exited or result.term.exited != 0) break :blk "";
        break :blk b.allocator.dupe(u8, std.mem.trim(u8, result.stdout, " \n\r")) catch "";
    };

    const cli_bootstrap_options = b.addOptions();
    cli_bootstrap_options.addOption([]const u8, "galley_git_url", options.galley_git_url);
    cli_bootstrap_options.addOption([]const u8, "galley_git_commit", galley_git_commit);
    const cli_bootstrap_options_mod = cli_bootstrap_options.createModule();

    // Zig 0.17 removed the @cImport builtin: the three time.h interfaces
    // the CLI uses are declared by hand in src/cli/c.zig, imported below
    // as `c`.
    const ctime_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/c.zig"),
        .target = target,
        .optimize = optimize,
    });

    const generator_cli_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/generator.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "galley_generator", .module = generator.galley_generator_mod },
            .{ .name = "cli_bootstrap_options", .module = cli_bootstrap_options_mod },
            .{ .name = "c", .module = ctime_mod },
        },
    });
    const generator_cli_exe = b.addExecutable(.{
        .name = "galley",
        .root_module = generator_cli_mod,
    });
    // The CLI formats timestamps through localtime/strftime. The runtime
    // module links libc on Linux/macOS only, so link it here for every
    // target; without this the Windows build has no CRT to link against.
    generator_cli_exe.root_module.link_libc = true;
    const install_generator_cli = b.addInstallArtifact(generator_cli_exe, .{});

    if (options.install_default) {
        b.getInstallStep().dependOn(&install_generator_cli.step);
    }
    if (options.add_galley_step) {
        const generator_cli_step = b.step("galley", "Build the Galley generator");
        generator_cli_step.dependOn(&install_generator_cli.step);
    }

    var generate_parser_file_exe: ?*std.Build.Step.Compile = null;
    if (options.include_generate_parser_file) {
        const generate_parser_file_mod = b.createModule(.{
            .root_source_file = b.path("src/tools/generate_parser_file.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "galley_generator", .module = generator.galley_generator_mod },
            },
        });
        generate_parser_file_exe = b.addExecutable(.{
            .name = "generate-parser-file",
            .root_module = generate_parser_file_mod,
        });
    }

    return .{
        .generator_cli_mod = generator_cli_mod,
        .generator_cli_exe = generator_cli_exe,
        .install_generator_cli = install_generator_cli,
        .generate_parser_file_exe = generate_parser_file_exe,
    };
}

pub fn parserName(
    allocator: std.mem.Allocator,
    parser_type: []const u8,
    entry_path: []const u8,
) ![]const u8 {
    return std.mem.concat(allocator, u8, &.{ parser_type, "-", entry_path });
}

pub fn addLanguageParser(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    generator: GeneratorModules,
    entry_path: []const u8,
    parser_type: []const u8,
) !?LanguageParser {
    const parser_file_name = try parserFileName(b.allocator, parser_type);
    defer b.allocator.free(parser_file_name);

    const parser_path = try std.fs.path.join(
        b.allocator,
        &.{ languages_path, entry_path, parser_file_name },
    );
    defer b.allocator.free(parser_path);

    // Whether the parser exists decides whether a parser module is wired
    // up; the directory's entries cover the file appearing or vanishing.
    if (std.fs.path.dirname(parser_path)) |parser_directory| {
        declareConfigureDependencyIfPresent(b, parser_directory);
    }
    const exists = b.root.access(b.graph.io, parser_path, .{});
    if (exists) |_| {} else |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    }

    return try addLanguageParserFromFile(
        b,
        target,
        optimize,
        generator,
        entry_path,
        parser_type,
        b.path(parser_path),
    );
}

pub fn addLanguageParserFromFile(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    generator: GeneratorModules,
    entry_path: []const u8,
    parser_type: []const u8,
    parser_file: std.Build.LazyPath,
) !LanguageParser {
    const procedures_path = try std.fs.path.join(
        b.allocator,
        &.{ languages_path, entry_path, "procedures.zig" },
    );
    defer b.allocator.free(procedures_path);

    const config_path = try std.fs.path.join(
        b.allocator,
        &.{ languages_path, entry_path, "config.zig" },
    );
    defer b.allocator.free(config_path);

    const error_messages_file_name = try errorMessagesFileName(b.allocator, parser_type);
    defer b.allocator.free(error_messages_file_name);
    const error_messages_path = try std.fs.path.join(
        b.allocator,
        &.{ languages_path, entry_path, error_messages_file_name },
    );
    defer b.allocator.free(error_messages_path);

    const procedures_mod = if (std.mem.eql(u8, entry_path, "galley"))
        addGalleyGrammarProceduresModule(b, target, optimize, generator.generator_common_mod)
    else
        b.createModule(.{
            .root_source_file = b.path(procedures_path),
            .target = target,
        });
    const config_mod = b.createModule(.{
        .root_source_file = b.path(config_path),
        .target = target,
    });
    const error_messages_mod = b.createModule(.{
        .root_source_file = b.path(error_messages_path),
        .target = target,
    });
    const parser_name = try parserName(b.allocator, parser_type, entry_path);
    const parser_module_name = try std.mem.concat(b.allocator, u8, &.{ parser_name, "-source" });

    const generated_parser = addGeneratedParserModule(
        b,
        target,
        optimize,
        parser_name,
        parser_module_name,
        parser_file,
        procedures_mod,
        config_mod,
        error_messages_mod,
        generator.runtime_options_mod,
        generator.signals_mod,
    );
    const galley_parser_mod = generated_parser.runtime_mod;
    const parser_mod = generated_parser.parser_mod;

    return .{
        .entry_path = entry_path,
        .parser_type = parser_type,
        .parser_name = parser_name,
        .galley_parser_mod = galley_parser_mod,
        .procedures_mod = procedures_mod,
        .config_mod = config_mod,
        .error_messages_mod = error_messages_mod,
        .parser_mod = parser_mod,
    };
}

pub fn addBenchmark(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    parser: LanguageParser,
) !void {
    const benchmark_run_step_name = try std.mem.concat(
        b.allocator,
        u8,
        &.{ "run-", parser.parser_name },
    );

    const benchmark_mod = b.createModule(.{
        .root_source_file = b.path("src/benchmarks/api_benchmark.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "galley", .module = parser.galley_parser_mod },
        },
    });
    const benchmark_exe = b.addExecutable(.{
        .name = parser.parser_name,
        .root_module = benchmark_mod,
    });
    const install_benchmark_artifact = b.addInstallArtifact(benchmark_exe, .{});

    const benchmark_description = try std.mem.concat(
        b.allocator,
        u8,
        &.{ "Benchmark the ", parser.entry_path, " parser API" },
    );

    const benchmark_step = b.step(parser.parser_name, benchmark_description);
    benchmark_step.dependOn(&install_benchmark_artifact.step);

    const benchmark_run_step = b.step(benchmark_run_step_name, benchmark_description);
    const benchmark_run_cmd = b.addRunArtifact(benchmark_exe);
    benchmark_run_step.dependOn(&benchmark_run_cmd.step);
    benchmark_run_cmd.step.dependOn(&install_benchmark_artifact.step);

    benchmark_run_cmd.addPassthruArgs();
}

pub fn addDelegatedTestStep(
    b: *std.Build,
    name: []const u8,
    description: []const u8,
    delegated_step_name: []const u8,
    test_filters: []const []const u8,
    ast_memory_benchmark: bool,
) *std.Build.Step {
    const step = b.step(name, description);
    const run_tests = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "build",
        "--build-file",
    });
    // 0.17 dropped b.graph.max_jobs: the delegated build no longer inherits
    // the outer -j limit.
    run_tests.addFileArg(b.path("build-tests.zig"));
    run_tests.addArg(delegated_step_name);
    run_tests.stdio = .inherit;
    run_tests.addArg("--summary");
    run_tests.addArg("all");
    if (ast_memory_benchmark) {
        run_tests.addArg("-Dast-memory-benchmark=true");
    }
    for (test_filters) |filter| {
        const option = b.allocator.print("-Dtest-filter={s}", .{filter}) catch @panic("OOM");
        run_tests.addArg(option);
    }
    run_tests.addArg("--");
    run_tests.addPassthruArgs();
    step.dependOn(&run_tests.step);
    return step;
}

pub fn expectSilentSuccess(run: *std.Build.Step.Run) void {
    run.expectStdOutEqual("");
    run.expectStdErrEqual("");
}

fn parserFileName(allocator: std.mem.Allocator, parser_type: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "_{s}-parser.zig", .{parser_type});
}

pub fn errorMessagesFileName(allocator: std.mem.Allocator, parser_type: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}_error_messages.zig", .{parser_type});
}
