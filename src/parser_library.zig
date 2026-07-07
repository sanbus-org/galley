const builtin = @import("builtin");
const std = @import("std");

pub const procedures = @import("procedures");
pub const config = @import("config");
pub const parser = @import("parser");
pub const string_utilities = @import("utilities/string.zig");
pub const stack_overflow_utilities = @import("utilities/stack-overflow.zig");
pub const data_structures = @import("utilities/data-structures/data-structures.zig");
pub const read_chunk_size = std.math.maxInt(std.math.Min(data_structures.Context.Size, u28));

pub const ParseOptions = struct {
    language_options: config.Options = .{},
    input_path: ?[]const u8 = null,
    verbosity: usize = 0,
};

pub const ParseResult = struct {
    parsed_bytes: usize,
    line: if (builtin.mode != .ReleaseFast) u32 else void,
    column: if (builtin.mode != .ReleaseFast) u32 else void,
    ast_root: ?data_structures.ASTNode.Pointer = null,
};

pub const ParsedInput = struct {
    session: Session,
    result: ParseResult,

    pub fn deinit(self: *ParsedInput) void {
        self.session.deinit();
    }
};

pub fn parseBytes(io: std.Io, allocator: std.mem.Allocator, input: []const u8, options: ParseOptions) !ParsedInput {
    var session = try Session.init(io, allocator, options);
    errdefer session.deinit();
    const result = try session.parseBytes(input, options.input_path);
    return .{
        .session = session,
        .result = result,
    };
}

pub fn parseSentinelBytes(io: std.Io, allocator: std.mem.Allocator, input: [:0]const u8, options: ParseOptions) !ParsedInput {
    var session = try Session.init(io, allocator, options);
    errdefer session.deinit();
    const result = try session.parseSentinelBytes(input, options.input_path);
    return .{
        .session = session,
        .result = result,
    };
}

pub const Session = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    runtime_context: data_structures.RuntimeContext,
    reader_buffer: []u8,
    chunk_buffer: []u8,
    owned_input: ?[]u8 = null,
    node_allocator: if (parser.is_ast_enabled) data_structures.ASTAllocator else void,
    verbosity: if (builtin.mode == .Debug) usize else void,

    pub fn init(io: std.Io, allocator: std.mem.Allocator, options: ParseOptions) !Session {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        const reader_buffer = try allocator.alloc(u8, read_chunk_size * 2);
        errdefer allocator.free(reader_buffer);

        const chunk_buffer = try allocator.alloc(u8, read_chunk_size);
        errdefer allocator.free(chunk_buffer);

        const node_allocator = if (parser.is_ast_enabled)
            try data_structures.ASTAllocator.initCapacity(allocator)
        else {};
        errdefer if (parser.is_ast_enabled) allocator.free(node_allocator.memory);

        return .{
            .io = io,
            .allocator = allocator,
            .arena = arena,
            .runtime_context = .{
                .io = io,
                .input_path = options.input_path,
                .language_options = options.language_options,
                .arena_allocator = arena.allocator(),
            },
            .reader_buffer = reader_buffer,
            .chunk_buffer = chunk_buffer,
            .node_allocator = node_allocator,
            .verbosity = if (builtin.mode == .Debug) options.verbosity else {},
        };
    }

    pub fn deinit(self: *Session) void {
        if (self.owned_input) |owned_input| {
            self.allocator.free(owned_input);
            self.owned_input = null;
        }
        if (parser.is_ast_enabled) {
            self.allocator.free(self.node_allocator.memory);
        }
        self.allocator.free(self.chunk_buffer);
        self.allocator.free(self.reader_buffer);
        self.arena.deinit();
    }

    pub fn parseBytes(self: *Session, input: []const u8, input_path: ?[]const u8) !ParseResult {
        if (self.owned_input) |owned_input| {
            self.allocator.free(owned_input);
            self.owned_input = null;
        }

        const owned_input = try self.allocator.alloc(u8, input.len + 1);
        @memcpy(owned_input[0..input.len], input);
        owned_input[input.len] = 0;
        self.owned_input = owned_input;

        var context_value = self._makeContext(.{ .bytes = .{ .input = owned_input } }, input_path);
        return try self._parseContext(&context_value);
    }

    pub fn parseSentinelBytes(self: *Session, input: [:0]const u8, input_path: ?[]const u8) !ParseResult {
        if (self.owned_input) |owned_input| {
            self.allocator.free(owned_input);
            self.owned_input = null;
        }

        var context_value = self._makeContext(.{ .bytes = .{ .input = input[0 .. input.len + 1] } }, input_path);
        return try self._parseContext(&context_value);
    }

    pub fn parseFile(self: *Session, file: std.Io.File, input_path: ?[]const u8) !ParseResult {
        var context_value = self._makeContext(.{ .file = file.reader(self.io, self.reader_buffer) }, input_path);
        return try self._parseContext(&context_value);
    }

    pub fn astAllocator(self: *Session) if (parser.is_ast_enabled) *data_structures.ASTAllocator else void {
        if (parser.is_ast_enabled) {
            return &self.node_allocator;
        }
        return {};
    }

    pub fn _makeContext(self: *Session, source: data_structures.Context.Source, input_path: ?[]const u8) data_structures.Context {
        self.runtime_context.input_path = input_path;
        self.runtime_context.arena_allocator = self.arena.allocator();

        var context_value = data_structures.Context{
            .source = source,
            .node_allocator = if (parser.is_ast_enabled) &self.node_allocator else {},
            .chunk_buffer = self.chunk_buffer,
        };
        if (comptime builtin.mode == .Debug) {
            context_value.verbosity = self.verbosity;
        }
        return context_value;
    }

    pub fn _parseContext(self: *Session, context_value: *data_structures.Context) !ParseResult {
        _ = self.arena.reset(.retain_capacity);
        data_structures.context.activateRuntimeContext(&self.runtime_context);
        defer data_structures.context.deactivateRuntimeContext(&self.runtime_context);

        try context_value.reset();
        return try parser.parseWithResult(context_value);
    }
};
