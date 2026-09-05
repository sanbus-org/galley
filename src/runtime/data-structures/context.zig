const builtin = @import("builtin");
const root = @import("galley");
const std = @import("std");
const data_structures = root.data_structures;
const string_utilities = root.string_utilities;

const NewlineSummary = struct {
    count: u32 = 0,
    last: ?usize = null,
};

fn summarizeNewlines(input: []const u8) NewlineSummary {
    var summary = NewlineSummary{};
    for (input, 0..) |byte, index| {
        switch (byte) {
            '\n', '\x01', '\x02' => {
                summary.count += 1;
                summary.last = index;
            },
            else => {},
        }
    }
    return summary;
}

pub const RuntimeContext = struct {
    io: std.Io,
    input_path: ?[]const u8 = null,
    arena_allocator: std.mem.Allocator,
    /// Every diagnostic recorded during the current parse, in recording
    /// order. Syntax records are bounded by the generated parsers' limit
    /// checks against `max_errors` (indentation records at most once per
    /// parse); semantic records are unbounded and hooks limit themselves
    /// through `Context.semanticErrorCount`.
    /// Arena-backed: valid until the next parse begins.
    recorded_diagnostics: std.ArrayList(root.ParseDiagnostic) = .empty,
    /// Message rendered for the most recent diagnostic by the grammar's
    /// error-message hooks (or their generic fallback). Arena-backed: valid
    /// until the next parse begins. Bindings surface this through
    /// `galley_diagnostic_message`.
    last_rendered_message: ?[]const u8 = null,
    max_errors: usize = 10,
    recovery_window: usize = 500,
    syntax_error_stack_depth: usize = 0,
    syntax_error_count: usize = 0,
    /// Aggregated semantic errors reported by procedure hooks through the
    /// single `reportSemanticError` gate. Unbounded by design; hooks read
    /// `Context.semanticErrorCount` to limit themselves.
    semantic_error_count: usize = 0,
    syntax_recovery_position: ?usize = null,
    explicit_recovery_position: ?usize = null,
    explicit_recovery_target_id: ?usize = null,
    pending_syntax_error_site: ?usize = null,
    syntax_error_reporter: ?root.SyntaxErrorMessageReporter = null,
    /// Session-owned message override table, wired at parse start. Lookup
    /// happens only inside cold syntax-error paths.
    message_overrides: ?*const std.StringHashMapUnmanaged([]const u8) = null,

    /// Returns the most recently recorded diagnostic of the current (or
    /// previous) parse, if any.
    pub fn lastDiagnostic(self: *const RuntimeContext) ?root.ParseDiagnostic {
        if (self.recorded_diagnostics.items.len == 0) return null;
        return self.recorded_diagnostics.items[self.recorded_diagnostics.items.len - 1];
    }
    /// Resolves a rendered message for `diagnostic` through the template
    /// tables in chain order: session-owned overrides first, then the
    /// consumer's comptime `error_messages` table from `config.zig`. Both
    /// tables share one key walk — the innermost in-progress variable name,
    /// then the universal `"*"` key — and one placeholder expansion
    /// (`{line}`, `{column}`, `{unexpected}`, `{expected}`, `{context}`;
    /// unknown placeholders pass through). Returns null when no table
    /// applies.
    pub fn resolveMessageOverride(self: *RuntimeContext, diagnostic: root.ParseDiagnostic, comptime config_messages: anytype) ?[]const u8 {
        const template = self.sessionTemplate(diagnostic) orelse configTemplate(config_messages, diagnostic) orelse return null;
        return self.expandPlaceholders(template, diagnostic);
    }

    fn sessionTemplate(self: *RuntimeContext, diagnostic: root.ParseDiagnostic) ?[]const u8 {
        const overrides = self.message_overrides orelse return null;
        if (innermostVariableName(diagnostic)) |name| {
            if (overrides.get(name)) |template| return template;
        }
        return overrides.get("*");
    }

    /// The innermost in-progress variable name carried by `diagnostic`, if
    /// its context records one.
    fn innermostVariableName(diagnostic: root.ParseDiagnostic) ?[]const u8 {
        switch (diagnostic) {
            .syntax => switch (diagnostic.syntax.context) {
                .while_parsing => |names| {
                    if (names.len > 0) return names[0];
                },
                else => {},
            },
            .semantic => |semantic| return semantic.variable,
            .indentation => {},
        }
        return null;
    }

    /// Looks up `diagnostic`'s key in the consumer's config.zig
    /// `error_messages` table with the same walk as session overrides.
    fn configTemplate(comptime config_messages: anytype, diagnostic: root.ParseDiagnostic) ?[]const u8 {
        _ = &config_messages;
        if (innermostVariableName(diagnostic)) |name| {
            if (structFieldValue(@TypeOf(config_messages), config_messages, name)) |template| return template;
        }
        return structFieldValue(@TypeOf(config_messages), config_messages, "*");
    }

    fn structFieldValue(comptime Messages: type, values: Messages, name: []const u8) ?[]const u8 {
        // Address-take silencer: stays legal whether the unrolled loop
        // below touches the value or not.
        _ = &values;
        inline for (@typeInfo(Messages).@"struct".fields) |field| {
            // String literals give fields pointer-to-array types, so no
            // exact-type guard here — implicit coercion to the slice return
            // type accepts them.
            if (std.mem.eql(u8, field.name, name)) return @field(values, field.name);
        }
        return null;
    }

    fn appendPlaceholder(output: *std.Io.Writer.Allocating, placeholder: []const u8, diagnostic: root.ParseDiagnostic) void {
        const writer = &output.writer;
        if (std.mem.eql(u8, placeholder, "line")) {
            writer.print("{d}", .{switch (diagnostic) {
                .syntax => |syntax| syntax.line,
                .semantic => |semantic| semantic.line,
                .indentation => |indentation| indentation.line,
            }}) catch {};
        } else if (std.mem.eql(u8, placeholder, "column")) {
            writer.print("{d}", .{switch (diagnostic) {
                .syntax => |syntax| syntax.column,
                .semantic => |semantic| semantic.column,
                .indentation => |indentation| indentation.column,
            }}) catch {};
        } else if (std.mem.eql(u8, placeholder, "unexpected")) {
            switch (diagnostic) {
                .syntax => |syntax| writer.writeAll(syntax.unexpected_token) catch {},
                .semantic, .indentation => {},
            }
        } else if (std.mem.eql(u8, placeholder, "expected")) {
            switch (diagnostic) {
                .syntax => |syntax| {
                    for (syntax.expected_tokens, 0..) |token, index| {
                        if (index != 0) writer.writeAll(", ") catch {};
                        writer.print("'{s}'", .{token}) catch {};
                    }
                },
                .semantic, .indentation => {},
            }
        } else if (std.mem.eql(u8, placeholder, "message")) {
            switch (diagnostic) {
                .semantic => |semantic| writer.writeAll(semantic.message) catch {},
                .syntax, .indentation => {},
            }
        } else if (std.mem.eql(u8, placeholder, "context")) {
            switch (diagnostic) {
                .syntax => |syntax| switch (syntax.context) {
                    .while_parsing => |names| {
                        for (names, 0..) |name, index| {
                            if (index != 0) writer.writeAll(" <~ ") catch {};
                            writer.writeAll(name) catch {};
                        }
                    },
                    else => {},
                },
                .semantic => |semantic| writer.writeAll(semantic.variable) catch {},
                .indentation => {},
            }
        } else {
            writer.print("{{{s}}}", .{placeholder}) catch {};
        }
    }

    fn expandPlaceholders(self: *RuntimeContext, template: []const u8, diagnostic: root.ParseDiagnostic) ?[]const u8 {
        var output = std.Io.Writer.Allocating.init(self.arena_allocator);
        const writer = &output.writer;
        var rest = template;
        while (std.mem.indexOfScalar(u8, rest, '{')) |opening| {
            const close = std.mem.indexOfScalarPos(u8, rest, opening, '}') orelse break;
            writer.writeAll(rest[0..opening]) catch return null;
            appendPlaceholder(&output, rest[opening + 1 .. close], diagnostic);
            rest = rest[close + 1 ..];
        }
        writer.writeAll(rest) catch return null;
        return output.written();
    }
};

