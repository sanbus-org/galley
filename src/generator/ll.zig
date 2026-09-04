//! Public LL generator façade.
//!
//! Backend planning and Zig emission are internal implementation details; the
//! stable generator API remains defined here.

const std = @import("std");
const common = @import("generator_common");
const emitter_common = @import("generator_emitter_common");
const emitter = @import("ll_emitter.zig");
const planning = @import("ll_plan.zig");

pub const Options = common.Options;
pub const atomic_file = common.atomic_file;

/// Rewrites a prepared grammar's directly shared prefixes to fixpoint, the
/// same pass `emitParserWithOptions` applies before LL planning, so callers
/// that inspect LL productions (strict hook collection) see the emitted
/// shapes. Grammars with no factorable conflict are returned untouched.
pub const factorSharedPrefixes = planning.factorSharedPrefixes;

pub fn emitParser(allocator: std.mem.Allocator, grammar: anytype, writer: *std.Io.Writer) !void {
    return emitParserWithOptions(allocator, grammar, writer, .{});
}

pub fn emitParserWithOptions(
    allocator: std.mem.Allocator,
    grammar: anytype,
    writer: *std.Io.Writer,
    options: Options,
) !void {
    var prepared = try common.prepareGrammar(allocator, grammar, options, true);
    const plan = try planning.LLPlan.build(allocator, &prepared, options);
    return emitter.emit(allocator, &prepared, &plan, writer, options);
}

pub fn emitErrorMessagesWithOptions(
    allocator: std.mem.Allocator,
    grammar: anytype,
    writer: *std.Io.Writer,
    options: Options,
) !void {
    var prepared = try common.prepareGrammar(allocator, grammar, options, true);
    const plan = try planning.LLPlan.build(allocator, &prepared, options);
    return emitter_common.emitErrorMessageFile(writer, "LL", plan.error_message_specs.items);
}

test {
    _ = planning;
    _ = @import("ll_recovery.zig");
}
