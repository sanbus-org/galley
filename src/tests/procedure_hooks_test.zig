const std = @import("std");
const parser = @import("parser-under-test");
const procedures = parser.procedures;

var nested_same_session: ?*parser.Session = null;
var nested_separate_session: ?*parser.Session = null;
var nested_callback_called = false;
var concurrent_arrivals = std.atomic.Value(u8).init(0);

fn parse(input: []const u8) !void {
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);
}

fn exerciseNestedSessions(args: *parser.data_structures.ProcedureArguments) !void {
    nested_callback_called = true;
    const outer_runtime = args.context.runtime();
    try std.testing.expectEqualStrings("outer", outer_runtime.input_path orelse return error.MissingOuterInputPath);

    const same_session = nested_same_session orelse return error.MissingNestedSession;
    try std.testing.expectError(error.SessionInUse, same_session.parseBytes("c", "same"));
    try std.testing.expectError(error.SessionInUse, same_session.readLatest());
    try std.testing.expectError(error.SessionInUse, same_session.readCurrent());
    try std.testing.expectError(error.SessionInUse, same_session.editCurrent());
    try std.testing.expectError(error.SessionInUse, same_session.tryDeinit());

    const separate_session = nested_separate_session orelse return error.MissingSeparateSession;
    const nested_result = try separate_session.parseBytes("c", "inner");
    try std.testing.expectEqual(@as(usize, 1), nested_result.parsed_bytes);
    try std.testing.expect(args.context.runtime() == outer_runtime);
    try std.testing.expectEqualStrings("outer", args.context.runtimeConst().input_path orelse return error.MissingRestoredInputPath);
}

fn synchronizeRuntimeContexts(args: *parser.data_structures.ProcedureArguments) !void {
    const input_path = args.context.runtimeConst().input_path orelse return error.MissingConcurrentInputPath;
    _ = concurrent_arrivals.fetchAdd(1, .seq_cst);
    while (concurrent_arrivals.load(.seq_cst) != 2) try std.Thread.yield();
    try std.testing.expectEqualStrings(input_path, args.context.runtimeConst().input_path orelse return error.LostConcurrentInputPath);
}

const ConcurrentSessionParse = struct {
    session: *parser.Session,
    input_path: []const u8,
    parse_error: ?anyerror = null,

    fn run(self: *ConcurrentSessionParse) void {
        _ = self.session.parseBytes("k", self.input_path) catch |err| {
            self.parse_error = err;
            return;
        };
    }
};

fn expectNodeName(event: procedures.Event, expected: []const u8) !void {
    const variable = event.node_variable orelse return error.ExpectedProcedureNode;
    try std.testing.expectEqualStrings(expected, parser.parser.variables[variable]);
}

fn expectHookTargets(hook: procedures.Hook, expected: []const []const u8) !void {
    var matched: usize = 0;
    for (procedures.trace()) |event| {
        if (event.hook != hook) continue;
        const variable = event.node_variable orelse return error.ExpectedProcedureNode;
        if (variable == parser.data_structures.Node.invalid_variable) continue;
        if (matched == expected.len) return error.UnexpectedExtraProcedureHook;
        try std.testing.expectEqualStrings(expected[matched], parser.parser.variables[variable]);
        matched += 1;
    }
    try std.testing.expectEqual(expected.len, matched);
}

fn expectOrderedTrace(expected: []const procedures.Hook, node_name: []const u8) !void {
    var matched: usize = 0;
    for (procedures.trace()) |event| {
        const variable = event.node_variable orelse continue;
        if (variable == parser.data_structures.Node.invalid_variable) continue;
        if (!std.mem.eql(u8, node_name, parser.parser.variables[variable])) continue;
        if (matched == expected.len) return error.UnexpectedExtraProcedureHook;
        try std.testing.expectEqual(expected[matched], event.hook);
        matched += 1;
    }
    try std.testing.expectEqual(expected.len, matched);
}

