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

pub fn emitParser(allocator: std.mem.Allocator, grammar: anytype, writer: *std.Io.Writer) !void {
    return emitParserWithOptions(allocator, grammar, writer, .{});
}

pub fn emitParserWithOptions(
    allocator: std.mem.Allocator,
    grammar: anytype,
    writer: *std.Io.Writer,
    options: Options,
) !void {
    const prepared = try common.prepareGrammar(allocator, grammar, options, true);
    const plan = try planning.LLPlan.build(allocator, &prepared, options);
    return emitter.emit(allocator, &prepared, &plan, writer, options);
}

pub fn emitErrorMessagesWithOptions(
    allocator: std.mem.Allocator,
    grammar: anytype,
    writer: *std.Io.Writer,
    options: Options,
) !void {
    const prepared = try common.prepareGrammar(allocator, grammar, options, true);
    const plan = try planning.LLPlan.build(allocator, &prepared, options);
    return emitter_common.emitErrorMessageFile(writer, "LL", plan.error_message_specs.items);
}

test {
    _ = planning;
    _ = @import("ll_recovery.zig");
}
