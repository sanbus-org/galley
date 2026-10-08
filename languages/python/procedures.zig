const std = @import("std");
const galley = @import("galley");

const ProcedureArguments = galley.data_structures.ProcedureArguments;
const Context = galley.data_structures.Context;
const Node = galley.data_structures.Node;
const Pointer = Node.Pointer;
const invalid = Node.invalid_pointer;

pub const Payload = struct {};

pub const hook_replaceWithChildren = galley.standard_procedures.replaceWithChildren;
pub const hook_rightRecursiveReduction = galley.standard_procedures.rightRecursiveReduction;

fn variableIndex(comptime variable_name: []const u8) u16 {
    @setEvalBranchQuota(1_000_000);
    for (galley.parser.variables, 0..) |variable, index| {
        if (std.mem.eql(u8, variable, variable_name)) return @intCast(index);
    }
    @compileError("unknown grammar variable " ++ variable_name);
}

const binary_operation_variable = variableIndex("BinaryOperation");
const unary_operation_variable = variableIndex("UnaryOperation");
const conditional_variable = variableIndex("Conditional");
const named_expression_variable = variableIndex("NamedExpression");
const call_variable = variableIndex("Call");
const subscript_variable = variableIndex("Subscript");
const attribute_variable = variableIndex("Attribute");
const name_variable = variableIndex("Name");
const keyword_name_variable = variableIndex("KeywordName");
const expression_variable = variableIndex("Expression");
const expression_statement_variable = variableIndex("ExpressionStatement");

fn isTrailer(variable: u16) bool {
    return variable == call_variable or variable == subscript_variable or variable == attribute_variable;
}

/// Python precedence, loosest first. Conditional and walrus nodes are the
/// loosest of all, so every operator reaches inside them.
const Precedence = struct {
    const lowest: u8 = 0;
    const @"or": u8 = 2;
    const @"and": u8 = 3;
    const not: u8 = 4;
    const comparison: u8 = 5;
    const bitwise_or: u8 = 6;
    const bitwise_xor: u8 = 7;
    const bitwise_and: u8 = 8;
    const shift: u8 = 9;
    const additive: u8 = 10;
    const multiplicative: u8 = 11;
    const unary: u8 = 12;
    const power: u8 = 13;
    const await: u8 = 14;
};

fn binaryPrecedence(operator_text: []const u8) u8 {
    const operator = std.mem.trim(u8, operator_text, " ");
    const second: u8 = if (operator.len > 1) operator[1] else 0;
    return switch (operator[0]) {
        'o' => Precedence.@"or",
        'a' => Precedence.@"and",
        'n', 'i', '=', '!' => Precedence.comparison,
        '<' => if (second == '<') Precedence.shift else Precedence.comparison,
        '>' => if (second == '>') Precedence.shift else Precedence.comparison,
        '|' => Precedence.bitwise_or,
        '^' => Precedence.bitwise_xor,
        '&' => Precedence.bitwise_and,
        '+', '-' => Precedence.additive,
        '*' => if (second == '*') Precedence.power else Precedence.multiplicative,
        else => Precedence.multiplicative,
    };
}

fn unaryPrecedence(operator_text: []const u8) u8 {
    const operator = std.mem.trim(u8, operator_text, " ");
    if (std.mem.eql(u8, operator, "not")) return Precedence.not;
    if (std.mem.eql(u8, operator, "await")) return Precedence.await;
    return Precedence.unary;
}

fn end(node: *const Node) usize {
    return node.text_start + node.text_length;
}

fn extendStart(node: *Node, start: usize) void {
    const node_end = end(node);
    node.text_start = start;
    node.text_length = node_end - start;
}

/// The operator of a resolved operation node: the source between its
/// operand children (or before its operand, for a unary operation).
fn operatorText(context: *Context, node: *const Node) []const u8 {
    const node_allocator = context.node_allocator;
    const first = node_allocator.at(node.first_child);
    if (node.variable == unary_operation_variable) {
        return context.getTextSlice(node.text_start, first.text_start - node.text_start);
    }
    const second = node_allocator.at(first.next);
    return context.getTextSlice(end(first), second.text_start - end(first));
}

/// Precedence of a resolved node as seen from an operator to its left, or
/// null when the node is an operand that operators cannot reach into.
fn resolvedPrecedence(context: *Context, address: Pointer) ?u8 {
    const node = context.node_allocator.at(address);
    if (node.first_child == invalid) return null;
    if (node.variable == conditional_variable or node.variable == named_expression_variable) return Precedence.lowest;
    if (node.variable == binary_operation_variable) return binaryPrecedence(operatorText(context, node));
    return null;
}

fn isUnaryNot(context: *Context, address: Pointer) bool {
    const node = context.node_allocator.at(address);
    if (node.variable != unary_operation_variable or node.first_child == invalid) return false;
    return unaryPrecedence(operatorText(context, node)) == Precedence.not;
}