fn expectFilteredHookOrder(expected: []const procedures.Hook, node_name: []const u8) !void {
    var matched: usize = 0;
    for (procedures.trace()) |event| {
        const variable = event.node_variable orelse continue;
        if (variable == parser.data_structures.Node.invalid_variable) continue;
        if (!std.mem.eql(u8, node_name, parser.parser.variables[variable])) continue;

        var belongs_to_sequence = false;
        for (expected) |expected_hook| {
            if (event.hook == expected_hook) {
                belongs_to_sequence = true;
                break;
            }
        }
        if (!belongs_to_sequence) continue;

        if (matched == expected.len) return error.UnexpectedExtraProcedureHook;
        try std.testing.expectEqual(expected[matched], event.hook);
        matched += 1;
    }
    try std.testing.expectEqual(expected.len, matched);
}

test "procedure-hooks LHS hooks run for every position" {
    procedures.resetTrace();
    try parse("lama");
    try expectHookTargets(.lhs, &.{ "LhsTarget", "LhsTarget" });
}

test "procedure-hooks RHS hooks are position-specific" {
    procedures.resetTrace();
    try parse("sxtx");
    try expectHookTargets(.rhs, &.{"RhsTarget"});
    for (procedures.trace()) |event| {
        if (event.hook == .rhs) try std.testing.expectEqual(@as(?usize, 1), event.node_text_start);
    }

    procedures.resetTrace();
    try parse("ux");
    try expectHookTargets(.rhs, &.{});
}

test "procedure-hooks production hooks are alternative-specific LHS hooks" {
    procedures.resetTrace();
    try parse("py");
    try expectHookTargets(.production, &.{"Start"});

    procedures.resetTrace();
    try parse("qy");
    try expectHookTargets(.production, &.{});
}

test "procedure-hooks chains run left to right" {
    procedures.resetTrace();
    try parse("c");
    try expectFilteredHookOrder(&.{ .chain_first, .chain_second }, "ChainTarget");
}

test "procedure-hooks automatic symbol hook matches its symbol" {
    procedures.resetTrace();
    try parse("vw");
    try expectHookTargets(.automatic_auto_target, &.{"AutoTarget"});
}

test "procedure-hooks general reduction runs once and last per variable" {
    procedures.resetTrace();
    try parse("gz");
    try expectHookTargets(.general, &.{ "GeneralLeaf", "Start" });
}

test "procedure-hooks phases follow local-to-global order" {
    procedures.resetTrace();
    try parse("o");
    try expectOrderedTrace(&.{
        .rhs_first,
        .rhs_second,
        .production_first,
        .production_second,
        .automatic_production,
        .lhs_first,
        .lhs_second,
        .automatic_symbol,
        .general,
    }, "Ordered");
}

test "procedure-hooks recursive RHS hooks run for each annotated occurrence" {
    procedures.resetTrace();
    try parse("rre");
    try expectHookTargets(.recursive_occurrence, &.{ "Recursive", "Recursive" });
}

test "procedure-hooks AST-suppressed variables do not run hooks" {
    procedures.resetTrace();
    try parse("h");
    try expectHookTargets(.hidden, &.{});
    for (procedures.trace()) |event| {
        if (event.hook == .general and event.node_variable == null) {
            return error.UnexpectedAstSuppressedReductionHook;
        }
    }
}

test "procedure-hooks node changes propagate through later phases" {
    procedures.resetTrace();
    try parse("dn");

    const expected = [_]procedures.Hook{
        .drop_occurrence,
        .after_drop_production,
        .after_drop_automatic_production,
        .after_drop_lhs,
        .after_drop_automatic_symbol,
        .general,
    };
    var matched: usize = 0;
    for (procedures.trace()) |event| {
        const belongs_to_drop_sequence = switch (event.hook) {
            .drop_occurrence,
            .after_drop_production,
            .after_drop_automatic_production,
            .after_drop_lhs,
            .after_drop_automatic_symbol,
            => true,
            .general => event.node_variable == null,
            else => false,
        };
        if (!belongs_to_drop_sequence) continue;

        if (matched == expected.len) return error.UnexpectedExtraProcedureHook;
        try std.testing.expectEqual(expected[matched], event.hook);
        try std.testing.expect(event.has_rule);
        if (matched == 0) {
            try expectNodeName(event, "DropTarget");
        } else {
            try std.testing.expectEqual(null, event.node_variable);
        }
        matched += 1;
    }
    try std.testing.expectEqual(expected.len, matched);
}

