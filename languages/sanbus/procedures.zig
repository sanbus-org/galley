const std = @import("std");
const ProcedureArguments = @import("galley").data_structures.ProcedureArguments;
const ASTNode = @import("galley").data_structures.ASTNode;
const string_utilities = @import("galley").string_utilities;
const parser = @import("galley").parser;
const standard_procedures = @import("galley").standard_procedures;

const control_characters_uppper_bound = 4;

pub const Payload = struct {
    rules: usize = 0,
    fields: usize = 0,
    outcomes: usize = 0,
    indent: usize = 0,
    parse_id: usize = 0,
};

var indent: u16 = 0;

const block_start_id = 1;
const block_end_id = 2;

pub fn reduction(args: *ProcedureArguments) !void {
    if (args.node) |node_address| {
        var node = args.context.node_allocator.at(node_address);
        var block_start: ?ASTNode.Pointer = null;
        while (if (node.first_child != ASTNode.invalid_pointer and
            args.context.node_allocator.at(node.first_child).payload.parse_id == block_start_id)
            node.first_child
        else
            null) |child_address|
        {
            // We need last BlockStart which is the last when iterating from
            // start of the array and has most indentation
            block_start = try ASTNode.removeSelf(child_address, args.context.node_allocator);
        }
        if (block_start) |to_prepend| {
            try ASTNode.insertBefore(node_address, args.context.node_allocator, to_prepend);
        }

        var block_end: ?ASTNode.Pointer = null;
        while (if (node.last_child != ASTNode.invalid_pointer and
            args.context.node_allocator.at(node.last_child).payload.parse_id == block_end_id)
            node.last_child
        else
            null) |child_address|
        {
            const new_block_end = try ASTNode.removeSelf(child_address, args.context.node_allocator);
            // We need last BlockEnd which is the first when iterating from
            // the end of the array and has least indenation
            if (block_end == null) {
                block_end = new_block_end;
            }
        }
        if (block_end) |to_append| {
            try ASTNode.insertAfter(node_address, args.context.node_allocator, to_append);
        }

        var iterator = ASTNode.iterateAugmented(node.first_child, args.context.node_allocator);
        while (iterator.next()) |child_address| {
            const child = args.context.node_allocator.at(child_address);
            node.payload.rules += child.payload.rules;
            node.payload.fields += child.payload.fields;
            node.payload.outcomes += child.payload.outcomes;
        }
    }
}

fn summerize(args: *ProcedureArguments) !void {
    if (args.node) |node_address| {
        _ = try ASTNode.cleanChildren(node_address, args.context.node_allocator);
        // node.label = try std.fmt.allocPrint(args.allocator, "{s} ('{s}')", .{
        //     node.label,
        //     node.text,
        // });
    }
}

pub const reduction_UppercaseId = summerize;
pub const reduction_LowercaseId = summerize;
pub const reduction_Id = summerize;
pub const reduction_Operator = summerize;
pub const reduction_String = summerize;

pub const dropSelf = standard_procedures.dropSelf;

pub const reduction_OptionalTypeArray_1 = dropSelf;
pub const reduction_OptionalBlank = dropSelf;

pub const dropChildren = standard_procedures.dropChildren;
pub const dropIfEmpty = standard_procedures.dropIfEmpty;
pub const rightRecursiveReduction = standard_procedures.rightRecursiveReduction;
pub const leftRecursiveReduction = standard_procedures.leftRecursiveReduction;

pub const reduction_OptionalBlankAndNewLine = dropChildren;
pub const reduction_OptionalNewLineMany = dropChildren;
pub const reduction_ForceNewLineMany = dropChildren;
pub const reduction_new_line = dropChildren;

pub const reduction_PositiveIntegerNumber = dropChildren;
pub const reduction_NegativeIntegerNumber = dropChildren;
pub const reduction_IntegerNumber = dropChildren;
pub const reduction_Number = dropChildren;
pub const reduction_text = dropChildren;

