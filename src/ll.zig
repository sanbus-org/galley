const clap = @import("clap");
const root = @import("root");
const std = @import("std");

pub const procedures = @import("procedures");
pub const parse_table = @import("parse-table");

const data_structures = root.data_structures;

pub fn parse(init: std.process.Init, program_file: std.Io.File) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help                          Display this help and exit.
        \\-v, --verbosity <VERBOSITY_LEVEL>   An option parameter, which takes a value.
        \\-r, --repeats <REPEAT_TIMES>        Repeat the parse process. Useful for benchmarking.
        \\<FILE>...
        \\
    );
    const parsers = comptime .{
        .VERBOSITY_LEVEL = clap.parsers.int(usize, 3),
        .REPEAT_TIMES = clap.parsers.int(usize, 10),
        .FILE = clap.parsers.string,
    };
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, init.minimal.args, .{
        .diagnostic = &diag,
        .allocator = init.gpa,
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(init.io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
        const stdout = &stdout_writer.interface;

        try clap.usageToFile(init.io, .stdout(), clap.Help, &params);
        _ = try stdout.writeAll("\n\n");
        try stdout.flush();
        return clap.helpToFile(init.io, .stdout(), clap.Help, &params, .{});
    }

    const verbosity = if (res.args.verbosity) |verbosity| verbosity else 0;
    const repeats = if (res.args.repeats) |repeats| repeats else 1;

    const gpa = init.gpa;
    const arena_allocator = init.arena.allocator();
    const io = init.io;

    for (0..repeats) |_| benchmark_loop: {
        var symbol_stack = try std.ArrayList(i16).initCapacity(gpa, 64);
        defer symbol_stack.deinit(gpa);

        var semantic_stack = try std.ArrayList(?*root.data_structures.ASTNode).initCapacity(gpa, 64);
        defer semantic_stack.deinit(gpa);

        var buffer: [16 * 1024]u8 = undefined;
        var reader = program_file.reader(io, &buffer);

        var token = data_structures.Token{};
        var columnOffsets = data_structures.Offsets{};
        var lineOffsets = data_structures.Offsets{};

        var current_symbol: u16 = 0;

        var line: u16 = 1;
        var column: u16 = 1;
        var indent_width: u16 = 0;
        var current_indent: u16 = 0;
        var line_spaces: u16 = 0;
        var is_start_of_line: bool = false;

        while (true) {
            var bytes_read = reader.interface.readSliceShort(&buffer) catch |err| switch (err) {
                error.ReadFailed => break,
            };

            if (bytes_read == 0 and buffer[0] != '\x00') {
                bytes_read = 1;
                buffer[0] = '\x00';
            }

            for (buffer[0..bytes_read]) |character| token_process_loop: {
                if (verbosity > 3) {
                    std.debug.print("-- {f} {d} line spaces: {d} {}\n", .{
                        root.string_utilities.fmtString(&[_]u8{character}),
                        character,
                        line_spaces,
                        is_start_of_line,
                    });
                }
                column += 1;
                try token.append(character);

                if (is_start_of_line) {
                    if (character == ' ') {
                        line_spaces += 1;
                        continue;
                    } else {
                        is_start_of_line = false;
                        if (indent_width == 0) {
                            indent_width = line_spaces;
                        } else if (line_spaces % indent_width != 0) {
                            std.log.err("\x1b[35mIndentationError at line {d}:\n\x1b[0mInvalid number of spaces {d} which is not divisible by previousely detected indentation width of \x1b[31m\"{d}\"\x1b[0m.", .{
                                line + 1,
                                line_spaces,
                                indent_width,
                            });

                            return error.InvalidIndentation;
                        }
                        const new_indent = line_spaces / indent_width;
                        try lineOffsets.append(1);
                        if (new_indent == current_indent) {
                            try columnOffsets.append(@intCast(line_spaces + 1));
                            try token.append('\n');
                        } else {
                            if (new_indent > current_indent) {
                                for (0..new_indent - current_indent) |index| {
                                    if (index != 0) {
                                        try lineOffsets.append(0);
                                    }
                                    try columnOffsets.append(@intCast(new_indent * indent_width + 1));
                                    try token.append('\x01');
                                }
                            } else if (new_indent < current_indent) {
                                for (0..current_indent - new_indent) |index| {
                                    if (index != 0) {
                                        try lineOffsets.append(0);
                                    }
                                    try columnOffsets.append(@intCast(new_indent * indent_width + 1));
                                    try token.append('\x02');
                                }
                            }
                            current_indent = new_indent;
                        }
                    }
                }

                if (character == '\n') {
                    line_spaces = 0;
                    is_start_of_line = true;
                    continue;
                }

                try lineOffsets.append(0);
                try columnOffsets.append(1);
                try token.append(character);

                while (true) {
                    if (verbosity > 1) {
                        std.debug.print("\n{d}:{d}:\"{f}\", Current symbol: {{{s}({d})}}, Stack: [ ", .{
                            line,
                            column - token.len,
                            root.string_utilities.fmtString(token.items()),
                            parse_table.symbols[current_symbol],
                            current_symbol,
                        });
                        for (symbol_stack.items, 0..) |symbol, index| {
                            if (index != 0) std.debug.print(", ", .{});
                            std.debug.print("{s}({d})", .{
                                if (symbol <= 0)
                                    parse_table.symbols[@intCast(-symbol)]
                                else
                                    parse_table.symbols[@intCast(symbol)],
                                symbol,
                            });
                        }
                        std.debug.print(" ]\n", .{});
                    }
                    const table = parse_table.parse_table[current_symbol];

                    for (table.keys()) |key| {
                        if (key.len > token.len and std.mem.startsWith(u8, key, token.items())) {
                            break :token_process_loop;
                        }
                    }

                    if (parse_table.is_terminal[@intCast(current_symbol)]) {
                        const text = parse_table.symbols[current_symbol];

                        if (token.len < text.len) {
                            break;
                        }
                        if (std.mem.startsWith(u8, token.items(), text)) {
                            if (std.mem.indexOfScalar(u8, text, '\n')) |index| {
                                line += 1;
                                column = @intCast(token.len - index);
                            }

                            const node = try arena_allocator.create(root.data_structures.ASTNode);
                            node.* = .{
                                .text = try arena_allocator.dupe(u8, token.items()[0..text.len]),
                                .label = try std.fmt.allocPrint(arena_allocator, "text '{s}'", .{
                                    token.items()[0..text.len],
                                }),
                                .variable = 0,
                                .payload = .{},

                                .right_hand_side_children = &[0]*root.data_structures.ASTNode{},
                                .children = &[0]*root.data_structures.ASTNode{},
                            };
                            try semantic_stack.append(gpa, node);

                            try token.pop(text.len);
                        }
                    } else if (table.getLongestPrefix(token.items())) |prefix| {
                        const longest_prefix = prefix.key;
                        if (verbosity > 1) {
                            std.debug.print("Longest prefix: \"{f}\" \"{f}\" {any}\n", .{
                                root.string_utilities.fmtString(longest_prefix),
                                root.string_utilities.fmtString(token.items()),
                                std.mem.eql(u8, longest_prefix, token.items()),
                            });
                        }

                        if (std.mem.eql(u8, longest_prefix, token.items()) and token.items()[0] != '\x00') {
                            break;
                        } else if (longest_prefix.len < token.len or
                            (longest_prefix[0] == 0 and token.items()[0] == 0))
                        {
                            const rule_index = table.get(longest_prefix).?;
                            const rule = parse_table.rules[rule_index];
                            if (verbosity > 1) {
                                std.debug.print("Rule expansion: {f}({d}) -> ", .{
                                    root.string_utilities.fmtString(parse_table.symbols[current_symbol]),
                                    current_symbol,
                                });
                                for (rule.right_hand_side, 0..) |symbol, i| {
                                    if (i != 0) std.debug.print(", ", .{});
                                    std.debug.print("{f}({d})", .{
                                        root.string_utilities.fmtString(parse_table.symbols[@intCast(symbol)]),
                                        symbol,
                                    });
                                }
                                std.debug.print("\n", .{});
                            }
                            try symbol_stack.append(gpa, @intCast(-@as(i32, @intCast(rule_index))));
                            for (rule.right_hand_side, 0..) |_, i| {
                                try symbol_stack.append(
                                    gpa,
                                    @intCast(rule.right_hand_side[rule.right_hand_side.len - i - 1]),
                                );
                            }
                        }
                    } else {
                        std.log.err("\x1b[35mSyntaxError at {d}:{d}:\x1b[0m unexpected token \x1b[31m\"{f}\"\x1b[0m while expecting \x1b[34m{{{s}}}\x1b[0m.", .{
                            line,
                            column - token.len,
                            root.string_utilities.fmtString(token.items()),
                            parse_table.symbols[current_symbol],
                        });

                        return error.SyntaxError;
                    }

                    while (symbol_stack.pop()) |popped_symbol| {
                        if (popped_symbol <= 0) {
                            const rule_index: u16 = @intCast(-popped_symbol);
                            const rule = parse_table.rules[rule_index];
                            if (verbosity > 1) {
                                std.debug.print("Reduction: {s}({d}) <~ ", .{
                                    parse_table.variables[rule.header],
                                    rule.header,
                                });
                                for (rule.right_hand_side, 0..) |idx, i| {
                                    if (i != 0) std.debug.print(", ", .{});
                                    std.debug.print("{f}({d})", .{ root.string_utilities.fmtString(if (idx == -1) "-1" else parse_table.symbols[idx]), idx });
                                }
                                std.debug.print("\n\n", .{});
                            }

                            var grammar_symbols_count: usize = 0;
                            for (rule.right_hand_side) |symbol| {
                                if (parse_table.is_grammar[symbol]) {
                                    grammar_symbols_count += 1;
                                }
                            }

                            const right_hand_side = try arena_allocator.alloc(
                                ?*root.data_structures.ASTNode,
                                grammar_symbols_count,
                            );

                            for (0..grammar_symbols_count) |i| {
                                if (semantic_stack.pop()) |semantic_item| {
                                    right_hand_side[right_hand_side.len - i - 1] = semantic_item orelse null;
                                }
                            }
                            var combined_text = try std.ArrayList(u8).initCapacity(arena_allocator, 256);

                            var semantic_list_size: usize = 0;

                            for (right_hand_side) |semantic_item| {
                                if (semantic_item) |child| {
                                    semantic_list_size += child.augmented_length();
                                    try combined_text.appendSlice(arena_allocator, child.text);
                                }
                            }

                            if (verbosity > 2) {
                                std.debug.print("{s} text:\n {s}\n\n", .{
                                    parse_table.variables[rule.header],
                                    combined_text.items,
                                });
                            }

                            const node = try arena_allocator.create(root.data_structures.ASTNode);
                            node.* = .{
                                .text = combined_text.items,
                                .label = parse_table.variables[rule.header],
                                .variable = rule.header,
                                .payload = .{},

                                .right_hand_side_children = right_hand_side,
                                .children = &[0]*root.data_structures.ASTNode{},
                            };

                            {
                                if (verbosity > 1) {
                                    std.debug.print("\n Semantic reduction: {s} <~ ", .{
                                        parse_table.variables[rule.header],
                                    });
                                }
                                var counter: usize = 0;
                                for (right_hand_side) |semantic_item| {
                                    if (semantic_item) |semantic_item_| {
                                        if (verbosity > 1) {
                                            var iterator = semantic_item_.iterate_augmented();
                                            while (iterator.next()) |augmented_item| {
                                                if (counter != 0) std.debug.print(", ", .{});
                                                std.debug.print("{s}", .{augmented_item.label});
                                            }

                                            counter += 1;
                                        }

                                        try node.*.append_children(
                                            arena_allocator,
                                            semantic_item_.augmented_first(),
                                        );
                                    }
                                }
                                if (verbosity > 1) {
                                    std.debug.print("\n\n", .{});
                                }
                            }

                            var args = data_structures.ProcedureArguments{
                                .allocator = arena_allocator,
                                .io = init.io,
                                .verbosity = verbosity,
                                .rule = rule,
                                .node = node,
                            };

                            if (parse_table.rule_procedures[rule_index]) |procedure_pointer| {
                                const procedure = @as(*data_structures.RuleProcedure, @constCast(procedure_pointer));
                                try procedure(&args);
                            }

                            if (parse_table.variable_procedures[rule.header]) |procedure_pointer| {
                                const procedure = @as(*data_structures.VariableProcedure, @constCast(procedure_pointer));
                                try procedure(&args);
                            }

                            if (parse_table.reduction_procedure) |procedure_pointer| {
                                const procedure = @as(*data_structures.ReductionProcedure, @constCast(procedure_pointer));
                                try procedure(&args);
                            }

                            if (verbosity > 2) {
                                std.debug.print("Procedure outcome for {s}: {f}\n", .{
                                    parse_table.variables[rule.header],
                                    root.string_utilities.fmtASTNode(args.node),
                                });
                            }

                            try semantic_stack.append(gpa, args.node);
                        } else if (parse_table.is_grammar[@intCast(popped_symbol)]) {
                            current_symbol = @intCast(popped_symbol);
                            break;
                        }
                    } else if (token.len == 1 and token.items()[0] == 0) {
                        if (verbosity > 0) {
                            std.log.info("The input file was parsed successfully!", .{});
                        }
                        break :benchmark_loop;
                    } else {
                        std.log.err("\x1b[35mSyntaxError at {d}:{d}:\x1b[0m unexpected token \x1b[31m\"{f}\"\x1b[0m while expecting \x1b[34m{{EOF}}\x1b[0m.", .{
                            line,
                            column - token.len,
                            root.string_utilities.fmtString(token.items()),
                        });

                        return error.SyntaxError;
                    }
                }
            }
        }
    }
}