var runtime_registry_mutex: std.atomic.Mutex = .unlocked;
var runtime_registry_head: ?*RuntimeContextRegistration = null;

/// Maximum number of in-progress variables that the LL parser tracks for
/// syntax error reporting. The generated `syntax_error_stack_depth` const must
/// not exceed this value.
pub const max_syntax_error_stack_depth = 64;

/// Ring of the most recently entered LL parse variables, innermost first.
/// Consecutive repeats of the same variable are suppressed so self-recursive
/// rules (for example `DigitTail -> digit DigitTail`) occupy a single slot.
pub const SyntaxErrorStack = struct {
    entries: [max_syntax_error_stack_depth][]const u8 = .{""} ** max_syntax_error_stack_depth,
    depth: usize = 0,
    head: usize = 0,

    const Self = @This();

    /// Pushes `name` and returns whether an entry was added. Returns false when
    /// the innermost entry is already `name`, so the matching pop is skipped.
    pub fn push(self: *Self, name: []const u8) bool {
        if (self.depth > 0) {
            const top = (self.head + max_syntax_error_stack_depth - 1) % max_syntax_error_stack_depth;
            if (std.mem.eql(u8, self.entries[top], name)) return false;
        }
        self.entries[self.head] = name;
        self.head = (self.head + 1) % max_syntax_error_stack_depth;
        if (self.depth < max_syntax_error_stack_depth) self.depth += 1;
        return true;
    }

    pub fn pop(self: *Self) void {
        if (self.depth > 0) {
            self.depth -= 1;
            self.head = (self.head + max_syntax_error_stack_depth - 1) % max_syntax_error_stack_depth;
        }
    }

    /// Writes the most recent entries into `out` (innermost first, up to
    /// `out.len` entries) and returns the number written.
    pub fn lastSlice(self: *const Self, out: [][]const u8) usize {
        const count = @min(out.len, self.depth);
        var index: usize = 0;
        while (index < count) : (index += 1) {
            const slot = (self.head + max_syntax_error_stack_depth - 1 - index) % max_syntax_error_stack_depth;
            out[index] = self.entries[slot];
        }
        return count;
    }

    test "ring reports innermost-first with consecutive repeats suppressed" {
        var stack: SyntaxErrorStack = .{};
        try std.testing.expect(stack.push("Value"));
        try std.testing.expect(stack.push("ArrayMembers"));
        try std.testing.expect(stack.push("Value"));
        try std.testing.expect(stack.push("DigitTail"));
        try std.testing.expect(!stack.push("DigitTail"));

        var scratch: [max_syntax_error_stack_depth][]const u8 = undefined;
        const count = stack.lastSlice(&scratch);
        try std.testing.expectEqual(@as(usize, 4), count);
        try std.testing.expectEqualStrings("DigitTail", scratch[0]);
        try std.testing.expectEqualStrings("Value", scratch[1]);
        try std.testing.expectEqualStrings("ArrayMembers", scratch[2]);
        try std.testing.expectEqualStrings("Value", scratch[3]);

        stack.pop();
        try std.testing.expect(stack.push("DigitTail"));
        stack.pop();
        stack.pop();
        stack.pop();
        stack.pop();
        try std.testing.expectEqual(@as(usize, 0), stack.lastSlice(&scratch));
    }
};

fn lockRuntimeRegistry() void {
    while (!runtime_registry_mutex.tryLock()) std.atomic.spinLoopHint();
}