/// Gives every node on the left spine from `root` down to `target` the start
/// of the operand that was just inserted at the bottom of that spine.
fn extendSpine(context: *Context, root: Pointer, target: Pointer, start: usize) void {
    const node_allocator = context.node_allocator;
    var address = root;
    while (true) {
        extendStart(node_allocator.at(address), start);
        if (address == target) return;
        address = node_allocator.at(address).first_child;
    }
}

/// Replaces `old` by the detached `new` at `old`'s position, or returns `new`
/// as the root when `old` had no parent.
fn replaceNode(context: *Context, old: Pointer, new: Pointer, root: Pointer) Pointer {
    const node_allocator = context.node_allocator;
    if (node_allocator.at(old).parent == invalid) return new;
    Node.insertBefore(old, node_allocator, new);
    Node.removeSelf(old, node_allocator);
    return root;
}

/// Combines `left`, the unresolved `operator` node and the resolved tree
/// `right`, returning the new root.
fn insertBinary(context: *Context, left: Pointer, operator: Pointer, right: Pointer) Pointer {
    const node_allocator = context.node_allocator;
    const operator_node = node_allocator.at(operator);
    const operator_text = context.getTextSlice(operator_node.text_start, operator_node.text_length);
    const precedence = binaryPrecedence(operator_text);
    const left_start = node_allocator.at(left).text_start;

    var root = right;
    var position = right;
    while (resolvedPrecedence(context, position)) |position_precedence| {
        const descends = position_precedence < precedence or
            (position_precedence == precedence and precedence != Precedence.power and precedence != Precedence.comparison);
        if (!descends) break;
        position = node_allocator.at(position).first_child;
    }

    // `a is not b` arrives as `is` applied to `not b`.
    if (std.mem.eql(u8, std.mem.trim(u8, operator_text, " "), "is") and isUnaryNot(context, position)) {
        const operand = node_allocator.at(position).first_child;
        Node.removeSelf(operand, node_allocator);
        root = replaceNode(context, position, operand, root);
        position = operand;
    }

    // Comparison chains stay one node: `a < b < c` has three operands.
    if (precedence == Precedence.comparison and resolvedPrecedence(context, position) == Precedence.comparison) {
        Node.insertChildren(position, node_allocator, 0, left);
        extendSpine(context, root, position, left_start);
        return root;
    }

    const position_parent = node_allocator.at(position).parent;
    if (position_parent != invalid) Node.removeSelf(position, node_allocator);
    Node.appendChildren(operator, node_allocator, left);
    Node.appendChildren(operator, node_allocator, position);
    operator_node.text_start = left_start;
    operator_node.text_length = end(node_allocator.at(position)) - left_start;
    if (position_parent == invalid) return operator;
    Node.insertChildren(position_parent, node_allocator, 0, operator);
    extendSpine(context, root, operator, left_start);
    return root;
}

/// Applies the unresolved prefix `operator` to the resolved tree `right`,
/// returning the new root.
fn insertUnary(context: *Context, operator: Pointer, right: Pointer) Pointer {
    const node_allocator = context.node_allocator;
    const operator_node = node_allocator.at(operator);
    const precedence = unaryPrecedence(context.getTextSlice(operator_node.text_start, operator_node.text_length));
    const operator_start = operator_node.text_start;

    var position = right;
    while (resolvedPrecedence(context, position)) |position_precedence| {
        if (position_precedence >= precedence) break;
        position = node_allocator.at(position).first_child;
    }

    const position_parent = node_allocator.at(position).parent;
    if (position_parent != invalid) Node.removeSelf(position, node_allocator);
    Node.appendChildren(operator, node_allocator, position);
    operator_node.text_length = end(node_allocator.at(position)) - operator_start;
    if (position_parent == invalid) return operator;
    Node.insertChildren(position_parent, node_allocator, 0, operator);
    extendSpine(context, right, operator, operator_start);
    return right;
}

/// Gives a detached node the detached `operand` as its first child.
fn prependOperand(context: *Context, node: Pointer, operand: Pointer) void {
    const node_allocator = context.node_allocator;
    const start = node_allocator.at(operand).text_start;
    Node.insertChildren(node, node_allocator, 0, operand);
    extendStart(node_allocator.at(node), start);
}

fn takeResolvedTree(context: *Context, sequence: Pointer) Pointer {
    const tree = context.node_allocator.at(sequence).first_child;
    Node.removeSelf(tree, context.node_allocator);
    return tree;
}