test "procedure-hooks terminal phases run local to global" {
    procedures.resetTrace();
    try parse("j");

    const expected = [_]procedures.Hook{
        .terminal_first,
        .terminal_second,
        .automatic_terminal,
        .general,
    };
    var matched: usize = 0;
    for (procedures.trace()) |event| {
        if (event.node_variable != parser.data_structures.Node.invalid_variable) continue;
        if (matched == expected.len) return error.UnexpectedExtraProcedureHook;
        try std.testing.expectEqual(expected[matched], event.hook);
        try std.testing.expect(!event.has_rule);
        matched += 1;
    }
    try std.testing.expectEqual(expected.len, matched);
}

test "procedure-hooks production indices follow alternatives under one LHS header" {
    procedures.resetTrace();
    try parse("i0");
    try expectHookTargets(.automatic_repeated_production, &.{});

    procedures.resetTrace();
    try parse("i1");
    try expectHookTargets(.automatic_repeated_production, &.{"IndexedTarget"});
}

test "procedure-hooks reject same-session nesting and preserve separate-session context" {
    var outer_session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer outer_session.deinit();
    var inner_session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer inner_session.deinit();

    nested_same_session = &outer_session;
    nested_separate_session = &inner_session;
    nested_callback_called = false;
    procedures.setNestedCallback(exerciseNestedSessions);
    defer procedures.setNestedCallback(null);
    defer nested_same_session = null;
    defer nested_separate_session = null;

    const result = try outer_session.parseBytes("k", "outer");
    try std.testing.expectEqual(@as(usize, 1), result.parsed_bytes);
    try std.testing.expect(nested_callback_called);
}

test "procedure-hooks keep concurrent session runtime contexts separate" {
    var first_session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer first_session.deinit();
    var second_session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer second_session.deinit();

    concurrent_arrivals.store(0, .seq_cst);
    procedures.setTraceEnabled(false);
    defer procedures.setTraceEnabled(true);
    procedures.setNestedCallback(synchronizeRuntimeContexts);
    defer procedures.setNestedCallback(null);

    var first = ConcurrentSessionParse{ .session = &first_session, .input_path = "first" };
    var second = ConcurrentSessionParse{ .session = &second_session, .input_path = "second" };
    const first_thread = try std.Thread.spawn(.{}, ConcurrentSessionParse.run, .{&first});
    const second_thread = try std.Thread.spawn(.{}, ConcurrentSessionParse.run, .{&second});
    first_thread.join();
    second_thread.join();

    if (first.parse_error) |err| return err;
    if (second.parse_error) |err| return err;
}

test "procedure-hooks AST nodes retain source text lengths" {
    if (comptime !parser.parser.is_ast_enabled) return;

    const input = "rre";
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    var context = session._makeContext(.{ .bytes = .{ .input = input[0 .. input.len + 1] } }, null);
    const result = try session._parseContext(&context);

    const root = result.ast_root orelse return error.MissingAstRoot;
    const allocator = &session.node_allocator;

    var zero_length_nodes: usize = 0;
    var stack: std.ArrayList(parser.data_structures.Node.Pointer) = .empty;
    defer stack.deinit(std.testing.allocator);
    try stack.append(std.testing.allocator, root);
    while (stack.pop()) |addr| {
        const node = allocator.at(addr);
        if (node.text_length == 0) zero_length_nodes += 1;
        var child = node.first_child;
        while (child != parser.data_structures.Node.invalid_pointer) {
            try stack.append(std.testing.allocator, child);
            child = allocator.at(child).next;
        }
    }
    try std.testing.expectEqual(@as(usize, 0), zero_length_nodes);

    const text = try parser.data_structures.Node.augmentedText(root, &context);
    try std.testing.expectEqualStrings(input, text);
}

var contention_in_hook = std.atomic.Value(bool).init(false);
var contention_attempted = std.atomic.Value(bool).init(false);
var contention_outcome: ?anyerror = null;

fn contentionHook(args: *parser.data_structures.ProcedureArguments) !void {
    _ = args;
    contention_in_hook.store(true, .seq_cst);
    while (!contention_attempted.load(.seq_cst)) try std.Thread.yield();
}