pub const Context = struct {
    pub const BytesSource = struct {
        input: []const u8,
        offset: usize = 0,
    };

    pub const Source = union(enum) {
        file: std.Io.File.Reader,
        bytes: BytesSource,
    };

    token: data_structures.Token = .{},
    source: Source = .{ .bytes = .{ .input = &[_]u8{0} } },
    chunk_buffer: []u8 = undefined,
    input_read_failed: bool = false,

    // These fields are defined only when non-indentation input streaming is enabled.
    file_input: if (root.input_streaming_enabled and !root.config.indentation_syntax and root.source_retention_enabled) []u8 else void = if (root.input_streaming_enabled and !root.config.indentation_syntax and root.source_retention_enabled) &.{} else {},
    input_end: if (root.input_streaming_enabled and !root.config.indentation_syntax) usize else void = if (root.input_streaming_enabled and !root.config.indentation_syntax) 0 else {},
    loaded_end: if (root.input_streaming_enabled and !root.config.indentation_syntax) usize else void = if (root.input_streaming_enabled and !root.config.indentation_syntax) 0 else {},
    window_base: if (root.sliding_input_enabled and !root.config.indentation_syntax) usize else void = if (root.sliding_input_enabled and !root.config.indentation_syntax) 0 else {},
    input_eof: if (root.sliding_input_enabled and !root.config.indentation_syntax) bool else void = if (root.sliding_input_enabled and !root.config.indentation_syntax) false else {},

    // These fields are defined only when indentation syntax is enabled
    indent_width: if (root.config.indentation_syntax) u16 else void = if (root.config.indentation_syntax) 0 else {},
    current_indent: if (root.config.indentation_syntax) u16 else void = if (root.config.indentation_syntax) 0 else {},
    indentation_error: if (root.config.indentation_syntax) bool else void = if (root.config.indentation_syntax) false else {},
    seek: if (root.config.indentation_syntax) usize else void = if (root.config.indentation_syntax) 0 else {},
    read_bytes: if (root.config.indentation_syntax) usize else void = if (root.config.indentation_syntax) 0 else {},

    // These fields are defined only when ast is enabled
    node_allocator: if (root.parser.is_ast_enabled) *data_structures.ASTAllocator else void = if (root.parser.is_ast_enabled) undefined else {},

    /// Host-owned pointer copied from `Session.user_data` for this parse.
    user_data: ?*anyopaque = null,

    // These fields are defined based on build mode and generated-parser options.
    verbosity: if (builtin.mode == .Debug) usize else void = if (builtin.mode == .Debug) 0 else {},

    line: if (root.position_tracking_enabled) u32 else void = if (root.position_tracking_enabled) 1 else {},
    column: if (root.position_tracking_enabled) u32 else void = if (root.position_tracking_enabled) 1 else {},

    line_offsets: if (root.position_tracking_enabled)
        data_structures.Offsets
    else
        void = if (root.position_tracking_enabled) .{} else {},
    column_offsets: if (root.position_tracking_enabled)
        data_structures.Offsets
    else
        void = if (root.position_tracking_enabled) .{} else {},

    // These fields are defined only when the generated parser reports the
    // in-progress variable stack in syntax errors.
    syntax_error_stack: if (root.parser.is_syntax_error_stack_enabled)
        SyntaxErrorStack
    else
        void = if (root.parser.is_syntax_error_stack_enabled) .{} else {},

    const Self = @This();

    pub noinline fn runtime(self: *Self) *RuntimeContext {
        return registeredRuntimeContext(self);
    }

    pub noinline fn runtimeConst(self: *const Self) *const RuntimeContext {
        return registeredRuntimeContext(self);
    }

    pub inline fn verbosityLevel(self: *const Self) usize {
        if (comptime builtin.mode == .Debug) {
            return self.verbosity;
        }
        return 0;
    }

    pub inline fn pushSyntaxErrorVariable(self: *Self, name: []const u8) bool {
        if (comptime root.parser.is_syntax_error_stack_enabled) return self.syntax_error_stack.push(name);
        return false;
    }

    pub inline fn popSyntaxErrorVariable(self: *Self) void {
        if (comptime root.parser.is_syntax_error_stack_enabled) self.syntax_error_stack.pop();
    }

    /// Retains `diagnostic` in the parse's recorded-diagnostics list. The
    /// arena allocation keeps every record valid until the next parse begins.
    fn retainDiagnostic(self: *Self, diagnostic: root.ParseDiagnostic) !void {
        const runtime_context = self.runtime();
        try runtime_context.recorded_diagnostics.append(runtime_context.arena_allocator, diagnostic);
    }

    pub fn recordSyntaxDiagnostic(
        self: *@This(),
        diagnostic_context: root.SyntaxDiagnosticContext,
        expected_tokens: []const []const u8,
    ) !void {
        if (self.input_read_failed) return error.ReadFailed;
        if (comptime root.config.indentation_syntax) {
            if (self.indentation_error) return error.IndentationError;
        }
        var effective_diagnostic_context = diagnostic_context;
        if (comptime root.parser.is_syntax_error_stack_enabled) {
            const runtime_context = self.runtime();
            const depth = @min(runtime_context.syntax_error_stack_depth, max_syntax_error_stack_depth);
            var scratch: [max_syntax_error_stack_depth][]const u8 = undefined;
            const count = self.syntax_error_stack.lastSlice(scratch[0..depth]);
            if (count > 0) {
                const names = try runtime_context.arena_allocator.alloc([]const u8, count);
                for (scratch[0..count], 0..) |name, index| names[index] = name;
                effective_diagnostic_context = .{ .while_parsing = names };
            }
        }
        const unexpected_token = try self.runtime().arena_allocator.dupe(u8, self.diagnosticTokenItems());
        try self.retainDiagnostic(.{
            .syntax = .{
                .line = if (comptime root.position_tracking_enabled) self.line else 0,
                .column = if (comptime root.position_tracking_enabled) self.column else 0,
                .unexpected_token = unexpected_token,
                .expected_tokens = expected_tokens,
                .context = effective_diagnostic_context,
            },
        });
        self.runtime().syntax_error_count += 1;
    }

    fn diagnosticTokenItems(self: *Self) []const u8 {
        const original = self.token.items();
        if (original.len == 0 or original[0] < 0x80) return original;

        const sequence_length = std.unicode.utf8ByteSequenceLength(original[0]) catch return original;
        if (sequence_length > original.len) {
            _ = self.head(u8, @intCast(sequence_length - 1));
        }

        const loaded = self.token.items();
        if (sequence_length > loaded.len) return original;
        _ = std.unicode.utf8Decode(loaded[0..sequence_length]) catch return original;
        return loaded[0..@max(original.len, sequence_length)];
    }

    pub inline fn syntaxErrorLimitReached(self: *const Self) bool {
        return self.runtimeConst().syntax_error_count >= self.runtimeConst().max_errors;
    }

    pub inline fn hasSyntaxErrors(self: *const Self) bool {
        return self.runtimeConst().syntax_error_count != 0;
    }

    pub inline fn semanticErrorCount(self: *const Self) usize {
        return self.runtimeConst().semantic_error_count;
    }

    pub inline fn hasSemanticErrors(self: *const Self) bool {
        return self.runtimeConst().semantic_error_count != 0;
    }

    pub inline fn recoveryWindow(self: *const Self) usize {
        return self.runtimeConst().recovery_window;
    }

    pub inline fn beginSyntaxRecovery(self: *Self) bool {
        const runtime_context = self.runtime();
        const position: usize = self.pos();
        if (runtime_context.syntax_recovery_position == position) return false;
        runtime_context.syntax_recovery_position = position;
        return true;
    }

    pub inline fn finishSyntaxRecovery(self: *Self) void {
        self.runtime().syntax_recovery_position = null;
    }

    pub fn tryExplicitRecovery(
        self: *Self,
        target_id: usize,
        target: root.SyntaxRecoveryTarget,
        points: []const root.SyntaxRecoveryPoint,
    ) !bool {
        if (self.syntaxErrorLimitReached() or points.len == 0) return false;

        const runtime_context = self.runtime();
        const position: usize = self.pos();
        if (runtime_context.explicit_recovery_position == position and
            runtime_context.explicit_recovery_target_id == target_id)
        {
            return false;
        }

        const lookahead = try self.recoveryLookahead();
        if (lookahead.len == 0 or lookahead[0] == 0) return false;
        const upper = @min(runtime_context.recovery_window, lookahead.len);
        var winning_point: ?usize = null;
        var winning_offset: usize = 0;
        var offset: usize = 0;
        while (offset < upper) : (offset += 1) {
            if (lookahead[offset] == 0) break;
            for (points, 0..) |point, point_index| {
                if (point.terminal.len > lookahead.len - offset or
                    !std.mem.eql(u8, lookahead[offset..][0..point.terminal.len], point.terminal))
                {
                    continue;
                }
                if (winning_point == null or point.terminal.len > points[winning_point.?].terminal.len) {
                    winning_point = point_index;
                    winning_offset = offset;
                }
            }
            if (winning_point != null) break;
        }

        const point = if (winning_point) |index| points[index] else return false;
        runtime_context.explicit_recovery_position = position;
        runtime_context.explicit_recovery_target_id = target_id;
        const skip_amount = winning_offset + if (point.@"resume" == .after) point.terminal.len else 0;
        self.skipRecoveryInput(skip_amount);
        try self.attachSyntaxRecovery(.{
            .target = target,
            .terminal = point.terminal,
            .@"resume" = point.@"resume",
        });
        return true;
    }

    pub fn attachSyntaxRecovery(self: *Self, recovery: root.SyntaxRecovery) !void {
        const records = &self.runtime().recorded_diagnostics;
        if (records.items.len == 0) return error.MissingSyntaxDiagnostic;
        const diagnostic = &records.items[records.items.len - 1];
        switch (diagnostic.*) {
            .syntax => |*syntax| syntax.recovery = recovery,
            .semantic, .indentation => return error.MissingSyntaxDiagnostic,
        }
    }

    pub inline fn setPendingSyntaxErrorSite(self: *Self, site: usize) void {
        self.runtime().pending_syntax_error_site = site;
    }

    pub inline fn pendingSyntaxErrorSite(self: *const Self) ?usize {
        return self.runtimeConst().pending_syntax_error_site;
    }

    pub inline fn clearPendingSyntaxErrorSite(self: *Self) void {
        self.runtime().pending_syntax_error_site = null;
    }

    pub fn skipRecoveryInput(self: *Self, amount: usize) void {
        for (0..amount) |_| {
            _ = self.head(u8, 0);
            self.releaseToken(1);
        }
    }

    /// Captures raw source bytes from the current source position through the
    /// next occurrence of `terminator`, consuming them without lexing,
    /// indentation processing, or escape decoding. When `consume` is true the
    /// parser resumes immediately after the terminator with line and column
    /// advanced over the captured bytes; when false the terminator bytes are
    /// left in the stream and the parser resumes at its first byte, so the
    /// terminator is parsed normally by the surrounding rule. When `terminator`
    /// never reappears the parse fails with `error.UnterminatedRawString`,
    /// mirroring recovery points by carrying the expected terminator bytes in
    /// the recorded diagnostic.
    ///
    /// Verbatim capture works with retained source and with input streaming; in
    /// the streaming case the terminator is found by scanning forward through
    /// the loaded regions and extending the input on demand, so the captured
    /// body never needs to fit inside a single loaded region.
    pub fn captureVerbatim(self: *Self, terminator: []const u8, consume: bool) !void {
        const body_start = self.currentTokenSourceOffset();
        if (comptime root.input_streaming_enabled) {
            return self.captureVerbatimStreaming(body_start, terminator, consume);
        }

        const body_end = if (comptime root.config.indentation_syntax)
            findVerbatimTerminatorEnd(self.chunk_buffer, body_start, terminator, consume) orelse {
                try self.recordUnterminatedVerbatim(terminator);
                return error.UnterminatedRawString;
            }
        else
            findVerbatimTerminatorEnd(self.token.buffer, body_start, terminator, consume) orelse {
                try self.recordUnterminatedVerbatim(terminator);
                return error.UnterminatedRawString;
            };

        if (comptime root.config.indentation_syntax) {
            // Any cleaned tokens already buffered from the captured region are
            // part of the opaque raw body; discard them (together with their
            // line/column offsets) and resume lexing from the terminator end.
            self.indentation_error = false;
            if (comptime root.position_tracking_enabled) {
                const discard = @min(self.token.len, self.line_offsets.len);
                if (discard != 0) {
                    self.line_offsets.pop(@intCast(discard));
                    self.column_offsets.pop(@intCast(discard));
                }
            }
            self.token.resetBuffered();
            self.seek = body_end;
            self.current_indent = @intCast(lineIndentOf(self.chunk_buffer, body_start) / @max(self.indent_width, 1));
            if (comptime root.position_tracking_enabled) {
                advanceVerbatimPositions(&self.line, &self.column, self.chunk_buffer[body_start..body_end]);
            }
        } else {
            self.token.head = body_end;
            self.token.len = 0;
            if (comptime root.position_tracking_enabled) {
                advanceVerbatimPositions(&self.line, &self.column, self.token.buffer[body_start..body_end]);
            }
        }
    }

    /// Result of a streaming verbatim terminator scan, in source coordinates.
    const VerbatimCapture = struct {
        body_end: usize,
        newlines: u32,
        last_newline: ?usize,
    };

    /// Ring of the most recent newline offsets recorded by a streaming verbatim
    /// scan, relative to the captured body start. The ring holds up to
    /// `terminator.len + 1` entries so that when the terminator itself contains
    /// newline bytes a non-consuming capture (`consume = false`) can still
    /// recover the last newline preceding the terminator after the terminator's
    /// own newlines overwrote the running `last_newline`.
    const NewlineTail = struct {
        entries: []usize = &.{},
        head: usize = 0,
        count: usize = 0,

        fn push(self: *NewlineTail, index: usize) void {
            if (self.entries.len == 0) return;
            self.entries[self.head] = index;
            self.head = (self.head + 1) % self.entries.len;
            if (self.count < self.entries.len) self.count += 1;
        }

        /// Most recent recorded newline offset strictly before `span_len`, or
        /// `null` when every retained newline falls at or past it.
        fn lastBefore(self: *const NewlineTail, span_len: usize) ?usize {
            if (self.entries.len == 0) return null;
            var k: usize = 0;
            const n = self.count;
            while (k < n) : (k += 1) {
                const slot = (self.head + self.entries.len - 1 - k) % self.entries.len;
                if (self.entries[slot] < span_len) return self.entries[slot];
            }
            return null;
        }
    };

    /// Newline bookkeeping for a streaming verbatim scan, so a non-consuming
    /// capture (`consume = false`) can exclude the terminator's bytes from the
    /// position statistics while a consuming capture keeps the full scan totals.
    const VerbatimScan = struct {
        newlines: u32 = 0,
        last_newline: ?usize = null,
        tail: NewlineTail = .{},

        /// Reserves the newline tail when the terminator contains newline bytes
        /// and the capture leaves it unconsumed; otherwise leaves it empty and
        /// `finish` uses the running `last_newline` directly.
        fn init(self: *VerbatimScan, allocator: std.mem.Allocator, terminator: []const u8, consume: bool) !void {
            if (consume) return;
            for (terminator) |byte| {
                if (byte == '\n') {
                    self.tail.entries = try allocator.alloc(usize, terminator.len + 1);
                    return;
                }
            }
        }

        fn record(self: *VerbatimScan, index: usize) void {
            self.newlines += 1;
            self.last_newline = index;
            self.tail.push(index);
        }

        /// Finalizes the capture at a matched terminator, backing the
        /// terminator bytes out of the statistics when they stay unconsumed.
        fn finish(self: *const VerbatimScan, frontier: usize, body_start: usize, terminator: []const u8, consume: bool) VerbatimCapture {
            if (consume) {
                return .{ .body_end = frontier, .newlines = self.newlines, .last_newline = self.last_newline };
            }
            const span_len = (frontier - body_start) - terminator.len;
            var terminator_newlines: u32 = 0;
            for (terminator) |byte| {
                if (byte == '\n') terminator_newlines += 1;
            }
            return .{
                .body_end = frontier - terminator.len,
                .newlines = self.newlines - terminator_newlines,
                .last_newline = if (self.tail.entries.len == 0) self.last_newline else self.tail.lastBefore(span_len),
            };
        }
    };

    /// Streaming-aware equivalent of `captureVerbatim`. Finds `terminator`
    /// starting at `body_start` in the raw source, loading more input through
    /// the active streaming mode as needed, then advances line/column over the
    /// captured bytes and resumes the parser after the terminator.
    fn captureVerbatimStreaming(self: *Self, body_start: usize, terminator: []const u8, consume: bool) !void {
        const capture = try self.findVerbatimTerminatorStreaming(body_start, terminator, consume) orelse {
            try self.recordUnterminatedVerbatim(terminator);
            return error.UnterminatedRawString;
        };
        const body_end = capture.body_end;

        if (comptime root.config.indentation_syntax) {
            const chunk_len = self.chunk_buffer.len;
            const body_chunk_base = body_end - (body_end % chunk_len);

            self.indentation_error = false;
            if (comptime root.position_tracking_enabled) {
                const discard = @min(self.token.len, self.line_offsets.len);
                if (discard != 0) {
                    self.line_offsets.pop(@intCast(discard));
                    self.column_offsets.pop(@intCast(discard));
                }
            }
            self.token.resetBuffered();
            // The scan advanced the chunk reader past `body_end`; rewind it to
            // the chunk containing the terminator end and reload that chunk so
            // lexing resumes exactly after the terminator.
            self.read_bytes = body_chunk_base;
            self.seek = body_end - body_chunk_base;
            try self.seekSourceTo(body_chunk_base);
            self.read();
            if (comptime root.position_tracking_enabled) {
                advanceVerbatimPositionsFromScan(&self.line, &self.column, body_end - body_start, capture);
            }
            return;
        }

        self.token.head = body_end;
        self.token.len = 0;
        if (comptime root.position_tracking_enabled) {
            advanceVerbatimPositionsFromScan(&self.line, &self.column, body_end - body_start, capture);
        }
    }

    /// Scans the raw input forward from `body_start` for `terminator`, loading
    /// more data through the active streaming mode as needed. Returns the
    /// absolute source offset just past the terminator together with the
    /// newline/column statistics accumulated over the captured body, or `null`
    /// when the terminator never reappears before the end of input. The scan
    /// carries the partial terminator match state across refill boundaries so
    /// the terminator may straddle chunks.
    fn findVerbatimTerminatorStreaming(self: *Self, body_start: usize, terminator: []const u8, consume: bool) !?VerbatimCapture {
        if (terminator.len == 0) return .{ .body_end = body_start, .newlines = 0, .last_newline = null };

        const failure = try self.runtime().arena_allocator.alloc(usize, terminator.len);
        @memset(failure, 0);
        {
            var matched: usize = 0;
            for (1..terminator.len) |index| {
                while (matched != 0 and terminator[index] != terminator[matched]) matched = failure[matched - 1];
                if (terminator[index] == terminator[matched]) matched += 1;
                failure[index] = matched;
            }
        }

        if (comptime root.config.indentation_syntax) {
            return self.scanVerbatimChunks(body_start, terminator, failure, consume);
        }

        var scan = VerbatimScan{};
        try scan.init(self.runtime().arena_allocator, terminator, consume);
        var frontier = body_start;
        var matched: usize = 0;
        while (true) {
            if (frontier >= self.loaded_end) {
                if (!self.extendVerbatimInput(frontier, body_start)) return null;
                continue;
            }

            const byte = self.token.buffer[frontier];
            frontier += 1;
            const captured_index = frontier - body_start - 1;
            if (byte == '\n') {
                scan.record(captured_index);
            }
            // A NUL only ever appears as the end-of-input sentinel padded past
            // the last real source byte, so reaching one before the terminator
            // means the input ended.
            if (byte == 0) return null;
            while (matched != 0 and byte != terminator[matched]) matched = failure[matched - 1];
            if (byte == terminator[matched]) matched += 1;
            if (matched == terminator.len) {
                return scan.finish(frontier, body_start, terminator, consume);
            }
        }
    }

    /// Loads more input for the verbatim scan, returning false at the end of
    /// input. `body_start` anchors the token's source offset so the refill
    /// loads forward from the scan frontier. Verbatim capture forces source
    /// retention (`uses_verbatim` contributes to `source_retention_enabled`),
    /// so this never runs with a sliding input window.
    fn extendVerbatimInput(self: *Self, frontier: usize, body_start: usize) bool {
        comptime std.debug.assert(root.input_streaming_enabled and !root.config.indentation_syntax);
        comptime std.debug.assert(!root.sliding_input_enabled);

        if (frontier < self.loaded_end) return true;
        if (self.loaded_end >= self.input_end) {
            // Reaching `loaded_end` with no more source available means EOF.
            return false;
        }
        const needed = (frontier - body_start) + root.read_chunk_size;
        self.loadInputUpTo(needed);
        return true;
    }

    /// Scans `chunk_buffer` chunks for the verbatim terminator in indentation
    /// streaming mode, reading fresh chunks as the frontier crosses chunk
    /// boundaries. `failure` is the KMP prefix table for `terminator`. Loading
    /// the chunk containing `body_start` also recomputes the indentation level
    /// of the body's line, mirroring the retained-source capture path.
    fn scanVerbatimChunks(self: *Self, body_start: usize, terminator: []const u8, failure: []const usize, consume: bool) !?VerbatimCapture {
        comptime std.debug.assert(root.config.indentation_syntax and root.input_streaming_enabled);

        const chunk_len = self.chunk_buffer.len;
        const body_chunk_base = body_start - (body_start % chunk_len);
        self.read_bytes = body_chunk_base;
        self.seek = body_start - body_chunk_base;
        try self.seekSourceTo(body_chunk_base);
        self.read();
        self.current_indent = @intCast(lineIndentOf(self.chunk_buffer, body_start - body_chunk_base) / @max(self.indent_width, 1));

        var scan = VerbatimScan{};
        try scan.init(self.runtime().arena_allocator, terminator, consume);
        var frontier = body_start;
        var matched: usize = 0;
        while (true) {
            const chunk_index = frontier - self.read_bytes;
            if (chunk_index >= chunk_len) {
                self.read_bytes += chunk_len;
                self.seek = 0;
                self.read();
                continue;
            }
            const byte = self.chunk_buffer[chunk_index];
            frontier += 1;
            const captured_index = frontier - body_start - 1;
            if (byte == '\n') {
                scan.record(captured_index);
            }
            // A NUL only ever appears as the end-of-input sentinel written by a
            // short chunk read (`Context.read`), so reaching one before the
            // terminator means the input ended.
            if (byte == 0) return null;
            while (matched != 0 and byte != terminator[matched]) matched = failure[matched - 1];
            if (byte == terminator[matched]) matched += 1;
            if (matched == terminator.len) {
                return scan.finish(frontier, body_start, terminator, consume);
            }
        }
    }

    /// Positions the underlying reader at an absolute source offset so the next
    /// `read()`/`readInput()` fills from there; byte sources just rewind the
    /// offset into the resident input.
    fn seekSourceTo(self: *Self, offset: usize) !void {
        comptime std.debug.assert(root.input_streaming_enabled);
        switch (self.source) {
            .file => |*reader| reader.seekTo(offset) catch return error.ReadFailed,
            .bytes => |*bytes| bytes.offset = @min(offset, bytes.input.len),
        }
    }

    /// Reports an unterminated verbatim capture with the expected terminator
    /// bytes as the diagnostic's expected tokens.
    fn recordUnterminatedVerbatim(self: *Self, terminator: []const u8) !void {
        if (self.input_read_failed) return error.ReadFailed;
        if (comptime root.config.indentation_syntax) {
            if (self.indentation_error) return error.IndentationError;
        }
        const arena = self.runtime().arena_allocator;
        const unexpected_token = try arena.dupe(u8, self.diagnosticTokenItems());
        const expected_tokens = try arena.alloc([]const u8, 1);
        expected_tokens[0] = try arena.dupe(u8, terminator);
        try self.retainDiagnostic(.{
            .syntax = .{
                .line = if (comptime root.position_tracking_enabled) self.line else 0,
                .column = if (comptime root.position_tracking_enabled) self.column else 0,
                .unexpected_token = unexpected_token,
                .expected_tokens = expected_tokens,
                .context = .none,
            },
        });
        self.runtime().syntax_error_count += 1;
    }

    fn advanceVerbatimPositions(line: *u32, column: *u32, captured: []const u8) void {
        var newlines: u32 = 0;
        var last_newline: ?usize = null;
        for (captured, 0..) |byte, index| {
            if (byte == '\n') {
                newlines += 1;
                last_newline = index;
            }
        }
        line.* += newlines;
        if (last_newline) |suffix_start| {
            column.* = @intCast(captured.len - suffix_start);
        } else {
            column.* += @intCast(captured.len);
        }
    }

    /// Streaming-scan equivalent of `advanceVerbatimPositions`, driven by the
    /// per-byte newline statistics accumulated over the captured body instead
    /// of a resident slice.
    fn advanceVerbatimPositionsFromScan(line: *u32, column: *u32, captured_len: usize, capture: VerbatimCapture) void {
        line.* += capture.newlines;
        if (capture.last_newline) |suffix_start| {
            column.* = @intCast(captured_len - suffix_start);
        } else {
            column.* += @intCast(captured_len);
        }
    }

    fn findVerbatimTerminatorEnd(buffer: []const u8, start: usize, terminator: []const u8, consume: bool) ?usize {
        const region_end = std.mem.indexOfScalarPos(u8, buffer, start, 0) orelse buffer.len;
        const terminator_at = std.mem.indexOf(u8, buffer[start..region_end], terminator) orelse return null;
        return start + terminator_at + (if (consume) terminator.len else 0);
    }

    /// Number of leading spaces on the line containing `offset`.
    fn lineIndentOf(buffer: []const u8, offset: usize) usize {
        var line_start = offset;
        while (line_start > 0 and buffer[line_start - 1] != '\n' and buffer[line_start - 1] != 0) : (line_start -= 1) {}
        var indent: usize = 0;
        while (line_start + indent < buffer.len and buffer[line_start + indent] == ' ') : (indent += 1) {}
        return indent;
    }

    pub fn recoveryLookahead(self: *Self) ![]const u8 {
        const required = self.runtime().recovery_window +| root.parser.longest_terminal_length;

        if (comptime !root.config.indentation_syntax) {
            if (comptime root.input_streaming_enabled) {
                self.loadInputUpTo(if (comptime root.sliding_input_enabled)
                    @min(required, root.input_window_size)
                else
                    required);
            }
            const start: usize = self.token.head - self.token.len;
            const available_end = if (comptime root.input_streaming_enabled)
                @min(self.loaded_end, self.input_end + 1)
            else
                self.token.buffer.len;
            const available = self.token.buffer[start..available_end];
            const sentinel = std.mem.indexOfScalar(u8, available, 0) orelse available.len - 1;
            return available[0..@min(available.len, @min(required, sentinel + 1))];
        }

        var output = std.ArrayList(u8).empty;
        try output.ensureTotalCapacity(self.runtime().arena_allocator, required);
        try output.appendSlice(self.runtime().arena_allocator, self.token.items());
        if (std.mem.indexOfScalar(u8, output.items, 0) != null) return output.items;

        var seek = self.seek;
        var current_indent = self.current_indent;
        var indent_width = self.indent_width;
        while (output.items.len < required) {
            while (self.chunk_buffer[seek] == '\n') {
                seek += 1;
                var line_spaces: u16 = 0;
                while (self.chunk_buffer[seek] == ' ') {
                    seek += 1;
                    line_spaces += 1;
                }

                if (indent_width == 0) {
                    indent_width = line_spaces;
                } else if (line_spaces % indent_width != 0) {
                    break;
                }
                const new_indent = if (indent_width == 0) 0 else line_spaces / indent_width;
                if (new_indent == current_indent) {
                    try output.append(self.runtime().arena_allocator, '\n');
                } else if (new_indent > current_indent) {
                    try output.appendNTimes(self.runtime().arena_allocator, '\x01', new_indent - current_indent);
                } else {
                    try output.appendNTimes(self.runtime().arena_allocator, '\x02', current_indent - new_indent);
                }
                current_indent = new_indent;
                if (output.items.len >= required) break;
            }
            if (output.items.len >= required) break;

            const byte = self.chunk_buffer[seek];
            try output.append(self.runtime().arena_allocator, byte);
            if (byte == 0) break;
            seek += 1;
        }
        return output.items;
    }

    pub fn releaseToken(self: *@This(), length: data_structures.Token.Length) void {
        if (comptime root.position_tracking_enabled) {
            if (comptime root.config.indentation_syntax) {
                self.line += self.line_offsets.sum(0, length);
                self.column += self.column_offsets.sum(0, length);
                const newlines = summarizeNewlines(self.token.items()[0..length]);
                if (newlines.last) |last_newline| {
                    self.column = self.column_offsets.sum(@intCast(last_newline), length);
                }
                self.line_offsets.pop(length);
                self.column_offsets.pop(length);
            } else {
                // Non-indentation grammars append a constant 1 per lexed byte,
                // so the offset sums equal plain lengths and the per-byte array
                // buys nothing. Keep the newline scan, drop the array passes.
                const newlines = summarizeNewlines(self.token.items()[0..length]);
                self.line += newlines.count;
                if (newlines.last) |last_newline| {
                    self.column = @intCast(@as(usize, length) - last_newline);
                } else {
                    self.column += length;
                }
            }
        }
        self.token.pop(length);
        if (comptime builtin.mode == .Debug) {
            if (self.verbosityLevel() > 1) {
                std.debug.print("\n{d}:{d}:\"{f}\"\n", .{
                    if (comptime root.position_tracking_enabled) self.line else 0,
                    if (comptime root.position_tracking_enabled) self.column else 0,
                    string_utilities.fmtString(self.token.items()),
                });
            }
        }
    }

    pub fn read(self: *@This()) void {
        const bytes_read = switch (self.source) {
            .file => |*reader| reader.interface.readSliceShort(self.chunk_buffer) catch |err| switch (err) {
                error.ReadFailed => failed: {
                    self.input_read_failed = true;
                    break :failed 0;
                },
            },
            .bytes => |*bytes| bytes_read: {
                if (bytes.offset >= bytes.input.len) {
                    break :bytes_read 0;
                }
                const remaining = bytes.input.len - bytes.offset;
                const amount = @min(remaining, self.chunk_buffer.len);
                @memcpy(self.chunk_buffer[0..amount], bytes.input[bytes.offset..][0..amount]);
                bytes.offset += amount;
                break :bytes_read amount;
            },
        };

        if (bytes_read < self.chunk_buffer.len) {
            self.chunk_buffer[bytes_read] = '\x00';
        }
    }

    pub fn reset(self: *@This()) !void {
        self.input_read_failed = false;
        switch (self.source) {
            .file => |*reader| try reader.seekTo(0),
            .bytes => |*bytes| bytes.offset = 0,
        }
        if (comptime root.config.indentation_syntax) {
            self.read_bytes = 0;
            self.seek = 0;
            self.indent_width = 0;
            self.current_indent = 0;
            self.indentation_error = false;
        }
        if (comptime root.position_tracking_enabled) {
            self.line = 1;
            self.column = 1;
            self.line_offsets.reset();
            self.column_offsets.reset();
        }
        if (comptime root.parser.is_ast_enabled) {
            self.node_allocator.reset();
        }
        if (comptime root.config.indentation_syntax) {
            self.token.resetBuffered();
            if (comptime root.input_streaming_enabled) {
                self.read();
            } else switch (self.source) {
                .file => self.read(),
                .bytes => |bytes| self.chunk_buffer = @constCast(bytes.input),
            }
        } else if (comptime root.sliding_input_enabled) {
            self.input_end = 0;
            self.loaded_end = 0;
            self.window_base = 0;
            self.input_eof = false;
            self.token.resetInput(self.chunk_buffer);
        } else if (comptime root.input_streaming_enabled) switch (self.source) {
            .file => {
                self.loaded_end = 0;
                self.token.resetInput(self.file_input);
            },
            .bytes => |bytes| {
                self.input_end = bytes.input.len - 1;
                self.loaded_end = bytes.input.len;
                self.token.resetInput(@constCast(bytes.input));
            },
        } else switch (self.source) {
            .file => {
                self.token.resetInput(self.chunk_buffer);
                self.read();
            },
            .bytes => |bytes| self.token.resetInput(@constCast(bytes.input)),
        }
    }

    pub inline fn advanceInputWithCheck(self: *@This()) void {
        comptime std.debug.assert(root.config.indentation_syntax);

        if (self.seek == self.chunk_buffer.len - 1) {
            self.read_bytes += @intCast(self.chunk_buffer.len);
            self.seek = 0;
            self.read();
        } else {
            self.seek += 1;
        }
    }

    pub inline fn advanceInputWithoutCheck(self: *@This()) void {
        comptime std.debug.assert(root.config.indentation_syntax);

        self.seek +%= 1;
    }

    pub inline fn advanceInput(self: *@This()) void {
        comptime std.debug.assert(root.config.indentation_syntax);

        if (comptime root.input_streaming_enabled) {
            self.advanceInputWithCheck();
        } else {
            self.advanceInputWithoutCheck();
        }
    }

    /// Appends a token to the indentation-mode token stream, recording the
    /// source offset the token was lexed from.
    inline fn appendToken(self: *@This(), char: u8, source_offset: usize) void {
        self.token.appendSource(char, source_offset);
    }

    pub inline fn advanceLexer(self: *@This()) void {
        if (comptime root.config.indentation_syntax) {
            const chunk_buffer = self.chunk_buffer;
            while (chunk_buffer[self.seek] == '\n') {
                const boundary_source = self.read_bytes + self.seek;
                self.advanceInput();
                var line_spaces: u16 = 0;

                while (chunk_buffer[self.seek] == ' ') {
                    self.advanceInput();
                    line_spaces += 1;
                }

                if (self.indent_width == 0) {
                    self.indent_width = line_spaces;
                } else if (line_spaces % self.indent_width != 0) {
                    self.recordIndentationDiagnostic(line_spaces);
                    while (self.token.len < @max(root.parser.longest_terminal_length, 1)) {
                        self.appendToken(0, self.read_bytes + self.seek);
                    }
                    return;
                }
                const new_indent = if (self.indent_width == 0) 0 else line_spaces / self.indent_width;
                if (comptime root.position_tracking_enabled and root.config.indentation_syntax) {
                    self.line_offsets.append(1);
                }
                if (new_indent == self.current_indent) {
                    if (comptime root.position_tracking_enabled) {
                        self.column_offsets.append(@as(u32, line_spaces) + 1);
                    }
                    self.appendToken('\n', boundary_source);
                } else {
                    if (new_indent > self.current_indent) {
                        for (0..new_indent - self.current_indent) |index| {
                            if (comptime root.position_tracking_enabled) {
                                if (comptime root.config.indentation_syntax) {
                                    if (index != 0) {
                                        self.line_offsets.append(0);
                                    }
                                }
                                self.column_offsets.append(@as(u32, new_indent) * @as(u32, self.indent_width) + 1);
                            }
                            self.appendToken('\x01', boundary_source);
                        }
                    } else if (new_indent < self.current_indent) {
                        for (0..self.current_indent - new_indent) |index| {
                            if (comptime root.position_tracking_enabled) {
                                if (comptime root.config.indentation_syntax) {
                                    if (index != 0) {
                                        self.line_offsets.append(0);
                                    }
                                }
                                self.column_offsets.append(@as(u32, new_indent) * @as(u32, self.indent_width) + 1);
                            }
                            self.appendToken('\x02', boundary_source);
                        }
                    }
                    self.current_indent = new_indent;
                }
            }
        }

        if (comptime root.position_tracking_enabled and root.config.indentation_syntax) {
            self.line_offsets.append(0);
            self.column_offsets.append(1);
        }
        if (comptime root.config.indentation_syntax) {
            self.appendToken(self.chunk_buffer[self.seek], self.read_bytes + self.seek);
            self.advanceInput();
        } else {
            self.token.appendNoCopy();
        }

        if (comptime builtin.mode == .Debug) {
            if (self.verbosityLevel() > 1) {
                std.debug.print("\n{d}:{d}:\"{f}\"\n", .{
                    if (comptime root.position_tracking_enabled) self.line else 0,
                    if (comptime root.position_tracking_enabled) self.column else 0,
                    string_utilities.fmtString(self.token.items()),
                });
            }
        }
    }

    fn recordIndentationDiagnostic(self: *Self, line_spaces: u16) void {
        comptime std.debug.assert(root.config.indentation_syntax);

        self.indentation_error = true;
        const diagnostic: root.ParseDiagnostic = .{ .indentation = .{
            .line = if (comptime root.position_tracking_enabled) self.line + 1 else 0,
            .column = if (comptime root.position_tracking_enabled) 1 else 0,
            .spaces = line_spaces,
            .indentation_width = self.indent_width,
        } };
        // The lexer path is infallible, so arena exhaustion here degrades to
        // dropping the retained copy; the parse still reports the
        // indentation error itself.
        self.retainDiagnostic(diagnostic) catch {};
    }

    inline fn ensureInputLoaded(self: *@This(), needed_len: usize) void {
        comptime std.debug.assert(root.input_streaming_enabled and !root.config.indentation_syntax);

        self.loadInputUpTo(needed_len);
        const token_start: usize = self.token.head - self.token.len;
        std.debug.assert(token_start + needed_len <= self.loaded_end);
    }

    inline fn loadInputUpTo(self: *@This(), needed_len: usize) void {
        comptime std.debug.assert(root.input_streaming_enabled and !root.config.indentation_syntax);

        const token_start: usize = self.token.head - self.token.len;
        const required_end = token_start + needed_len;
        if (required_end > self.loaded_end) {
            @branchHint(.unlikely);
            self.refillInput(needed_len);
        }
    }

    fn readInput(self: *@This(), destination: []u8) usize {
        return switch (self.source) {
            .file => |*reader| reader.interface.readSliceShort(destination) catch |err| switch (err) {
                error.ReadFailed => failed: {
                    self.input_read_failed = true;
                    break :failed 0;
                },
            },
            .bytes => |*bytes| bytes_read: {
                if (bytes.offset >= bytes.input.len) break :bytes_read 0;
                const amount = @min(destination.len, bytes.input.len - bytes.offset);
                @memcpy(destination[0..amount], bytes.input[bytes.offset..][0..amount]);
                bytes.offset += amount;
                break :bytes_read amount;
            },
        };
    }

    noinline fn refillInput(self: *@This(), needed_len: usize) void {
        @branchHint(.cold);
        comptime std.debug.assert(root.input_streaming_enabled and !root.config.indentation_syntax);

        if (comptime root.sliding_input_enabled) {
            const token_start: usize = self.token.head - self.token.len;
            if (token_start != 0) {
                std.debug.assert(token_start <= self.input_end);
                const remaining = self.input_end - token_start;
                std.mem.copyForwards(
                    u8,
                    self.token.buffer[0..remaining],
                    self.token.buffer[token_start..self.input_end],
                );
                self.window_base += token_start;
                self.token.head -= @intCast(token_start);
                self.input_end = remaining;
                self.loaded_end = remaining;
            }

            while (needed_len > self.loaded_end and !self.input_eof) {
                std.debug.assert(self.input_end < root.input_window_size);
                const bytes_read = self.readInput(self.token.buffer[self.input_end..root.input_window_size]);
                if (bytes_read == 0) {
                    self.input_eof = true;
                    const padded_end = self.input_end + root.input_padding_size;
                    @memset(self.token.buffer[self.input_end..padded_end], 0);
                    self.loaded_end = padded_end;
                    break;
                }
                self.input_end += bytes_read;
                self.loaded_end = self.input_end;
            }
            return;
        }

        const required_end = @as(usize, self.token.head - self.token.len) + needed_len;
        const reader = switch (self.source) {
            .file => |*reader| reader,
            .bytes => unreachable,
        };

        while (self.loaded_end < required_end and self.loaded_end < self.input_end) {
            const target_end = @min(
                self.input_end,
                @max(required_end, self.loaded_end +| root.read_chunk_size),
            );
            const bytes_read = reader.interface.readSliceShort(self.token.buffer[self.loaded_end..target_end]) catch |err| switch (err) {
                error.ReadFailed => failed: {
                    self.input_read_failed = true;
                    break :failed 0;
                },
            };
            if (bytes_read == 0) {
                self.input_end = self.loaded_end;
                break;
            }
            self.loaded_end += bytes_read;
        }

        if (self.loaded_end == self.input_end) {
            const padded_end = @min(self.token.buffer.len, self.input_end + root.input_padding_size);
            @memset(self.token.buffer[self.input_end..padded_end], 0);
            self.loaded_end = padded_end;
        }
    }

    pub fn head(self: *@This(), comptime T: type, offset: data_structures.Token.Length) T {
        const bytes_needed = comptime @divExact(@bitSizeOf(T), 8);
        const needed_len = offset + bytes_needed;
        if (comptime root.input_streaming_enabled and !root.config.indentation_syntax) {
            self.ensureInputLoaded(needed_len);
        }
        while (self.token.len < needed_len) {
            self.advanceLexer();
        }

        const base_ptr = self.token.items().ptr + offset;

        if (comptime T == u8) {
            return base_ptr[0];
        }

        const array_ptr: *const [bytes_needed]u8 = @ptrCast(base_ptr);
        return std.mem.readInt(T, array_ptr, .big);
    }

    pub inline fn pos(self: *const Self) usize {
        if (comptime root.config.indentation_syntax) {
            return self.read_bytes + self.seek;
        }
        if (comptime root.sliding_input_enabled) {
            return self.window_base + self.token.head - self.token.len;
        }
        return self.token.head - self.token.len;
    }

    /// Source offset of the token the parser is about to consume, or of the
    /// byte it is about to lex when no front-run token is buffered. This is the
    /// source position where the next consumed token begins (equivalently, where
    /// the previously consumed token ended), and is the coordinate space node
    /// text spans should be captured in.
    pub inline fn currentTokenSourceOffset(self: *const Self) usize {
        if (comptime root.config.indentation_syntax) {
            if (self.token.len == 0) return self.read_bytes + self.seek;
            return self.token.firstSourceOffset();
        }
        return self.pos();
    }

    /// Creates the local node handle a generated rule body assembles for one
    /// variable. Comptime-specialized: an AST allocation when AST
    /// construction is enabled, a by-value stack node otherwise. The
    /// configuration decision happens here, once — generated parsers call
    /// this unconditionally.
    pub inline fn createVariableNode(
        self: *Self,
        source_offset: usize,
        variable: u16,
    ) error{ ASTCapacityExceeded, OutOfMemory }!data_structures.VariableNodeHandle {
        if (comptime root.parser.is_ast_enabled) {
            return self.node_allocator.create(source_offset, variable);
        }
        return .{ .text_start = source_offset, .variable = variable, .payload = .{} };
    }

    /// Reads the raw source bytes of a source-coordinate span. In indentation
    /// mode the token stream is a cleaned/rewritten view of the input, so node
    /// text spans cannot be resolved against it; this reads the original
    /// source instead.
    fn readSourceSlice(self: *const Self, start: usize, length: usize) []const u8 {
        const end = start + length;
        switch (self.source) {
            .bytes => |bytes| return bytes.input[start..end],
            .file => {
                if (comptime !root.input_streaming_enabled) {
                    return self.chunk_buffer[start..end];
                }
                const mutable = @constCast(self);
                const span = self.runtimeConst().arena_allocator.alloc(u8, length) catch return &[_]u8{};
                const frontier = self.read_bytes + self.seek;
                mutable.source.file.seekTo(start) catch return span[0..0];
                var filled: usize = 0;
                while (filled < length) {
                    const n = mutable.source.file.interface.readSliceShort(span[filled..]) catch break;
                    if (n == 0) break;
                    filled += n;
                }
                mutable.source.file.seekTo(frontier) catch {};
                return span[0..filled];
            },
        }
    }

    pub inline fn getTextSlice(self: *const Self, start: usize, length: usize) []const u8 {
        if (comptime root.config.indentation_syntax) {
            return self.readSourceSlice(start, length);
        }
        return self.token.buffer[start .. start + length];
    }

    pub inline fn diagnosticInput(self: *const Self) []const u8 {
        if (comptime root.config.indentation_syntax) return self.chunk_buffer;
        if (comptime root.input_streaming_enabled) {
            return self.token.buffer[0..@min(self.loaded_end, self.input_end + 1)];
        }
        return self.token.buffer;
    }
};