/// Nests the flat sequence an `Expression` or `Disjunction` reduces to. The
/// recursive sequence on the right has already been resolved into one tree.
pub fn hook_resolveExpression(args: *ProcedureArguments) !void {
    if (comptime !galley.parser.is_ast_enabled) return;
    const node_address = args.node_address orelse return;
    const context = args.context;
    const node_allocator = context.node_allocator;
    const node = node_allocator.at(node_address);
    if (node.children_count <= 1) return;

    var items: [64]Pointer = undefined;
    if (node.children_count > items.len) return;
    var count: usize = 0;
    while (node.first_child != invalid) : (count += 1) {
        items[count] = node.first_child;
        Node.removeSelf(items[count], node_allocator);
    }

    var root: Pointer = undefined;
    if (node_allocator.at(items[0]).variable == unary_operation_variable) {
        root = insertUnary(context, items[0], takeResolvedTree(context, items[1]));
    } else {
        var operand = items[0];
        var index: usize = 1;
        while (index < count) : (index += 1) {
            if (!isTrailer(node_allocator.at(items[index]).variable)) break;
            prependOperand(context, items[index], operand);
            operand = items[index];
        }
        root = operand;
        if (index < count) {
            const continuation = items[index];
            const variable = node_allocator.at(continuation).variable;
            if (variable == binary_operation_variable) {
                root = insertBinary(context, operand, continuation, takeResolvedTree(context, items[index + 1]));
            } else {
                prependOperand(context, continuation, operand);
                root = continuation;
            }
        }
    }
    Node.appendChildren(node_address, node_allocator, root);
}

fn isIdentifierByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

/// A KeywordName starts after the keyword it shares its first letters with
/// ("return" in "return_value"); move its start back over those letters.
pub fn hook_extendIdentifierStart(args: *ProcedureArguments) !void {
    const node = args.currentNode() orelse return;
    var start = node.text_start;
    while (start > 0 and isIdentifierByte(args.context.getTextSlice(start - 1, 1)[0])) start -= 1;
    extendStart(node, start);
}

/// A keyword statement whose keyword turned out to begin an identifier
/// ("passed = 1") is an ExpressionStatement: its KeywordName becomes a Name
/// and, with the trailers that follow it, the statement's first Expression.
pub fn hook_identifierStatement(args: *ProcedureArguments) !void {
    if (comptime !galley.parser.is_ast_enabled) return;
    const node_address = args.node_address orelse return;
    const context = args.context;
    const node_allocator = context.node_allocator;
    const node = node_allocator.at(node_address);
    const head = node.first_child;
    if (head == invalid or node_allocator.at(head).variable != keyword_name_variable) return;

    node.variable = expression_statement_variable;
    node_allocator.at(head).variable = name_variable;
    Node.removeSelf(head, node_allocator);
    var operand = head;
    while (node.first_child != invalid and isTrailer(node_allocator.at(node.first_child).variable)) {
        const trailer = node.first_child;
        Node.removeSelf(trailer, node_allocator);
        prependOperand(context, trailer, operand);
        operand = trailer;
    }
    const operand_node = node_allocator.at(operand);
    const wrapper = try node_allocator.create(operand_node.text_start, expression_variable);
    node_allocator.at(wrapper).text_length = operand_node.text_length;
    Node.appendChildren(wrapper, node_allocator, operand);
    Node.insertChildren(node_address, node_allocator, 0, wrapper);
}

/// Recursive list rules nest one wrapper node per element (`Statements`
/// holds an element and the next `Statements`). Splicing each level into its
/// parent as it reduces re-parents the whole tail every time, which is
/// quadratic, so the wrappers stay nested and the node that owns the list
/// lifts them once here: each element moves exactly once.
const list_wrapper_variables = [_]u16{
    variableIndex("Statements"),           variableIndex("ForTargets"),
    variableIndex("WithItems"),            variableIndex("ImportNames"),
    variableIndex("FromNames"),            variableIndex("ParenthesizedFromNames"),
    variableIndex("Parameters"),           variableIndex("LambdaParameters"),
    variableIndex("Assignments"),          variableIndex("TargetList"),
    variableIndex("ExpressionList"),       variableIndex("ParenthesizedItems"),
    variableIndex("ListItems"),            variableIndex("BraceItems"),
    variableIndex("ComprehensionTargets"), variableIndex("ComprehensionTail"),
    variableIndex("CallArguments"),        variableIndex("SubscriptItems"),
};

fn isListWrapper(variable: u16) bool {
    return std.mem.indexOfScalar(u16, &list_wrapper_variables, variable) != null;
}

/// A list wrapper is always the last child of its owner and of the wrapper
/// above it, so lifting the trailing wrapper repeatedly flattens the list.
pub fn hook_flattenLists(args: *ProcedureArguments) !void {
    if (comptime !galley.parser.is_ast_enabled) return;
    const node_address = args.node_address orelse return;
    const node_allocator = args.context.node_allocator;
    while (true) {
        const wrapper = node_allocator.at(node_address).last_child;
        if (wrapper == invalid or !isListWrapper(node_allocator.at(wrapper).variable)) return;
        Node.removeSelf(wrapper, node_allocator);
        const children = Node.cleanChildren(wrapper, node_allocator);
        if (children != invalid) Node.appendChildren(node_address, node_allocator, children);
    }
}
