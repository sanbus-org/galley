//! Public LR generator façade.
//!
//! Backend planning and Zig emission are internal implementation details; the
//! stable generator API remains defined here.

const std = @import("std");
const common = @import("generator_common");
const emitter_common = @import("generator_emitter_common");
const emitter = @import("lr_emitter.zig");
const planning = @import("lr_plan.zig");

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
    const prepared = try common.prepareGrammar(allocator, grammar, options, false);
    const plan = try planning.LRPlan.build(allocator, &prepared);
    return emitter.emit(allocator, &prepared, &plan, writer, options);
}

pub fn emitErrorMessagesWithOptions(
    allocator: std.mem.Allocator,
    grammar: anytype,
    writer: *std.Io.Writer,
    options: Options,
) !void {
    const prepared = try common.prepareGrammar(allocator, grammar, options, false);
    const plan = try planning.LRPlan.build(allocator, &prepared);
    return emitter_common.emitErrorMessageFile(writer, "LR", plan.error_message_specs.items);
}

pub fn canonicalTopologyEqualForTesting(
    allocator: std.mem.Allocator,
    lhs_grammar: anytype,
    rhs_grammar: anytype,
) !bool {
    const lhs_prepared = try common.prepareGrammar(allocator, lhs_grammar, .{}, false);
    const lhs_plan = try planning.LRPlan.build(allocator, &lhs_prepared);
    const rhs_prepared = try common.prepareGrammar(allocator, rhs_grammar, .{}, false);
    const rhs_plan = try planning.LRPlan.build(allocator, &rhs_prepared);
    return lhs_plan.topologyEqual(&rhs_plan);
}

pub fn canonicalStateCountForTesting(
    allocator: std.mem.Allocator,
    grammar: anytype,
) !usize {
    const prepared = try common.prepareGrammar(allocator, grammar, .{}, false);
    const plan = try planning.LRPlan.build(allocator, &prepared);
    return plan.states.items.len;
}

test {
    _ = planning;
    _ = @import("lr_recovery.zig");
}
