const std = @import("std");
const root = @import("galley");
const data_structures = root.data_structures;

pub const ProcedureArguments = struct {
    context: *data_structures.Context,
    rule: ?data_structures.Rule,

    /// AST mode: the sole structural drop/replace channel; `null` means the
    /// node was dropped. `void` when AST construction is disabled.
    node_address: if (root.parser.is_ast_enabled) ?data_structures.Node.Pointer else void =
        if (root.parser.is_ast_enabled) null else {},

    /// No-AST mode: internal direct pointer to the temporary node. `void`
    /// when AST construction is enabled; not a drop/replace channel.
    _temp_node: if (root.parser.is_ast_enabled) void else ?*data_structures.Node =
        if (root.parser.is_ast_enabled) {} else null,

    /// Resolves the current node for reading and in-place mutation. In AST
    /// mode the pointer is derived live from `node_address`, so it reflects
    /// any drop or replacement performed by an earlier hook phase and never
    /// goes stale after allocator growth within a single phase.
    pub fn currentNode(self: *const @This()) ?*data_structures.Node {
        if (comptime root.parser.is_ast_enabled) {
            return if (self.node_address) |address| self.context.node_allocator.at(address) else null;
        }
        return self._temp_node;
    }

    /// The single gate for consumer-reported semantic errors. Records an
    /// arena-backed diagnostic, marks the current node when one exists, and
    /// returns the total semantic error count so hooks can limit themselves.
    /// Parsing continues; `Session` returns `ParseError.SemanticError` after
    /// a syntax-clean parse that recorded any semantic error.
    pub fn reportSemanticError(self: *@This(), message: []const u8) !usize {
        const runtime_context = self.context.runtime();
        const arena = runtime_context.arena_allocator;
        const owned_message = try arena.dupe(u8, message);

        var variable_name: []const u8 = "*";
        var text_start: usize = 0;
        var text_length: usize = 0;
        if (self.currentNode()) |node| {
            text_start = node.text_start;
            text_length = node.text_length;
            if (node.variable != data_structures.Node.invalid_variable and
                node.variable < root.parser.variables.len)
            {
                variable_name = root.parser.variables[node.variable];
            } else if (self.rule) |rule| {
                if (rule.header < root.parser.variables.len) {
                    variable_name = root.parser.variables[rule.header];
                }
            }
            node.is_semantic_error = true;
        } else if (self.rule) |rule| {
            if (rule.header < root.parser.variables.len) {
                variable_name = root.parser.variables[rule.header];
            }
        }

        try runtime_context.recorded_diagnostics.append(arena, .{
            .semantic = .{
                .line = if (comptime root.position_tracking_enabled) self.context.line else 0,
                .column = if (comptime root.position_tracking_enabled) self.context.column else 0,
                .variable = variable_name,
                .message = owned_message,
                .text_start = text_start,
                .text_length = text_length,
            },
        });
        runtime_context.semantic_error_count += 1;
        return runtime_context.semantic_error_count;
    }
};

pub const Procedure = fn (args: *ProcedureArguments) anyerror!void;

pub fn wrapProcedure(comptime Signature: type, comptime procedure: anytype, comptime procedure_name: []const u8) Signature {
    const signature_type_info = @typeInfo(Signature);

    if (signature_type_info != .@"fn") {
        @compileError(std.fmt.comptimePrint("{s} procedure: Expected a function signature, got {s}", .{
            procedure_name,
            @typeName(Signature),
        }));
    }

    const signature_fn_info = signature_type_info.@"fn";

    if (signature_fn_info.params.len != 1) {
        @compileError(std.fmt.comptimePrint("{s} procedure: Signature must take exactly one argument (a struct)", .{
            procedure_name,
        }));
    }

    const ArgType = signature_fn_info.params[0].type orelse @compileError(std.fmt.comptimePrint("{s} procedure: Generic parameters not allwoed here", .{
        procedure_name,
    }));
    const arg_type_info = @typeInfo(ArgType);

    const ProcedureType = @TypeOf(procedure);
    const procedure_type_info = @typeInfo(ProcedureType);

    if (procedure_type_info != .@"fn") {
        @compileError(std.fmt.comptimePrint("{s} procedure: Expected a function, got {s}", .{
            procedure_name,
            @typeName(ProcedureType),
        }));
    }

    const procedure_fn_info = procedure_type_info.@"fn";

    if (procedure_fn_info.params.len > 1) {
        @compileError(std.fmt.comptimePrint("{s} procedure: Handler must take at most one argument (a struct)", .{
            procedure_name,
        }));
    }

    if (procedure_fn_info.return_type) |ReturnType| {
        const return_type_info = @typeInfo(ReturnType);

        if (ReturnType != void and
            (return_type_info != .error_union or return_type_info.error_union.payload != void))
        {
            @compileError(std.fmt.comptimePrint("{s} procedure: Handler must return {any} or {any}, got {any}", .{
                procedure_name,
                void,
                anyerror!void,
                ReturnType,
            }));
        }
    } else {
        @compileError(std.fmt.comptimePrint("{s} procedure: Handler must return '{any}'", .{
            procedure_name,
            void,
        }));
    }

    if (procedure_fn_info.params.len == 1) {
        const ProcedureArgType = procedure_fn_info.params[0].type orelse @compileError(std.fmt.comptimePrint("{s} procedure: Generic parameters not allowed here", .{
            procedure_name,
        }));

        if (ProcedureArgType != *ProcedureArguments) {
            @compileError(std.fmt.comptimePrint("{s} procedure: Handler argument must be of type '{any}'", .{
                procedure_name,
                *ProcedureArguments,
            }));
        }

        const procedure_arg_type_info = @typeInfo(@typeInfo(ProcedureArgType).pointer.child);
        inline for (procedure_arg_type_info.@"struct".fields) |field| {
            if (!@hasField(arg_type_info.pointer.child, field.name)) {
                @compileError(std.fmt.comptimePrint("{s} procedure: Args is missing required field: '{s}'", .{
                    procedure_name,
                    field.name,
                }));
            }
        }
    }

    const Wrapper = struct {
        fn call(args: ArgType) anyerror!void {
            if (procedure_fn_info.params.len == 0) {
                return procedure();
            }

            return @call(.auto, procedure, .{args});
        }
    };

    return Wrapper.call;
}
