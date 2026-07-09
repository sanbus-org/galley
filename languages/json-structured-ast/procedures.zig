const std = @import("std");
const data_structures = @import("galley").data_structures;
const ProcedureArguments = data_structures.ProcedureArguments;
const string_utilities = @import("galley").string_utilities;
const standard_procedures = @import("galley").standard_procedures;

pub const indentation_syntax = false;
pub const Payload = struct {
    objects: u32 = 0,
    arrays: u32 = 0,
    nulls: u32 = 0,
};

pub fn reduction(args: *ProcedureArguments) !void {
    if (args.node) |node_address| {
        var node = args.context.node_allocator.at(node_address);
        var iterator = data_structures.ASTNode.iterateAugmented(node.first_child, args.context.node_allocator);
        while (iterator.next()) |child_address| {
            const child = args.context.node_allocator.at(child_address);
            node.payload.objects += child.payload.objects;
            node.payload.arrays += child.payload.arrays;
            node.payload.nulls += child.payload.nulls;
        }
    }
}

pub fn reduction_Object(args: *ProcedureArguments) !void {
    if (args.node) |node_address| {
        var node = args.context.node_allocator.at(node_address);
        node.payload.objects += 1;
    }
}

pub fn reduction_Array(args: *ProcedureArguments) !void {
    if (args.node) |node_address| {
        var node = args.context.node_allocator.at(node_address);
        node.payload.arrays += 1;
    }
}

pub fn reduction_null(args: *ProcedureArguments) !void {
    if (args.node) |node_address| {
        var node = args.context.node_allocator.at(node_address);
        node.payload.nulls += 1;
    }
}

pub const dropSelf = standard_procedures.dropSelf;
pub const dropChildren = standard_procedures.dropChildren;
pub const replaceWithChildren = standard_procedures.replaceWithChildren;

pub fn reduction_Start(args: *ProcedureArguments) !void {
    if (if (args.context.verbosityLevel() > 0) args.node else null) |node_address| {
        std.debug.print("\nProgram text:\n{s}\n", .{try data_structures.ASTNode.augmentedText(node_address, args.context)});

        const log_file = try std.Io.Dir.cwd().createFile(args.context.runtime().io, "sanbus-parse.log", .{
            .lock = .exclusive,
        });
        defer log_file.close(args.context.runtime().io);

        var buffer: [4096]u8 = undefined;
        var buffered_writer: std.Io.File.Writer = .init(log_file, args.context.runtime().io, &buffer);
        const writer = &buffered_writer.interface;

        const node = args.context.node_allocator.at(node_address);
        const child = args.context.node_allocator.at(node.first_child);
        try writer.print("{d} objects, {d} arrays, {d} nulls!\n\n{f}\n", .{
            child.payload.objects,
            child.payload.arrays,
            child.payload.nulls,
            string_utilities.fmtASTNode(node_address, args.context),
        });

        try writer.flush();
    }
}
