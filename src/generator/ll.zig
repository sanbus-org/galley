const std = @import("std");
const common = @import("generator_common");

pub const Options = common.Options;
const SymbolKind = common.SymbolKind;
const Symbol = common.Symbol;
const Rule = common.Rule;
const ErrorMessageSpec = common.ErrorMessageSpec;
const bytesToInt = common.bytesToInt;
const emitEscapedForComment = common.emitEscapedForComment;
const emitFormatToken = common.emitFormatToken;
const emitStringLiteral = common.emitStringLiteral;
const indented = common.indented;
const readableSymbolName = common.readableSymbolName;
const safeIdentifier = common.safeIdentifier;

const Generator = struct {
    allocator: std.mem.Allocator,
    options: Options,
    symbols: std.ArrayList(Symbol) = .empty,
    variables: std.ArrayList(usize) = .empty,
    rules: std.ArrayList(Rule) = .empty,
    parse_table: std.ArrayList(ParseEntry) = .empty,
    error_message_specs: std.ArrayList(ErrorMessageSpec) = .empty,
    syntax_error_handlers: std.ArrayList(SyntaxErrorHandlerSpec) = .empty,
    needs_ast_suppressed_parser: std.AutoHashMap(usize, void) = undefined,
    augmented_start: usize = 0,
    has_occurrence_procedures: bool = false,

    const ParseEntry = struct {
        variable: usize,
        terminal: usize,
        rule: usize,
    };

    const SyntaxErrorHandlerSpec = struct {
        name: []const u8,
        symbol_index: usize,
        expected_tokens: []const []const u8,
        exact_name: []const u8,
        symbol_name: []const u8,
        skip_ast_construction: bool,
    };

    fn init(allocator: std.mem.Allocator, options: Options) Generator {
        return .{
            .allocator = allocator,
            .options = options,
            .needs_ast_suppressed_parser = std.AutoHashMap(usize, void).init(allocator),
        };
    }

    fn addSymbol(self: *Generator, id: []const u8, kind: SymbolKind) !usize {
        return common.addSymbol(self.allocator, &self.symbols, &self.variables, id, kind);
    }

    fn fromGrammar(self: *Generator, grammar: anytype) !void {
        var rhs_counts = std.AutoHashMap(usize, usize).init(self.allocator);
        defer rhs_counts.deinit();

        for (grammar.rules) |rule| {
            const header = try self.addSymbol(rule.header, .variable);
            try common.appendProcedureNames(self.allocator, &self.symbols.items[header].procedures, rule.procedures);
            for (rule.right_hand_sides) |rhs| {
                const rhs_index = rhs_counts.get(header) orelse 0;
                try rhs_counts.put(header, rhs_index + 1);

                var generated_rule = Rule{
                    .header = header,
                    .rhs_index = try std.fmt.allocPrint(self.allocator, "{d}", .{rhs_index}),
                };
                try common.appendProcedureNames(self.allocator, &generated_rule.procedures, rhs.procedures);
                for (rhs.symbols) |symbol| {
                    const kind: SymbolKind = switch (symbol.kind) {
                        .variable => .variable,
                        .terminal => .terminal,
                        .generative_terminal => .generative_terminal,
                    };
                    const symbol_index = try self.addSymbol(symbol.id, kind);
                    try generated_rule.rhs.append(self.allocator, symbol_index);
                    try generated_rule.rhs_procedures.append(self.allocator, try common.cloneProcedureNames(self.allocator, symbol.procedures));
                    if (self.options.with_procedures and symbol.procedures.len != 0 and self.symbolReturnsNode(symbol_index, false)) {
                        self.has_occurrence_procedures = true;
                    }
                }
                try self.rules.append(self.allocator, generated_rule);
            }
        }

        const original_start = self.rules.items[0].header;
        self.augmented_start = try self.addSymbol("_AugmentedStart", .variable);
        const eof = try self.addSymbol("\x00", .end);
        var augmented_rule = Rule{ .header = self.augmented_start, .rhs_index = "0" };
        try augmented_rule.rhs.append(self.allocator, original_start);
        try augmented_rule.rhs_procedures.append(self.allocator, .{});
        try augmented_rule.rhs.append(self.allocator, eof);
        try augmented_rule.rhs_procedures.append(self.allocator, .{});
        try self.rules.append(self.allocator, augmented_rule);

        const generative_terminal = try self.addSymbol("GenerativeTerminal", .variable);
        try self.rules.append(self.allocator, .{ .header = generative_terminal, .rhs_index = "0" });

        std.mem.sort(Rule, self.rules.items, self, ruleLessThan);
        try self.buildParseTable();
    }

    fn ruleLessThan(self: *Generator, lhs: Rule, rhs: Rule) bool {
        return common.ruleLessThan(self.symbols.items, lhs, rhs);
    }

    fn buildParseTable(self: *Generator) !void {
        for (self.variables.items) |variable| {
            var first_set = std.AutoHashMap(usize, usize).init(self.allocator);
            defer first_set.deinit();
            try self.firsts(variable, &first_set, null);

            const nullable_rule = self.nullableRule(variable);
            var iterator = first_set.iterator();
            while (iterator.next()) |entry| {
                try self.addParseEntry(.{
                    .variable = variable,
                    .terminal = entry.key_ptr.*,
                    .rule = entry.value_ptr.*,
                });
            }

            if (nullable_rule) |rule_index| {
                var follow_set = std.AutoHashMap(usize, usize).init(self.allocator);
                defer follow_set.deinit();
                try self.follows(variable, &follow_set, null);
                var follow_iterator = follow_set.iterator();
                while (follow_iterator.next()) |entry| {
                    try self.addParseEntry(.{
                        .variable = variable,
                        .terminal = entry.key_ptr.*,
                        .rule = rule_index,
                    });
                }
            }
        }
    }

    fn nullableRule(self: *Generator, variable: usize) ?usize {
        var visited = std.AutoHashMap(usize, void).init(self.allocator);
        defer visited.deinit();
        return self.nullableRuleImpl(variable, &visited);
    }

    fn nullableRuleImpl(self: *Generator, variable: usize, visited: *std.AutoHashMap(usize, void)) ?usize {
        if (visited.contains(variable)) return null;
        visited.put(variable, {}) catch return null;
        defer _ = visited.remove(variable);
        for (self.rules.items, 0..) |rule, rule_index| {
            if (rule.header != variable) continue;
            for (rule.rhs.items) |symbol_index| {
                if (self.symbols.items[symbol_index].kind != .variable or self.nullableRuleImpl(symbol_index, visited) == null) break;
            } else {
                return rule_index;
            }
        }
        return null;
    }

    fn firsts(self: *Generator, variable: usize, out: *std.AutoHashMap(usize, usize), visited: ?*std.AutoHashMap(usize, void)) !void {
        if (visited) |set| {
            if (set.contains(variable)) return;
        }
        var local_visited = std.AutoHashMap(usize, void).init(self.allocator);
        defer local_visited.deinit();
        if (visited) |set| {
            var it = set.iterator();
            while (it.next()) |entry| try local_visited.put(entry.key_ptr.*, {});
        }
        try local_visited.put(variable, {});

        for (self.rules.items, 0..) |rule, rule_index| {
            if (rule.header != variable) continue;
            for (rule.rhs.items) |symbol_index| {
                const symbol = self.symbols.items[symbol_index];
                if (symbol.kind == .variable) {
                    var child_firsts = std.AutoHashMap(usize, usize).init(self.allocator);
                    defer child_firsts.deinit();
                    try self.firsts(symbol_index, &child_firsts, &local_visited);
                    var child_iterator = child_firsts.iterator();
                    while (child_iterator.next()) |entry| {
                        try putUnique(out, entry.key_ptr.*, rule_index);
                    }
                } else {
                    try putUnique(out, symbol_index, rule_index);
                }
                if (symbol.kind != .variable or self.nullableRule(symbol_index) == null) break;
            }
        }
    }

    fn follows(self: *Generator, variable: usize, out: *std.AutoHashMap(usize, usize), visited: ?*std.AutoHashMap(usize, void)) !void {
        if (visited) |set| {
            if (set.contains(variable)) return;
        }
        var local_visited = std.AutoHashMap(usize, void).init(self.allocator);
        defer local_visited.deinit();
        if (visited) |set| {
            var it = set.iterator();
            while (it.next()) |entry| try local_visited.put(entry.key_ptr.*, {});
        }
        try local_visited.put(variable, {});

        for (self.rules.items, 0..) |rule, rule_index| {
            for (rule.rhs.items, 0..) |symbol_index, rhs_pos| {
                if (symbol_index != variable) continue;
                var propagated = true;
                var next_pos = rhs_pos + 1;
                while (next_pos < rule.rhs.items.len) : (next_pos += 1) {
                    const next_symbol_index = rule.rhs.items[next_pos];
                    const next_symbol = self.symbols.items[next_symbol_index];
                    if (next_symbol.kind == .variable) {
                        var next_firsts = std.AutoHashMap(usize, usize).init(self.allocator);
                        defer next_firsts.deinit();
                        try self.firsts(next_symbol_index, &next_firsts, null);
                        var it = next_firsts.iterator();
                        while (it.next()) |entry| try out.put(entry.key_ptr.*, entry.value_ptr.*);
                    } else {
                        try out.put(next_symbol_index, rule_index);
                    }
                    if (next_symbol.kind != .variable or self.nullableRule(next_symbol_index) == null) {
                        propagated = false;
                        break;
                    }
                }
                if (propagated and rule.header != variable) {
                    try self.follows(rule.header, out, &local_visited);
                }
            }
        }
    }

    fn emit(self: *Generator, writer: *std.Io.Writer) !void {
        try writer.writeAll(
            \\const builtin = @import("builtin");
            \\const std = @import("std");
            \\const root = @import("galley");
            \\const procedures = root.procedures;
            \\const error_messages = root.error_messages;
            \\const data_structures = root.data_structures;
            \\const string_utilities = root.string_utilities;
            \\
        );
        try writer.print(
            \\
            \\pub const parser_type = data_structures.ParserType.ll;
            \\pub const is_ast_enabled = {};
            \\pub const are_procedures_enabled = {};
            \\pub const is_error_recovery_enabled = {};
            \\pub const input_size_cap = u{d};
            \\pub const longest_terminal_length = {d};
            \\
            \\
        , .{
            self.options.with_ast,
            self.options.with_procedures,
            self.options.with_error_recovery,
            self.options.input_size,
            self.longestTerminalLength(),
        });

        try writer.writeAll("pub const symbols = &[_][]const u8{\n");
        for (self.symbols.items, 0..) |symbol, index| {
            try writer.writeAll("    ");
            try emitStringLiteral(writer, symbol.id);
            try writer.print(", // {d}\n", .{index});
        }
        try writer.writeAll("};\n\npub const is_terminal = &[_]bool{\n");
        for (self.symbols.items) |symbol| try writer.print("    {},\n", .{symbol.kind != .variable});
        try writer.writeAll("};\n\npub const is_generative_terminal = &[_]bool{\n");
        for (self.symbols.items) |symbol| try writer.print("    {},\n", .{symbol.kind == .generative_terminal});
        try writer.writeAll("};\n\npub const variables = &[_][]const u8{\n");
        for (self.variables.items) |symbol_index| {
            try writer.writeAll("    ");
            try emitStringLiteral(writer, self.symbols.items[symbol_index].id);
            try writer.writeAll(",\n");
        }
        try writer.writeAll("};\n\npub const symbol_by_variable = &[_]usize{\n");
        for (self.variables.items) |symbol_index| try writer.print("    {d},\n", .{symbol_index});
        try writer.writeAll("};\n\npub const rules = &[_]data_structures.Rule{\n");
        for (self.rules.items) |rule| {
            const variable_index = self.variableIndex(rule.header);
            try writer.print("    data_structures.Rule{{ .header = {d}, .right_hand_side = &[_]u16{{", .{variable_index});
            if (rule.rhs.items.len > 1) try writer.writeByte(' ');
            for (rule.rhs.items, 0..) |symbol_index, i| {
                if (i != 0) try writer.writeAll(", ");
                try writer.print("{d}", .{symbol_index});
            }
            if (rule.rhs.items.len > 1) try writer.writeByte(' ');
            try writer.writeAll("}, .right_hand_side_index = ");
            try emitStringLiteral(writer, rule.rhs_index);
            try writer.writeAll(" }, // ");
            try writer.writeAll(self.symbols.items[rule.header].id);
            try writer.writeByte('\n');
        }
        try writer.writeAll("};\n\n");
        if (self.options.with_error_recovery) try self.emitRecoverySupport(writer);
        if (self.options.with_procedures and self.options.with_ast) try self.emitProcedureBoilerplate(writer);
        try self.emitParserFunctions(writer);
        try self.emitAstSuppressedParsers(writer);
        if (self.options.with_error_recovery) try self.emitSyntaxErrorHandlers(writer);
        try writer.writeAll(
            \\pub fn parseWithResult(context: *data_structures.Context) !root.ParseResult {
            \\    _ = parse__AugmentedStart(context
        );
        if (self.has_occurrence_procedures) try writer.writeAll(", null");
        try writer.writeAll(
            \\) catch |err| switch (err) {
            \\        root.ParseError.SyntaxError => return root.ParseError.SyntaxError,
            \\        else => return err,
            \\    };
        );
        if (self.options.with_error_recovery) {
            try writer.writeAll("    if (context.hasSyntaxErrors()) return root.ParseError.SyntaxError;\n");
        }
        try writer.writeAll(
            \\
            \\    if (context.verbosityLevel() > 0) {
            \\        std.log.info("The input file was parsed successfully!", .{});
            \\    }
            \\
        );
        if (self.options.with_ast) {
            try writer.writeAll("    const ast_root: ?data_structures.ASTNode.Pointer = if (context.node_allocator.counter > 0) 0 else null;\n");
        } else {
            try writer.writeAll("    const ast_root = null;\n");
        }
        try writer.writeAll(
            \\    return .{
            \\        .parsed_bytes = context.pos() - 1,
            \\        .line = context.line,
            \\        .column = context.column,
            \\        .ast_root = ast_root,
            \\    };
            \\}
            \\
            \\pub fn parse(context: *data_structures.Context) !void {
            \\    _ = try parseWithResult(context);
            \\}
            \\
        );
    }

    fn emitRecoverySupport(self: *Generator, writer: *std.Io.Writer) !void {
        _ = self;
        try common.emitRecoveryOffsetFunction(writer, "llRecoveryOffset");
    }

    fn emitProcedureBoilerplate(self: *Generator, writer: *std.Io.Writer) !void {
        try writer.print(
            \\const ProcedureSequenceNode = struct {{
            \\    procedure: *const data_structures.Procedure,
            \\    next: ?*const ProcedureSequenceNode,
            \\}};
            \\
            \\fn makeProcedureSequence(comptime procedure_names: []const []const u8) ?*const ProcedureSequenceNode {{
            \\    if (procedure_names.len == 0) return null;
            \\    const procedure_name = procedure_names[0];
            \\    return &ProcedureSequenceNode{{
            \\        .procedure = data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, procedure_name), procedure_name),
            \\        .next = makeProcedureSequence(procedure_names[1..]),
            \\    }};
            \\}}
            \\
            \\fn runProcedureSequence(sequence: ?*const ProcedureSequenceNode, args: *data_structures.ProcedureArguments) !void {{
            \\    var current = sequence;
            \\    while (current) |entry| {{
            \\        const procedure = @as(*data_structures.Procedure, @constCast(entry.procedure));
            \\        try procedure(args);
            \\        current = entry.next;
            \\    }}
            \\}}
            \\
            \\pub const rule_procedures = rule_procedures: {{
            \\    var arr: [{d}]?*const data_structures.Procedure = .{{null}} ** {d};
            \\
            \\    for (rules, 0..) |rule, index| {{
            \\        const procedure_name = "reduction_" ++ variables[rule.header] ++ "_" ++ rule.right_hand_side_index;
            \\        if (@hasDecl(procedures, procedure_name)) {{
            \\            arr[index] = data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, procedure_name), procedure_name);
            \\        }}
            \\    }}
            \\
            \\    break :rule_procedures arr;
            \\}};
            \\
            \\pub const symbol_procedures = symbol_procedures: {{
            \\    var arr: [{d}]?*const data_structures.Procedure = .{{null}} ** {d};
            \\
            \\    for (symbols, 0..) |symbol, index| {{
            \\        const procedure_name = "reduction_" ++ symbol;
            \\        if (@hasDecl(procedures, procedure_name)) {{
            \\            arr[index] = data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, procedure_name), symbol);
            \\        }}
            \\    }}
            \\
            \\    break :symbol_procedures arr;
            \\}};
            \\
            \\const variable_procedure_names = &[_][]const []const u8{{
            \\
        , .{ self.rules.items.len, self.rules.items.len, self.symbols.items.len, self.symbols.items.len });
        for (self.variables.items) |symbol_index| {
            const symbol = self.symbols.items[symbol_index];
            try writer.writeAll("    &[_][]const u8{");
            for (symbol.procedures.items, 0..) |procedure, i| {
                if (i != 0) try writer.writeAll(", ");
                try emitStringLiteral(writer, procedure);
            }
            try writer.writeAll("},\n");
        }
        try writer.print(
            \\}};
            \\
            \\pub const variable_procedures = variable_procedures: {{
            \\    var arr: [{d}]?*const ProcedureSequenceNode = .{{null}} ** {d};
            \\
            \\    for (variable_procedure_names, 0..) |procedure_names, index| {{
            \\        arr[index] = makeProcedureSequence(procedure_names);
            \\    }}
            \\
            \\    break :variable_procedures arr;
            \\}};
            \\
            \\pub const reduction_procedure: ?*const data_structures.Procedure = if (@hasDecl(procedures, "reduction")) data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, "reduction"), "reduction") else null;
            \\
            \\
        , .{ self.variables.items.len, self.variables.items.len });
    }

    fn emitProcedureSequenceExpression(self: *Generator, writer: *std.Io.Writer, procedures_: []const []const u8) !void {
        _ = self;
        try writer.writeAll("comptime makeProcedureSequence(&[_][]const u8{");
        for (procedures_, 0..) |procedure, index| {
            if (index != 0) try writer.writeAll(", ");
            try emitStringLiteral(writer, procedure);
        }
        try writer.writeAll("})");
    }

    fn emitParserFunctions(self: *Generator, writer: *std.Io.Writer) !void {
        for (self.symbols.items, 0..) |symbol, symbol_index| {
            if (symbol.kind == .variable) {
                if (!self.hasParseEntries(symbol_index)) continue;
                try self.emitVariableParser(writer, symbol_index, false);
            } else {
                try self.emitTerminalParser(writer, symbol_index, false);
            }
            try writer.writeByte('\n');
        }
    }

    fn emitAstSuppressedParsers(self: *Generator, writer: *std.Io.Writer) !void {
        var generated = std.AutoHashMap(usize, void).init(self.allocator);
        while (generated.count() < self.needs_ast_suppressed_parser.count()) {
            for (0..self.symbols.items.len) |symbol_index| {
                if (!self.needs_ast_suppressed_parser.contains(symbol_index)) continue;
                if (generated.contains(symbol_index)) continue;
                try generated.put(symbol_index, {});

                try writer.writeByte('\n');
                const symbol = self.symbols.items[symbol_index];
                if (symbol.kind == .variable) {
                    if (!self.hasParseEntries(symbol_index)) continue;
                    try self.emitVariableParser(writer, symbol_index, true);
                } else {
                    try self.emitTerminalParser(writer, symbol_index, true);
                }
            }
        }
        if (generated.count() > 0) try writer.writeByte('\n');
    }

    fn markNeedsAstSuppressedParser(self: *Generator, symbol_index: usize) !void {
        if (self.needs_ast_suppressed_parser.contains(symbol_index)) return;
        try self.needs_ast_suppressed_parser.put(symbol_index, {});
    }

    fn parserName(self: *Generator, symbol_index: usize) ![]const u8 {
        const symbol = self.symbols.items[symbol_index];
        if (symbol.kind == .end) return self.allocator.dupe(u8, "special_EOF");
        const prefix = switch (symbol.kind) {
            .variable => "",
            .terminal => "terminal_",
            .generative_terminal => "generative_terminal_",
            .end => unreachable,
        };
        const repr = try readableSymbolName(self.allocator, symbol.id);
        const text = try std.mem.concat(self.allocator, u8, &.{ prefix, repr });
        return safeIdentifier(self.allocator, text);
    }

    fn emitVariableParser(self: *Generator, writer: *std.Io.Writer, variable: usize, skip_ast_construction: bool) !void {
        try self.emitSelfRepeatingParsers(writer, variable, skip_ast_construction);
        const name = try self.parserName(variable);
        const returns_node = self.symbolReturnsNode(variable, skip_ast_construction);
        try writer.print("// {s}Parser for Symbol \"", .{if (skip_ast_construction) "AST-Suppressed " else ""});
        try std.zig.stringEscape(self.symbols.items[variable].id, writer);
        try writer.print("\" with index {d}\n", .{variable});
        try writer.print("fn parse_{s}{s}(context: *data_structures.Context", .{ name, if (skip_ast_construction) "_" else "" });
        if (self.has_occurrence_procedures) {
            try writer.writeAll(", occurrence_procedures: ?*const ProcedureSequenceNode");
        }
        try writer.print(") anyerror!{s} {{\n", .{if (returns_node) "data_structures.ASTNode.Pointer" else "void"});
        if (self.has_occurrence_procedures and !returns_node) {
            try writer.writeAll("    _ = occurrence_procedures;\n");
        }
        if (returns_node) {
            const variable_index = self.variableIndex(variable);
            const is_var = self.options.with_procedures and self.options.with_ast and !skip_ast_construction;
            try writer.print("    {s} node_address = context.node_allocator.create(context.pos(), {d});\n\n", .{ if (is_var) "var" else "const", variable_index });
        }

        var entries = std.ArrayList(SwitchEntry).empty;

        for (self.parse_table.items) |entry| {
            if (entry.variable != variable) continue;
            const terminal = self.symbols.items[entry.terminal];
            for (terminal.terminals.items) |terminal_item| {
                try appendSwitchEntry(&entries, self.allocator, terminal_item, entry.rule);
            }
        }

        if (entries.items.len == 0) {
            const error_function_names = try self.syntaxErrorFunctionNames(variable, &.{});
            try writer.writeAll("    switch (context.head(u8, 0)) {\n");
            try writer.writeAll("        else => {\n");
            try writer.writeAll("            @branchHint(.unlikely);\n");
            try self.emitSyntaxErrorCall(writer, variable, &.{}, error_function_names, skip_ast_construction, "            ");
            try writer.writeAll("        },\n");
            try writer.writeAll("    }\n");
        } else {
            try self.emitRuleSwitch(writer, variable, entries.items, 0, "    ", skip_ast_construction, false);
            try writer.writeByte('\n');
        }
        if (returns_node) {
            try writer.writeAll("    return node_address;\n");
        }
        try writer.writeAll("}\n");
    }

    fn emitSelfRepeatingParsers(self: *Generator, writer: *std.Io.Writer, variable: usize, skip_ast_construction: bool) !void {
        for (self.rules.items, 0..) |rule, rule_index| {
            if (rule.header != variable) continue;
            for (rule.rhs.items, 0..) |symbol_index, child_index| {
                if (symbol_index != variable) continue;
                try self.emitSelfRepeatingParser(writer, variable, rule_index, child_index, skip_ast_construction);
                try writer.writeByte('\n');
            }
        }
    }

    fn symbolReturnsNode(self: *Generator, symbol_index: usize, skip_ast_construction: bool) bool {
        const symbol = self.symbols.items[symbol_index];
        return self.options.with_ast and !skip_ast_construction and switch (symbol.kind) {
            .variable => symbol.ast_enabled,
            .terminal, .generative_terminal => self.options.ast_for_terminals,
            .end => false,
        };
    }

    fn hasParseEntries(self: *Generator, variable: usize) bool {
        for (self.parse_table.items) |entry| {
            if (entry.variable == variable) return true;
        }
        return false;
    }

    fn emitSelfRepeatingParser(self: *Generator, writer: *std.Io.Writer, variable: usize, rule_index: usize, self_index: usize, skip_ast_construction: bool) !void {
        const rule = self.rules.items[rule_index];
        const name = try self.parserName(variable);
        const returns_node = self.symbolReturnsNode(variable, skip_ast_construction);
        try writer.print("// {s}Self-Repeating Parser for Symbol \"", .{if (skip_ast_construction) "AST-Suppressed " else ""});
        try self.emitSymbolRepr(writer, variable);
        try writer.print("\" at index {d} of its right hand side\n// Right hand side: -> ", .{self_index});
        try self.emitRuleSymbolsForDebug(writer, rule);
        try writer.print("\nfn parse_{s}_{s}_{d}{s}(context: *data_structures.Context", .{
            name,
            rule.rhs_index,
            self_index,
            if (skip_ast_construction) "_" else "",
        });
        if (self.has_occurrence_procedures) {
            try writer.writeAll(", occurrence_procedures: ?*const ProcedureSequenceNode");
        }
        try writer.print(") anyerror!{s} {{\n", .{if (returns_node) "data_structures.ASTNode.Pointer" else "void"});
        if (self.has_occurrence_procedures and !returns_node) {
            try writer.writeAll("    _ = occurrence_procedures;\n");
        }

        if (returns_node) {
            try writer.writeAll(
                \\    var node_address = data_structures.ASTNode.invalid_pointer;
                \\    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
                \\    _ = &node_address;
                \\    var repeating_node_address = node_address;
                \\    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths
                \\    var repeating_node: *data_structures.ASTNode = undefined;
                \\    repeating_node = repeating_node; // dummy store for 0-repetition paths
                \\    _ = &repeating_node;
                \\
            );
        } else if (rule.rhs.items.len > self_index + 1) {
            try writer.writeAll(
                \\    var counter: usize = 0;
                \\    counter = counter; // dummy store for 0-repetition paths
                \\
            );
        }

        var cases = std.ArrayList(u8).empty;
        for (self.parse_table.items) |entry| {
            if (entry.variable != variable or entry.rule != rule_index) continue;
            for (self.symbols.items[entry.terminal].terminals.items) |terminal| {
                if (terminal.len > 0 and !byteListContains(cases.items, terminal[0])) try cases.append(self.allocator, terminal[0]);
            }
        }
        std.mem.sort(u8, cases.items, {}, comptime std.sort.asc(u8));

        try writer.writeAll("\n    while (true) {\n        switch (context.head(u8, 0)) {\n            ");
        for (cases.items, 0..) |byte, i| {
            if (i != 0) try writer.writeAll(", ");
            try writer.print("{d}", .{byte});
        }
        try writer.writeAll(" => { // ");
        for (cases.items, 0..) |byte, i| {
            if (i != 0) try writer.writeAll(", ");
            try writer.writeByte('\'');
            try emitEscapedForComment(writer, &.{byte});
            try writer.writeByte('\'');
        }
        try writer.writeByte('\n');
        try self.emitDebugRuleExpansion(writer, rule, variable, "                ");

        if (returns_node) {
            try writer.print(
                \\                const temporary_address = context.node_allocator.create(context.pos(), {d});
                \\                if (node_address == data_structures.ASTNode.invalid_pointer) {{
                \\                    node_address = temporary_address;
                \\                }} else {{
                \\                    repeating_node.immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child {d}
                \\                }}
                \\                repeating_node_address = temporary_address;
                \\                repeating_node = context.node_allocator.at(repeating_node_address);
                \\
            , .{ self.variableIndex(variable), self_index });
        }

        const skip_ast_for_children = self.options.with_ast and (skip_ast_construction or !self.symbols.items[variable].ast_enabled);
        for (rule.rhs.items[0..self_index], 0..) |symbol_index, child_index| {
            try self.emitChildParseLine(writer, symbol_index, variable, rule, child_index, if (returns_node) "repeating_node" else null, if (returns_node) "repeating_node_address" else null, "                ", skip_ast_for_children);
        }
        if (!returns_node and rule.rhs.items.len > self_index + 1) {
            try writer.writeAll("                counter += 1;\n");
        }
        try writer.writeAll("            },\n            else => break,\n        }\n    }\n");

        if (returns_node) {
            try writer.print("    const exit_node = try parse_{s}(context", .{name});
            if (self.has_occurrence_procedures) {
                try writer.writeAll(", if (node_address == data_structures.ASTNode.invalid_pointer) occurrence_procedures else ");
                try self.emitProcedureSequenceExpression(writer, rule.rhs_procedures.items[self_index].items.items);
            }
            try writer.print(
                \\);
                \\    if (exit_node != data_structures.ASTNode.invalid_pointer) {{
                \\        if (node_address == data_structures.ASTNode.invalid_pointer) {{
                \\            node_address = exit_node;
                \\        }} else {{
                \\            repeating_node.immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child {d} (chain if replaceWithChildren)
                \\        }}
                \\    }}
                \\    while (repeating_node_address != data_structures.ASTNode.invalid_pointer) {{
                \\        repeating_node = context.node_allocator.at(repeating_node_address);
            , .{self_index});
            try writer.writeByte('\n');
            for (rule.rhs.items[self_index + 1 ..], self_index + 1..) |symbol_index, child_index| {
                try self.emitChildParseLine(writer, symbol_index, variable, rule, child_index, "repeating_node", "repeating_node_address", "        ", skip_ast_for_children);
            }
            try writer.writeByte('\n');
            try self.emitDebugReduction(writer, rule, variable, "        ");
            if (self.options.with_procedures and self.options.with_ast) {
                try writer.writeByte('\n');
                if (self.has_occurrence_procedures) {
                    try writer.writeAll("        const reduction_occurrence_procedures = if (repeating_node.parent == data_structures.ASTNode.invalid_pointer) occurrence_procedures else ");
                    try self.emitProcedureSequenceExpression(writer, rule.rhs_procedures.items[self_index].items.items);
                    try writer.writeAll(";\n");
                }
                try self.emitProcedureBlock(
                    writer,
                    rule_index,
                    variable,
                    "repeating_node_address",
                    if (self.has_occurrence_procedures) "reduction_occurrence_procedures" else "null",
                    "        ",
                    true,
                );
                try writer.writeByte('\n');
                try writer.writeAll(
                    \\        if (args.node) |effective| {
                    \\            if (node_address == repeating_node_address) {
                    \\                node_address = effective;
                    \\            }
                    \\        } else {
                    \\            data_structures.ASTNode.unlinkWrapper(repeating_node_address, context.node_allocator);
                    \\            if (node_address == repeating_node_address) {
                    \\                node_address = data_structures.ASTNode.invalid_pointer;
                    \\            }
                    \\        }
                    \\
                );
            }
            try writer.writeAll("        repeating_node_address = repeating_node.parent;\n");
            try writer.writeAll(
                \\    }
                \\    return node_address;
                \\
            );
        } else {
            try writer.print("    try parse_{s}{s}(context", .{ name, if (self.options.with_ast) "_" else "" });
            if (self.has_occurrence_procedures) try writer.writeAll(", null");
            try writer.writeAll(");\n");
            if (rule.rhs.items.len > self_index + 1) {
                try writer.writeAll("    for (0..counter) |_| {\n");
                for (rule.rhs.items[self_index + 1 ..], self_index + 1..) |symbol_index, child_index| {
                    try self.emitChildParseLine(writer, symbol_index, variable, rule, child_index, null, null, "        ", skip_ast_for_children);
                }
                try writer.writeAll("    }\n");
            }
        }

        try writer.writeAll("}\n");
    }

    fn emitTerminalParser(self: *Generator, writer: *std.Io.Writer, terminal_index: usize, skip_ast_construction: bool) !void {
        const symbol = self.symbols.items[terminal_index];
        const name = try self.parserName(terminal_index);
        const returns_node = self.symbolReturnsNode(terminal_index, skip_ast_construction);
        try writer.print("// {s}Parser for Symbol \"", .{if (skip_ast_construction) "AST-Suppressed " else ""});
        try self.emitSymbolRepr(writer, terminal_index);
        try writer.print("\" with index {d}\n", .{terminal_index});
        try writer.print("inline fn parse_{s}{s}(context: *data_structures.Context", .{ name, if (skip_ast_construction) "_" else "" });
        if (self.has_occurrence_procedures) {
            try writer.writeAll(", occurrence_procedures: ?*const ProcedureSequenceNode");
        }
        try writer.print(") anyerror!{s} {{\n", .{if (returns_node) "data_structures.ASTNode.Pointer" else "void"});
        if (self.has_occurrence_procedures and !returns_node) {
            try writer.writeAll("    _ = occurrence_procedures;\n");
        }
        if (returns_node) {
            try writer.print("    {s} node_address = context.node_allocator.create(context.pos(), data_structures.ASTNode.invalid_variable);\n\n", .{
                if (self.options.with_procedures and self.options.with_ast) "var" else "const",
            });
        }

        var entries = std.ArrayList(SwitchEntry).empty;
        for (symbol.terminals.items) |terminal| {
            try appendSwitchEntry(&entries, self.allocator, terminal, 0);
        }
        try self.emitRuleSwitch(writer, terminal_index, entries.items, 0, "    ", skip_ast_construction, false);
        try writer.writeByte('\n');
        if (returns_node) {
            if (self.options.with_procedures and self.options.with_ast) {
                try self.emitTerminalProcedureBlock(
                    writer,
                    terminal_index,
                    "node_address",
                    if (self.has_occurrence_procedures) "occurrence_procedures" else "null",
                    "    ",
                );
                try writer.writeAll("    node_address = args.node orelse data_structures.ASTNode.invalid_pointer;\n\n");
            }
            try writer.writeAll("    return node_address;\n");
        }

        try writer.writeAll("}\n");
    }

    const SwitchEntry = struct {
        terminal: []const u8,
        rule: usize,
    };

    const SwitchGroup = struct {
        heads: std.ArrayList([]const u8) = .empty,
        payload: std.ArrayList(SwitchEntry) = .empty,
    };

    fn appendSwitchEntry(entries: *std.ArrayList(SwitchEntry), allocator: std.mem.Allocator, terminal: []const u8, rule: usize) !void {
        for (entries.items) |entry| {
            if (entry.rule == rule and std.mem.eql(u8, entry.terminal, terminal)) return;
        }
        try entries.append(allocator, .{ .terminal = terminal, .rule = rule });
    }

    fn appendUniqueString(items: *std.ArrayList([]const u8), allocator: std.mem.Allocator, value: []const u8) !void {
        for (items.items) |item| {
            if (std.mem.eql(u8, item, value)) return;
        }
        try items.append(allocator, value);
    }

    fn recoveryTerminalStringsForSequence(self: *Generator, sequence: []const usize, follow_variable: ?usize) !std.ArrayList([]const u8) {
        var result = std.ArrayList([]const u8).empty;
        var sequence_is_nullable = true;
        for (sequence) |symbol_index| {
            const symbol = self.symbols.items[symbol_index];
            if (symbol.kind == .variable) {
                var first_set = std.AutoHashMap(usize, usize).init(self.allocator);
                defer first_set.deinit();
                try self.firsts(symbol_index, &first_set, null);
                var iterator = first_set.iterator();
                while (iterator.next()) |entry| {
                    for (self.symbols.items[entry.key_ptr.*].terminals.items) |terminal| {
                        try appendUniqueString(&result, self.allocator, terminal);
                    }
                }
                if (self.nullableRule(symbol_index) != null) continue;
            } else {
                for (symbol.terminals.items) |terminal| {
                    try appendUniqueString(&result, self.allocator, terminal);
                }
            }
            sequence_is_nullable = false;
            break;
        }

        if (sequence_is_nullable) {
            if (follow_variable) |variable| {
                var follow_set = std.AutoHashMap(usize, usize).init(self.allocator);
                defer follow_set.deinit();
                try self.follows(variable, &follow_set, null);
                var iterator = follow_set.iterator();
                while (iterator.next()) |entry| {
                    for (self.symbols.items[entry.key_ptr.*].terminals.items) |terminal| {
                        try appendUniqueString(&result, self.allocator, terminal);
                    }
                }
            }
        }
        std.mem.sort([]const u8, result.items, {}, stringLessThan);
        return result;
    }

    fn emitRecoveryCandidates(self: *Generator, writer: *std.Io.Writer, candidates: []const []const u8) !void {
        _ = self;
        try writer.writeAll("&[_][]const u8{");
        for (candidates, 0..) |candidate, index| {
            if (index != 0) try writer.writeAll(", ");
            try emitStringLiteral(writer, candidate);
        }
        try writer.writeAll("}");
    }

    fn stringLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
        return std.mem.order(u8, lhs, rhs) == .lt;
    }

    fn joinWithOr(allocator: std.mem.Allocator, items: []const []const u8) ![]const u8 {
        if (items.len == 0) return allocator.dupe(u8, "valid_input");
        if (items.len == 1) return allocator.dupe(u8, items[0]);

        var out = std.ArrayList(u8).empty;
        for (items, 0..) |item, index| {
            if (index != 0) try out.appendSlice(allocator, "_or_");
            try out.appendSlice(allocator, item);
        }
        return out.toOwnedSlice(allocator);
    }

    fn switchEntryLessThan(_: void, lhs: SwitchEntry, rhs: SwitchEntry) bool {
        const order = std.mem.order(u8, lhs.terminal, rhs.terminal);
        if (order != .eq) return order == .lt;
        return lhs.rule < rhs.rule;
    }

    fn headLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
        return common.headLessThan({}, lhs, rhs);
    }

    fn byteListContains(items: []const u8, byte: u8) bool {
        for (items) |item| if (item == byte) return true;
        return false;
    }

    fn switchGroupLessThan(_: void, lhs: SwitchGroup, rhs: SwitchGroup) bool {
        return std.mem.order(u8, lhs.heads.items[0], rhs.heads.items[0]) == .lt;
    }

    fn switchPayloadEqual(lhs: []const SwitchEntry, rhs: []const SwitchEntry) bool {
        if (lhs.len != rhs.len) return false;
        for (lhs, rhs) |a, b| {
            if (a.rule != b.rule or !std.mem.eql(u8, a.terminal, b.terminal)) return false;
        }
        return true;
    }

    fn switchStepLength(entries: []const SwitchEntry) usize {
        var step_length: usize = std.math.maxInt(usize);
        for (entries) |entry| {
            if (entry.terminal.len > 0) step_length = @min(step_length, entry.terminal.len);
        }
        return step_length;
    }

    fn buildSwitchGroups(self: *Generator, entries: []const SwitchEntry, step_length: usize) !std.ArrayList(SwitchGroup) {
        var heads = std.ArrayList([]const u8).empty;
        for (entries) |entry| {
            if (entry.terminal.len == 0) continue;
            const head = entry.terminal[0..step_length];
            for (heads.items) |existing| {
                if (std.mem.eql(u8, existing, head)) break;
            } else {
                try heads.append(self.allocator, head);
            }
        }
        std.mem.sort([]const u8, heads.items, {}, headLessThan);

        var groups = std.ArrayList(SwitchGroup).empty;
        for (heads.items) |head| {
            var payload = std.ArrayList(SwitchEntry).empty;
            for (entries) |entry| {
                if (entry.terminal.len == 0) continue;
                if (!std.mem.eql(u8, entry.terminal[0..step_length], head)) continue;
                try appendSwitchEntry(&payload, self.allocator, entry.terminal[step_length..], entry.rule);
            }
            std.mem.sort(SwitchEntry, payload.items, {}, switchEntryLessThan);

            var found: ?usize = null;
            for (groups.items, 0..) |group, i| {
                if (switchPayloadEqual(group.payload.items, payload.items)) {
                    found = i;
                    break;
                }
            }
            if (found) |index| {
                try groups.items[index].heads.append(self.allocator, head);
            } else {
                var group = SwitchGroup{ .payload = payload };
                try group.heads.append(self.allocator, head);
                try groups.append(self.allocator, group);
            }
        }

        for (groups.items) |*group| {
            std.mem.sort([]const u8, group.heads.items, {}, headLessThan);
        }
        std.mem.sort(SwitchGroup, groups.items, {}, switchGroupLessThan);
        return groups;
    }

    fn emitRuleSwitch(self: *Generator, writer: *std.Io.Writer, symbol_index: usize, entries: []const SwitchEntry, prefix_length: usize, indent: []const u8, skip_ast_construction: bool, is_self_repeating: bool) !void {
        var empty_rule: ?usize = null;
        var non_empty_count: usize = 0;
        for (entries) |entry| {
            if (entry.terminal.len == 0) {
                empty_rule = entry.rule;
            } else {
                non_empty_count += 1;
            }
        }
        if (non_empty_count == 0) {
            if (empty_rule) |rule_index| {
                try self.emitSwitchLeaf(writer, symbol_index, rule_index, prefix_length, indent, skip_ast_construction);
                return;
            }
        }

        const step_length = switchStepLength(entries);
        try writer.print("{s}switch (context.head(u{d}, {d})) {{\n", .{ indent, step_length * 8, prefix_length });
        const groups = try self.buildSwitchGroups(entries, step_length);
        for (groups.items) |group| {
            try writer.print("{s}    ", .{indent});
            for (group.heads.items, 0..) |head, i| {
                if (i != 0) try writer.writeAll(", ");
                try writer.print("{d}", .{bytesToInt(head)});
            }
            try writer.writeAll(" => { // ");
            for (group.heads.items, 0..) |head, i| {
                if (i != 0) try writer.writeAll(", ");
                try writer.writeByte('\'');
                try emitEscapedForComment(writer, head);
                try writer.writeByte('\'');
            }
            try writer.writeByte('\n');

            if (group.payload.items.len == 1 and group.payload.items[0].terminal.len == 0) {
                try self.emitSwitchLeaf(writer, symbol_index, group.payload.items[0].rule, prefix_length + step_length, indent, skip_ast_construction);
            } else {
                var child_indent = std.ArrayList(u8).empty;
                try child_indent.appendSlice(self.allocator, indent);
                try child_indent.appendSlice(self.allocator, "        ");
                try self.emitRuleSwitch(writer, symbol_index, group.payload.items, prefix_length + step_length, child_indent.items, skip_ast_construction, is_self_repeating);
                try writer.writeByte('\n');
            }
            try writer.print("{s}    }},\n", .{indent});
        }
        try self.emitSwitchElse(writer, symbol_index, groups.items, empty_rule, prefix_length, indent, skip_ast_construction, is_self_repeating);
        try writer.print("{s}}}", .{indent});
    }

    fn emitSwitchLeaf(self: *Generator, writer: *std.Io.Writer, symbol_index: usize, rule_index: usize, length: usize, indent: []const u8, skip_ast_construction: bool) !void {
        const symbol = self.symbols.items[symbol_index];
        if (symbol.kind == .variable) {
            try self.emitRuleBody(writer, rule_index, symbol_index, try indented(self.allocator, indent, 8), skip_ast_construction);
        } else {
            try writer.print("{s}        context.releaseToken({d});\n", .{ indent, length });
        }
    }

    fn emitSwitchElse(self: *Generator, writer: *std.Io.Writer, symbol_index: usize, groups: []const SwitchGroup, empty_rule: ?usize, prefix_length: usize, indent: []const u8, skip_ast_construction: bool, is_self_repeating: bool) !void {
        if (empty_rule) |rule_index| {
            try writer.print("{s}    else => {{ // ''\n", .{indent});
            try self.emitSwitchLeaf(writer, symbol_index, rule_index, prefix_length, indent, skip_ast_construction);
            try writer.print("{s}    }},\n", .{indent});
            return;
        }
        if (is_self_repeating) {
            try writer.print("{s}    else => break,\n", .{indent});
            return;
        }
        var expected_heads = std.ArrayList([]const u8).empty;
        for (groups) |group| {
            for (group.heads.items) |head| try expected_heads.append(self.allocator, head);
        }
        std.mem.sort([]const u8, expected_heads.items, {}, headLessThan);
        const error_function_names = try self.syntaxErrorFunctionNames(symbol_index, groups);
        try writer.print("{s}    else => {{\n", .{indent});
        try writer.print("{s}        @branchHint(.unlikely);\n", .{indent});
        try self.emitSyntaxErrorCall(writer, symbol_index, expected_heads.items, error_function_names, skip_ast_construction, try indented(self.allocator, indent, 8));
        try writer.print("{s}    }},\n", .{indent});
    }

    fn emitSyntaxErrorCall(
        self: *Generator,
        writer: *std.Io.Writer,
        symbol_index: usize,
        expected_tokens: []const []const u8,
        function_names: SyntaxErrorFunctionNames,
        skip_ast_construction: bool,
        indent: []const u8,
    ) !void {
        if (!self.options.with_error_recovery) {
            const symbol = self.symbols.items[symbol_index];
            try writer.print("{s}try context.recordSyntaxDiagnostic(.{{ .while_parsing = ", .{indent});
            try emitStringLiteral(writer, symbol.id);
            try writer.writeAll(" }, ");
            try self.emitRecoveryCandidates(writer, expected_tokens);
            try writer.writeAll(");\n");
            try writer.print("{s}if (!builtin.is_test) {{\n", .{indent});
            try self.emitSyntaxErrorMessagePrint(writer, function_names.exact, function_names.symbol, try indented(self.allocator, indent, 4));
            try writer.print("{s}}}\n", .{indent});
            try writer.print("{s}return root.ParseError.SyntaxError;\n", .{indent});
            return;
        }

        const handler_name = try std.fmt.allocPrint(self.allocator, "ll_syntax_error_{d}", .{self.syntax_error_handlers.items.len});
        try self.syntax_error_handlers.append(self.allocator, .{
            .name = handler_name,
            .symbol_index = symbol_index,
            .expected_tokens = try self.allocator.dupe([]const u8, expected_tokens),
            .exact_name = function_names.exact,
            .symbol_name = function_names.symbol,
            .skip_ast_construction = skip_ast_construction,
        });
        const can_tail_call = !self.has_occurrence_procedures and (!self.options.with_ast or
            (self.symbols.items[symbol_index].kind == .variable and !self.symbolReturnsNode(symbol_index, skip_ast_construction)));
        if (can_tail_call) {
            try writer.print("{s}if (comptime builtin.zig_backend == .stage2_llvm or builtin.zig_backend == .stage2_aarch64) {{\n", .{indent});
            try writer.print("{s}    return @call(.always_tail, {s}, .{{context}});\n", .{ indent, handler_name });
            try writer.print("{s}}}\n", .{indent});
        }
        try writer.print("{s}return {s}(context);\n", .{ indent, handler_name });
    }

    fn emitSyntaxErrorHandlers(self: *Generator, writer: *std.Io.Writer) !void {
        for (self.syntax_error_handlers.items) |spec| {
            const symbol = self.symbols.items[spec.symbol_index];
            const returns_node = self.symbolReturnsNode(spec.symbol_index, spec.skip_ast_construction);
            const candidates = try self.recoveryTerminalStringsForSequence(&.{spec.symbol_index}, if (symbol.kind == .variable) spec.symbol_index else null);

            try writer.print("\nfn {s}(context: *data_structures.Context) anyerror!{s} {{\n", .{
                spec.name,
                if (returns_node) "data_structures.ASTNode.Pointer" else "void",
            });
            try writer.writeAll("    @branchHint(.cold);\n");
            try writer.writeAll("    const report_syntax_error = context.beginSyntaxRecovery();\n");
            try writer.writeAll("    if (report_syntax_error) {\n");
            try writer.writeAll("        try context.recordSyntaxDiagnostic(.{ .while_parsing = ");
            try emitStringLiteral(writer, symbol.id);
            try writer.writeAll(" }, ");
            try self.emitRecoveryCandidates(writer, spec.expected_tokens);
            try writer.writeAll(");\n");
            try writer.writeAll("        if (!builtin.is_test) {\n");
            try self.emitSyntaxErrorMessagePrint(writer, spec.exact_name, spec.symbol_name, "            ");
            try writer.writeAll("        }\n");
            try writer.writeAll("    }\n");
            try writer.writeAll("    if (report_syntax_error and context.syntaxErrorLimitReached()) return root.ParseError.SyntaxError;\n");
            try writer.writeAll("    if (try llRecoveryOffset(context, ");
            try self.emitRecoveryCandidates(writer, candidates.items);
            try writer.writeAll(", if (report_syntax_error) 1 else 0)) |recovery_offset| {\n");
            try writer.writeAll("        context.skipRecoveryInput(recovery_offset);\n");
            try writer.writeAll("    }\n");
            if (returns_node) {
                try writer.writeAll("    return data_structures.ASTNode.invalid_pointer;\n");
            }
            try writer.writeAll("}\n");
        }
    }

    const SyntaxErrorFunctionNames = struct {
        exact: []const u8,
        symbol: []const u8,
    };

    fn syntaxErrorFunctionNames(self: *Generator, symbol_index: usize, groups: []const SwitchGroup) !SyntaxErrorFunctionNames {
        const symbol_stem = try self.parserName(symbol_index);
        const expected_stem = try self.syntaxErrorExpectedStem(symbol_index, groups);
        const exact = try std.fmt.allocPrint(self.allocator, "syntax_error_ll_{s}__expected_{s}", .{ symbol_stem, expected_stem });
        const symbol = try std.fmt.allocPrint(self.allocator, "syntax_error_ll_{s}", .{symbol_stem});
        try self.appendErrorMessageSpec(exact);
        return .{ .exact = exact, .symbol = symbol };
    }

    fn syntaxErrorExpectedStem(self: *Generator, symbol_index: usize, groups: []const SwitchGroup) ![]const u8 {
        var stems = std.ArrayList([]const u8).empty;
        if (groups.len == 0) {
            try appendUniqueString(&stems, self.allocator, try std.fmt.allocPrint(self.allocator, "valid_{s}", .{try self.parserName(symbol_index)}));
        } else if (self.symbols.items[symbol_index].kind == .variable) {
            for (groups) |group| {
                for (group.payload.items) |entry| {
                    try appendUniqueString(&stems, self.allocator, try self.ruleExpectedStem(symbol_index, entry.rule));
                }
            }
        } else {
            try appendUniqueString(&stems, self.allocator, try self.parserName(symbol_index));
        }
        if (stems.items.len == 0) {
            try appendUniqueString(&stems, self.allocator, try std.fmt.allocPrint(self.allocator, "valid_{s}", .{try self.parserName(symbol_index)}));
        }
        std.mem.sort([]const u8, stems.items, {}, stringLessThan);
        return try joinWithOr(self.allocator, stems.items);
    }

    fn ruleExpectedStem(self: *Generator, symbol_index: usize, rule_index: usize) ![]const u8 {
        if (rule_index >= self.rules.items.len) return self.parserName(symbol_index);
        const rule = self.rules.items[rule_index];
        if (rule.header != symbol_index) return self.parserName(symbol_index);
        if (rule.rhs.items.len == 0) {
            return try std.fmt.allocPrint(self.allocator, "end_of_{s}", .{try self.parserName(symbol_index)});
        }
        return self.parserName(rule.rhs.items[0]);
    }

    fn appendErrorMessageSpec(self: *Generator, name: []const u8) !void {
        for (self.error_message_specs.items) |spec| {
            if (std.mem.eql(u8, spec.name, name)) return;
        }
        try self.error_message_specs.append(self.allocator, .{ .name = name });
    }

    fn emitSyntaxErrorMessagePrint(self: *Generator, writer: *std.Io.Writer, exact_name: []const u8, symbol_name: []const u8, indent: []const u8) !void {
        try writer.print("{s}const diagnostic = context.runtime().last_diagnostic.?;\n", .{indent});
        try writer.print("{s}const diagnostic_message = if (comptime @hasDecl(error_messages, \"{s}\"))\n", .{ indent, exact_name });
        try self.emitSyntaxErrorHookCall(writer, "", exact_name, indent);
        try writer.print("{s}else if (comptime @hasDecl(error_messages, \"{s}\"))\n", .{ indent, symbol_name });
        try self.emitSyntaxErrorHookCall(writer, "", symbol_name, indent);
        try writer.print("{s}else if (comptime @hasDecl(error_messages, \"syntax_error_ll\"))\n", .{indent});
        try self.emitSyntaxErrorHookCall(writer, "error_messages.syntax_error_ll", null, indent);
        try writer.print("{s}else if (comptime @hasDecl(error_messages, \"syntax_error\"))\n", .{indent});
        try self.emitSyntaxErrorHookCall(writer, "error_messages.syntax_error", null, indent);
        try writer.print(
            \\{s}else
            \\{s}    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
            \\{s}std.debug.print("{{s}}", .{{diagnostic_message}});
            \\
        , .{ indent, indent, indent });
    }

    fn emitSyntaxErrorHookCall(self: *Generator, writer: *std.Io.Writer, callee_prefix: []const u8, field_name: ?[]const u8, indent: []const u8) !void {
        _ = self;
        if (field_name) |name| {
            try writer.print(
                \\{s}    @field(error_messages, "{s}")(.{{
                \\{s}        .allocator = context.runtime().arena_allocator,
                \\{s}        .context = context,
                \\{s}        .diagnostic = diagnostic,
                \\{s}        .style = .ansi,
                \\{s}    }}) catch ""
                \\
            , .{ indent, name, indent, indent, indent, indent, indent });
        } else {
            try writer.print(
                \\{s}    {s}(.{{
                \\{s}        .allocator = context.runtime().arena_allocator,
                \\{s}        .context = context,
                \\{s}        .diagnostic = diagnostic,
                \\{s}        .style = .ansi,
                \\{s}    }}) catch ""
                \\
            , .{ indent, callee_prefix, indent, indent, indent, indent, indent });
        }
    }

    fn emitRuleBody(self: *Generator, writer: *std.Io.Writer, rule_index: usize, parent_variable: usize, indent: []const u8, skip_ast_construction: bool) !void {
        const rule = self.rules.items[rule_index];
        const parent_returns_node = self.symbolReturnsNode(parent_variable, skip_ast_construction);
        try self.emitDebugRuleExpansion(writer, rule, parent_variable, indent);

        if (rule.rhs.items.len != 0) {
            for (rule.rhs.items, 0..) |symbol_index, child_index| {
                try self.emitChildParseLine(
                    writer,
                    symbol_index,
                    parent_variable,
                    rule,
                    child_index,
                    if (parent_returns_node) "node_address" else null,
                    if (parent_returns_node) "node_address" else null,
                    indent,
                    skip_ast_construction,
                );
            }
        }

        try self.emitRuleFinalize(writer, rule_index, parent_variable, indent, skip_ast_construction);
    }

    fn emitRuleFinalize(self: *Generator, writer: *std.Io.Writer, rule_index: usize, parent_variable: usize, indent: []const u8, skip_ast_construction: bool) !void {
        const rule = self.rules.items[rule_index];
        const parent_returns_node = self.symbolReturnsNode(parent_variable, skip_ast_construction);

        if (self.options.with_procedures and self.options.with_ast and parent_returns_node) {
            try self.emitProcedureBlock(
                writer,
                rule_index,
                parent_variable,
                "node_address",
                if (self.has_occurrence_procedures) "occurrence_procedures" else "null",
                indent,
                true,
            );
            try writer.print("{s}node_address = args.node orelse data_structures.ASTNode.invalid_pointer;\n", .{indent});
        }

        if (self.options.with_procedures and self.options.with_ast and parent_returns_node) try writer.writeByte('\n');
        try self.emitDebugReduction(writer, rule, parent_variable, indent);
    }

    fn emitChildParseLine(self: *Generator, writer: *std.Io.Writer, symbol_index: usize, parent_variable: usize, rule: Rule, child_index: usize, parent: ?[]const u8, parent_address: ?[]const u8, indent: []const u8, skip_ast_construction: bool) !void {
        const name = try self.parserName(symbol_index);
        const child = self.symbols.items[symbol_index];
        const child_skips_ast_construction = self.options.with_ast and (skip_ast_construction or (child.kind == .variable and !child.ast_enabled));
        if (child_skips_ast_construction) try self.markNeedsAstSuppressedParser(symbol_index);
        const child_returns_node = self.symbolReturnsNode(symbol_index, child_skips_ast_construction);
        const call_name = if (symbol_index == parent_variable)
            try std.fmt.allocPrint(self.allocator, "{s}_{s}_{d}", .{ name, rule.rhs_index, child_index })
        else
            name;
        if (parent != null) {
            if (child_returns_node) {
                try writer.print("{s}{{\n{s}    const child_node = try parse_{s}(context", .{ indent, indent, call_name });
                try self.emitChildOccurrenceArgument(writer, rule, child_index, child_returns_node);
                try writer.print(
                    \\);
                    \\{s}    if (child_node != data_structures.ASTNode.invalid_pointer) {{
                    \\{s}        context.node_allocator.at({s}).immediateAppendChildren({s}, child_node, context.node_allocator); // child {d} (chain if replaceWithChildren)
                    \\{s}    }}
                    \\{s}}}
                    \\
                , .{ indent, indent, parent_address.?, parent_address.?, child_index, indent, indent });
            } else {
                try writer.print("{s}try parse_{s}{s}(context", .{ indent, call_name, if (child_skips_ast_construction) "_" else "" });
                try self.emitChildOccurrenceArgument(writer, rule, child_index, false);
                try writer.print("); // child {d}\n", .{child_index});
            }
        } else if (child_returns_node) {
            try writer.print("{s}_ = try parse_{s}(context", .{ indent, call_name });
            try self.emitChildOccurrenceArgument(writer, rule, child_index, true);
            try writer.print("); // child {d}\n", .{child_index});
        } else {
            try writer.print("{s}try parse_{s}{s}(context", .{ indent, call_name, if (child_skips_ast_construction) "_" else "" });
            try self.emitChildOccurrenceArgument(writer, rule, child_index, false);
            try writer.print("); // child {d}\n", .{child_index});
        }
    }

    fn emitChildOccurrenceArgument(self: *Generator, writer: *std.Io.Writer, rule: Rule, child_index: usize, child_returns_node: bool) !void {
        if (!self.has_occurrence_procedures) return;
        try writer.writeAll(", ");
        if (child_returns_node) {
            try self.emitProcedureSequenceExpression(writer, rule.rhs_procedures.items[child_index].items.items);
        } else {
            try writer.writeAll("null");
        }
    }

    fn emitProcedureBlock(self: *Generator, writer: *std.Io.Writer, rule_index: usize, parent_variable: usize, node_expr: []const u8, occurrence_expr: []const u8, indent: []const u8, include_outcome: bool) !void {
        const rule = self.rules.items[rule_index];
        const variable_index = self.variableIndex(parent_variable);
        try writer.print(
            \\{s}var args = data_structures.ProcedureArguments{{
            \\{s}    .context = context,
            \\{s}    .rule = rules[{d}],
            \\{s}    .node = {s},
            \\{s}}};
            \\{s}_ = &args;
            \\{s}args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            \\
        , .{
            indent, indent, indent, rule_index, indent, node_expr, indent, indent, indent,
        });
        if (self.has_occurrence_procedures) {
            try writer.print("{s}try runProcedureSequence({s}, &args);\n", .{ indent, occurrence_expr });
        }
        try writer.print("{s}try runProcedureSequence(", .{indent});
        try self.emitProcedureSequenceExpression(writer, rule.procedures.items);
        try writer.writeAll(", &args);\n");
        try writer.print(
            \\{s}if (comptime rule_procedures[{d}]) |procedure_pointer| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            \\{s}    try procedure(&args);
            \\{s}}}
            \\{s}try runProcedureSequence(variable_procedures[{d}], &args);
            \\{s}if (comptime symbol_procedures[{d}]) |procedure_pointer| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            \\{s}    try procedure(&args);
            \\{s}}}
            \\{s}if (comptime reduction_procedure) |procedure_pointer| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            \\{s}    try procedure(&args);
            \\{s}}}
            \\
        , .{
            indent, rule_index,     indent, indent,          indent,
            indent, variable_index, indent, parent_variable, indent,
            indent, indent,         indent, indent,          indent,
            indent,
        });
        if (include_outcome) {
            try writer.print(
                \\
                \\{s}if (comptime builtin.mode == .Debug) {{
                \\{s}    if (context.verbosityLevel() > 2) {{
                \\{s}        std.debug.print("Procedure outcome for 
            , .{ indent, indent, indent });
            try emitFormatToken(writer, self.symbols.items[parent_variable].id);
            try writer.print(
                \\: {{f}}\n", .{{
                \\{s}            string_utilities.fmtASTNode(args.node, context),
                \\{s}        }});
                \\{s}    }}
                \\{s}}}
                \\
            , .{ indent, indent, indent, indent });
        }
    }

    fn emitTerminalProcedureBlock(self: *Generator, writer: *std.Io.Writer, terminal_index: usize, node_expr: []const u8, occurrence_expr: []const u8, indent: []const u8) !void {
        try writer.print(
            \\{s}var args = data_structures.ProcedureArguments{{
            \\{s}    .context = context,
            \\{s}    .rule = null,
            \\{s}    .node = {s},
            \\{s}}};
        , .{ indent, indent, indent, indent, node_expr, indent });
        if (self.has_occurrence_procedures) {
            try writer.print("{s}try runProcedureSequence({s}, &args);\n", .{ indent, occurrence_expr });
        }
        try writer.print(
            \\{s}if (comptime symbol_procedures[{d}]) |procedure_pointer| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            \\{s}    try procedure(&args);
            \\{s}}}
            \\{s}if (comptime reduction_procedure) |procedure_pointer| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            \\{s}    try procedure(&args);
            \\{s}}}
            \\
        , .{
            indent, terminal_index, indent, indent, indent,
            indent, indent,         indent, indent,
        });
    }

    fn emitDebugRuleExpansion(self: *Generator, writer: *std.Io.Writer, rule: Rule, parent_variable: usize, indent: []const u8) !void {
        try writer.print(
            \\{s}if (comptime builtin.mode == .Debug) {{
            \\{s}    if (context.verbosityLevel() > 1) {{
            \\{s}        std.debug.print("Rule expansion: 
        , .{ indent, indent, indent });
        try emitFormatToken(writer, self.symbols.items[parent_variable].id);
        try writer.writeAll(" -> ");
        try self.emitRuleSymbolsForDebug(writer, rule);
        try writer.print(
            \\\n", .{{}});
            \\{s}    }}
            \\{s}}}
            \\
        , .{ indent, indent });
    }

    fn emitDebugReduction(self: *Generator, writer: *std.Io.Writer, rule: Rule, parent_variable: usize, indent: []const u8) !void {
        try writer.print(
            \\{s}if (comptime builtin.mode == .Debug) {{
            \\{s}    if (context.verbosityLevel() > 1) {{
            \\{s}        std.debug.print("Reduction: 
        , .{ indent, indent, indent });
        try emitFormatToken(writer, self.symbols.items[parent_variable].id);
        try writer.writeAll(" <~ ");
        try self.emitRuleSymbolsForDebug(writer, rule);
        try writer.print(
            \\\n", .{{}});
            \\{s}    }}
            \\{s}}}
            \\
        , .{ indent, indent });
    }

    fn emitRuleSymbolsForDebug(self: *Generator, writer: *std.Io.Writer, rule: Rule) !void {
        for (rule.rhs.items, 0..) |symbol_index, i| {
            if (i != 0) try writer.writeAll(", ");
            const symbol = self.symbols.items[symbol_index];
            if (symbol.kind == .variable) {
                try emitFormatToken(writer, symbol.id);
            } else {
                try writer.writeByte('\'');
                try emitFormatToken(writer, symbol.id);
                try writer.writeByte('\'');
            }
        }
    }

    fn emitSymbolRepr(self: *Generator, writer: *std.Io.Writer, symbol_index: usize) !void {
        const symbol = self.symbols.items[symbol_index];
        if (symbol.kind == .end) {
            try writer.writeAll("special_EOF");
            return;
        }
        switch (symbol.kind) {
            .variable => {},
            .terminal => try writer.writeAll("terminal_"),
            .generative_terminal => try writer.writeAll("generative_terminal_"),
            .end => unreachable,
        }
        const repr = try readableSymbolName(self.allocator, symbol.id);
        try writer.writeAll(repr);
    }

    fn variableIndex(self: *Generator, symbol_index: usize) usize {
        for (self.variables.items, 0..) |candidate, index| {
            if (candidate == symbol_index) return index;
        }
        unreachable;
    }

    fn addParseEntry(self: *Generator, entry: ParseEntry) !void {
        for (self.parse_table.items) |existing| {
            if (existing.variable == entry.variable and existing.terminal == entry.terminal) {
                if (existing.rule != entry.rule) return error.AmbiguousGrammar;
                return;
            }
        }
        try self.parse_table.append(self.allocator, entry);
    }

    fn longestTerminalLength(self: *Generator) usize {
        return common.longestTerminalLength(self.symbols.items);
    }
};

pub fn emitParser(allocator: std.mem.Allocator, grammar: anytype, writer: *std.Io.Writer) !void {
    try emitParserWithOptions(allocator, grammar, writer, .{});
}

pub fn emitParserWithOptions(allocator: std.mem.Allocator, grammar: anytype, writer: *std.Io.Writer, options: Options) !void {
    var generator = Generator.init(allocator, options);
    try generator.fromGrammar(grammar);
    try generator.emit(writer);
}

pub fn emitErrorMessagesWithOptions(allocator: std.mem.Allocator, grammar: anytype, writer: *std.Io.Writer, options: Options) !void {
    var generator = Generator.init(allocator, options);
    try generator.fromGrammar(grammar);

    var generated_parser: std.Io.Writer.Allocating = .init(allocator);
    defer generated_parser.deinit();
    try generator.emit(&generated_parser.writer);

    try common.emitErrorMessageFile(writer, "LL", generator.error_message_specs.items);
}

fn putUnique(map: *std.AutoHashMap(usize, usize), key: usize, value: usize) !void {
    if (map.get(key)) |existing| {
        if (existing != value) return error.AmbiguousGrammar;
        return;
    }
    try map.put(key, value);
}