fn blockEdge(parse_id: comptime_int) type {
    return struct {
        fn function(args: *ProcedureArguments) !void {
            if (args.node) |node_address| {
                const node = args.context.node_allocator.at(node_address);
                if (parse_id == block_start_id) indent += 1 else indent -= 1;

                // const spaces = try args.allocator.alloc(u8, indent * 2 + 1);
                // @memset(spaces, ' ');
                // spaces[0] = '\n';
                // args.node.?.text = spaces;
                // args.node.?.label = if (parse_id == block_start_id) "BlockStart" else "BlockEnd";

                node.payload.parse_id = parse_id;
            }
        }
    };
}

pub const reduction_block_start = blockEdge(block_start_id).function;
pub const reduction_block_end = blockEdge(block_end_id).function;

pub const replaceWithChildren = standard_procedures.replaceWithChildren;

pub const reduction_Operand = replaceWithChildren;
pub const reduction_Expression_1 = replaceWithChildren;
pub const reduction_OperandAndNumber = replaceWithChildren;
pub const reduction_ActionBody = replaceWithChildren;

pub fn reduction_ActionOutcomeEntry(args: *ProcedureArguments) !void {
    if (args.node) |node_address| {
        const removed_address = try ASTNode.removeChild(node_address, args.context.node_allocator, 0);
        args.context.node_allocator.at(removed_address).payload.outcomes = 1;
        args.node = removed_address;
    }
}

pub fn reduction_FieldRow(args: *ProcedureArguments) void {
    if (args.node) |node_address| {
        const node = args.context.node_allocator.at(node_address);
        node.payload.fields = 1;
    }
}

pub const reduction_RulesTail_0 = rightRecursiveReduction;
pub const reduction_Fields_0 = rightRecursiveReduction;
pub const reduction_ActionOutcome_0 = rightRecursiveReduction;
pub const reduction_ActionsToDispatch_0 = rightRecursiveReduction;
pub const reduction_SideEffectsToDispatch_0 = rightRecursiveReduction;
pub const reduction_InstantiationParameters_0 = rightRecursiveReduction;
pub const reduction_Parameters_0 = rightRecursiveReduction;

pub fn reduction_Rule(args: *ProcedureArguments) !void {
    if (args.node) |node_address| {
        const node = args.context.node_allocator.at(node_address);
        if (args.context.verbosityLevel() > 0) {
            std.debug.print("{f}({d}) -> |", .{
                string_utilities.fmtString(
                    if (args.rule.?.header == -1)
                        "-1"
                    else
                        parser.variables[args.rule.?.header],
                ),
                args.rule.?.header,
            });
            for (args.rule.?.right_hand_side) |idx| {
                std.debug.print("{f}({d})|", .{
                    string_utilities.fmtString(if (idx == -1)
                        "-1"
                    else
                        parser.symbols[idx]),
                    idx,
                });
            }
            std.debug.print("\n", .{});
        }

        // args.node.?.label = try std.fmt.allocPrint(args.allocator, "{s} '{s}'", .{
        //     args.node.?.label,
        //     args.node.?.children[0].text,
        // });

        node.payload.rules = 1;
    }
}

pub fn reduction_Start(args: *ProcedureArguments) !void {
    if (if (args.context.verbosityLevel() > 0) args.node else null) |node_address| {
        std.debug.print("\nProgram text:\n{s}\n", .{try ASTNode.augmentedText(node_address, args.context)});
    }

    const log_file = try std.Io.Dir.cwd().createFile(args.context.runtime().io, "sanbus-parse.log", .{
        .lock = .exclusive,
    });
    defer log_file.close(args.context.runtime().io);

    var buffer: [4096]u8 = undefined;
    var buffered_writer: std.Io.File.Writer = .init(log_file, args.context.runtime().io, &buffer);
    const writer = &buffered_writer.interface;

    if (args.node) |node_address| {
        const node = args.context.node_allocator.at(node_address);
        const child = args.context.node_allocator.at(node.first_child);
        try writer.print("{d} rules, {d} fields, {d} outcomes!\n\n{f}\n", .{
            child.payload.rules,
            child.payload.fields,
            child.payload.outcomes,
            string_utilities.fmtASTNode(node_address, args.context),
        });
    }

    try writer.flush();
}