test "newline summary counts every marker and retains the final position" {
    const summary = summarizeNewlines("a\n\nb\x01c\x02\x02d");
    try std.testing.expectEqual(@as(u32, 5), summary.count);
    try std.testing.expectEqual(@as(?usize, 7), summary.last);
}

pub const RuntimeContextRegistration = struct {
    context_address: usize,
    runtime_context: *RuntimeContext,
    next: ?*RuntimeContextRegistration = null,
    is_registered: bool = false,

    pub fn init(context: *Context, runtime_context: *RuntimeContext) RuntimeContextRegistration {
        return .{
            .context_address = @intFromPtr(context),
            .runtime_context = runtime_context,
        };
    }

    pub fn register(self: *RuntimeContextRegistration) void {
        lockRuntimeRegistry();
        defer runtime_registry_mutex.unlock();

        std.debug.assert(!self.is_registered);
        self.next = runtime_registry_head;
        runtime_registry_head = self;
        self.is_registered = true;
    }

    pub fn unregister(self: *RuntimeContextRegistration) void {
        lockRuntimeRegistry();
        defer runtime_registry_mutex.unlock();

        var link = &runtime_registry_head;
        while (link.*) |registration| {
            if (registration == self) {
                link.* = registration.next;
                self.next = null;
                self.is_registered = false;
                return;
            }
            link = &registration.next;
        }
        unreachable;
    }
};

fn registeredRuntimeContext(context: *const Context) *RuntimeContext {
    const context_address = @intFromPtr(context);

    lockRuntimeRegistry();
    defer runtime_registry_mutex.unlock();

    var registration = runtime_registry_head;
    while (registration) |entry| : (registration = entry.next) {
        if (entry.context_address == context_address) return entry.runtime_context;
    }
    @panic("parser context has no active runtime registration");
}