fn contentionAttempt(session: *parser.Session) void {
    while (!contention_in_hook.load(.seq_cst)) std.Thread.yield() catch {};
    _ = session.parseBytes("k", "contended") catch |err| {
        contention_outcome = err;
        contention_attempted.store(true, .seq_cst);
        return;
    };
    contention_outcome = error.ExpectedSessionInUse;
    contention_attempted.store(true, .seq_cst);
}

test "procedure-hooks same session contends fail-fast across threads" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();

    contention_in_hook.store(false, .seq_cst);
    contention_attempted.store(false, .seq_cst);
    contention_outcome = null;
    procedures.setNestedCallback(contentionHook);
    defer procedures.setNestedCallback(null);

    const contender = try std.Thread.spawn(.{}, contentionAttempt, .{&session});
    const result = try session.parseBytes("k", "owner");
    try std.testing.expectEqual(@as(usize, 1), result.parsed_bytes);
    contender.join();

    try std.testing.expect(contention_outcome.? == error.SessionInUse);
}

test "procedure-hooks stale results are nameable and distinct from parse failures" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();

    const first = try session.parseBytes("k", "first");
    const second = try session.parseBytes("k", "second");
    try std.testing.expectError(error.StaleParseResult, session.read(first));
    var read_guard = try session.read(second);
    defer read_guard.deinit();
    try std.testing.expectEqual(@as(usize, 1), second.parsed_bytes);
}

fn ignoreDiagnostic(_: []const u8) void {}

test "procedure-hooks current gates address the last successful parse" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();

    try std.testing.expectError(error.NoParseResult, session.readCurrent());
    try std.testing.expectError(error.NoParseResult, session.editCurrent());

    const first = try session.parseBytes("k", "first");
    {
        var read_guard = try session.readCurrent();
        defer read_guard.deinit();
        try std.testing.expectEqual(first.parsed_bytes, read_guard.result.parsed_bytes);
        try std.testing.expectEqual(first._session_generation, read_guard.result._session_generation);
    }
    {
        var edit_guard = try session.editCurrent();
        edit_guard.deinit();
    }

    const second = try session.parseBytes("k", "second");
    try std.testing.expectError(error.StaleParseResult, session.read(first));
    var read_guard = try session.readCurrent();
    defer read_guard.deinit();
    try std.testing.expectEqual(second._session_generation, read_guard.result._session_generation);
}

test "procedure-hooks a failed parse leaves the published result stale" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{ .syntax_error_reporter = &ignoreDiagnostic });
    defer session.deinit();

    _ = try session.parseBytes("k", "first");
    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes("z", "second"));
    try std.testing.expectError(error.StaleParseResult, session.readCurrent());
    try std.testing.expectError(error.StaleParseResult, session.editCurrent());

    _ = try session.parseBytes("k", "third");
    var read_guard = try session.readCurrent();
    read_guard.deinit();
}

test "procedure-hooks a first failed parse publishes nothing" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{ .syntax_error_reporter = &ignoreDiagnostic });
    defer session.deinit();

    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes("z", "only"));
    try std.testing.expectError(error.NoParseResult, session.readCurrent());
    try std.testing.expectError(error.NoParseResult, session.editCurrent());
}

test "procedure-hooks a lease holds the session until released" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();

    var lease = try session.parseBytesLeased("k", "leased");
    try std.testing.expectEqual(@as(usize, 1), lease.result.parsed_bytes);
    try std.testing.expectError(error.SessionInUse, session.readCurrent());
    try std.testing.expectError(error.SessionInUse, session.editCurrent());
    try std.testing.expectError(error.SessionInUse, session.parseBytes("k", "second"));
    lease.deinit();

    var read_guard = try session.readCurrent();
    defer read_guard.deinit();
    try std.testing.expectEqual(@as(usize, 1), read_guard.result.parsed_bytes);
}

test "procedure-hooks sequential protected parses stay usable" {
    if (!parser.stack_overflow_recovery_available) return error.SkipZigTest;

    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{ .stack_overflow_recovery = true });
    defer session.deinit();

    const first = try session.parseBytes("k", "first");
    try std.testing.expectEqual(@as(usize, 1), first.parsed_bytes);
    const second = try session.parseBytes("k", "second");
    try std.testing.expectEqual(@as(usize, 1), second.parsed_bytes);
}

var protected_nested_session: ?*parser.Session = null;
var protected_nested_called = false;

fn exerciseProtectedNesting(args: *parser.data_structures.ProcedureArguments) !void {
    _ = args;
    protected_nested_called = true;

    const inner = protected_nested_session orelse return error.MissingNestedSession;
    const nested_result = try inner.parseBytes("c", "inner");
    try std.testing.expectEqual(@as(usize, 1), nested_result.parsed_bytes);
}

test "procedure-hooks protected parse stacks a protected nested parse" {
    if (!parser.stack_overflow_recovery_available) return error.SkipZigTest;

    var outer_session = try parser.Session.init(std.testing.io, std.testing.allocator, .{ .stack_overflow_recovery = true });
    defer outer_session.deinit();
    var inner_session = try parser.Session.init(std.testing.io, std.testing.allocator, .{ .stack_overflow_recovery = true });
    defer inner_session.deinit();

    protected_nested_session = &inner_session;
    protected_nested_called = false;
    procedures.setNestedCallback(exerciseProtectedNesting);
    defer procedures.setNestedCallback(null);
    defer protected_nested_session = null;

    const result = try outer_session.parseBytes("k", "outer");
    try std.testing.expectEqual(@as(usize, 1), result.parsed_bytes);
    try std.testing.expect(protected_nested_called);

    // Disarm the nesting hook before reuse: it would otherwise re-enter
    // the sessions under test.
    procedures.setNestedCallback(null);

    // Session reuse proves both scopes cleaned up.
    const outer_again = try outer_session.parseBytes("k", "outer-again");
    try std.testing.expectEqual(@as(usize, 1), outer_again.parsed_bytes);
    const inner_again = try inner_session.parseBytes("k", "inner-again");
    try std.testing.expectEqual(@as(usize, 1), inner_again.parsed_bytes);
}

fn exerciseProtectedRejectsUnprotected(args: *parser.data_structures.ProcedureArguments) !void {
    _ = args;
    protected_nested_called = true;

    const inner = protected_nested_session orelse return error.MissingNestedSession;
    try std.testing.expectError(error.NestedParseDuringStackOverflowRecovery, inner.parseBytes("c", "inner"));
}

test "procedure-hooks protected parse rejects an unprotected nested parse" {
    if (!parser.stack_overflow_recovery_available) return error.SkipZigTest;

    var outer_session = try parser.Session.init(std.testing.io, std.testing.allocator, .{ .stack_overflow_recovery = true });
    defer outer_session.deinit();
    var inner_session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer inner_session.deinit();

    protected_nested_session = &inner_session;
    protected_nested_called = false;
    procedures.setNestedCallback(exerciseProtectedRejectsUnprotected);
    defer procedures.setNestedCallback(null);
    defer protected_nested_session = null;

    const result = try outer_session.parseBytes("k", "outer");
    try std.testing.expectEqual(@as(usize, 1), result.parsed_bytes);
    try std.testing.expect(protected_nested_called);

    // The rejected nested parse ran before any session mutation: the inner
    // session's generation, node storage, owned input, and input path are
    // untouched, so it reuses cleanly.
    try std.testing.expectEqual(@as(usize, 0), inner_session.generation);
    try std.testing.expect(inner_session.owned_input == null);
    try std.testing.expect(inner_session.runtime_context.input_path == null);
    if (comptime parser.parser.is_ast_enabled) {
        try std.testing.expectEqual(@as(usize, 0), inner_session.node_allocator.totalNodeCapacity());
    }

    // Disarm the nesting hook before reuse: it would otherwise re-enter
    // the sessions under test.
    procedures.setNestedCallback(null);

    const outer_again = try outer_session.parseBytes("k", "outer-again");
    try std.testing.expectEqual(@as(usize, 1), outer_again.parsed_bytes);
    const inner_again = try inner_session.parseBytes("k", "inner-again");
    try std.testing.expectEqual(@as(usize, 1), inner_again.parsed_bytes);
}
