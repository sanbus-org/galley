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
const trailers_variable = variableIndex("Trailers");
const name_variable = variableIndex("Name");
const keyword_name_variable = variableIndex("KeywordName");
const expression_variable = variableIndex("Expression");
const expression_statement_variable = variableIndex("ExpressionStatement");

/// Python precedence, loosest first. Conditional and walrus bind looser
/// still: they take the whole sequence before them.
const Precedence = struct {
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

/// Whether a node is a terminal's (built only with AST nodes for terminals).
/// The hooks pair operands and find list wrappers among a node's children, so
/// they step over terminal children.
fn isTerminal(node: *const Node) bool {
    return node.variable == Node.invalid_variable;
}

/// The first child that is not a terminal's, starting at `address`.
fn nextOperand(context: *Context, address: Pointer) Pointer {
    var current = address;
    while (current != invalid and isTerminal(context.node_allocator.at(current))) current = context.node_allocator.at(current).next;
    return current;
}

fn firstOperand(context: *Context, node: *const Node) Pointer {
    return nextOperand(context, node.first_child);
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
    const first = node_allocator.at(firstOperand(context, node));
    if (node.variable == unary_operation_variable) {
        return context.getTextSlice(node.text_start, first.text_start - node.text_start);
    }
    const second = node_allocator.at(nextOperand(context, first.next));
    return context.getTextSlice(end(first), second.text_start - end(first));
}

/// The source text of a node.
fn ownText(context: *Context, node: *const Node) []const u8 {
    return context.getTextSlice(node.text_start, node.text_length);
}

/// Precedence of an operator node on the tree's right spine.
fn spinePrecedence(context: *Context, address: Pointer) u8 {
    const node = context.node_allocator.at(address);
    if (node.variable == unary_operation_variable) return unaryPrecedence(operatorText(context, node));
    return binaryPrecedence(operatorText(context, node));
}

fn setEnd(node: *Node, node_end: usize) void {
    node.text_length = node_end - node.text_start;
}

/// Gives a detached node the detached `operand` as its first child.
fn prependOperand(context: *Context, node: Pointer, operand: Pointer) void {
    const node_allocator = context.node_allocator;
    const start = node_allocator.at(operand).text_start;
    Node.insertChildren(node, node_allocator, 0, operand);
    extendStart(node_allocator.at(node), start);
}

/// Chains the trailers of a nested `Trailers` wrapper onto the detached
/// `operand`: each trailer takes the one before it as its first child.
/// Returns the outermost trailer.
fn applyTrailers(context: *Context, operand: Pointer, trailers: Pointer) Pointer {
    const node_allocator = context.node_allocator;
    var result = operand;
    var level = trailers;
    while (level != invalid) {
        const trailer = firstOperand(context, node_allocator.at(level));
        level = nextOperand(context, node_allocator.at(trailer).next);
        Node.removeSelf(trailer, node_allocator);
        prependOperand(context, trailer, result);
        result = trailer;
    }
    return result;
}

/// Builds the tree of a flat operator sequence left to right. The right
/// spine runs from `tip`, the last operand, up to `root`. An operator climbs
/// that spine past every node that binds at least as tightly and takes the
/// node it stops at as its left operand; a node climbed past leaves the spine
/// for good, so the whole sequence resolves in linear time. The sequence
/// must alternate operands (with prefix operators and trailers) and binary
/// operators, and may end in one Conditional or NamedExpression; the
/// assertions reject any other grammar shape instead of misbuilding it.
const SequenceResolver = struct {
    context: *Context,
    root: Pointer = invalid,
    tip: Pointer = invalid,
    /// The operator node waiting for its next operand.
    open: Pointer = invalid,
    /// The operand waiting for its trailers.
    operand: Pointer = invalid,
    /// `a is not b` arrives as `is` followed by a prefix `not`.
    after_is: bool = false,

    fn attach(self: *SequenceResolver, address: Pointer) void {
        if (self.open == invalid) {
            self.root = address;
        } else {
            Node.appendChildren(self.open, self.context.node_allocator, address);
        }
    }

    /// Whether the sequence is at an operand position: at its start or after
    /// an operator.
    fn expectsOperand(self: *const SequenceResolver) bool {
        return self.operand == invalid and (self.root == invalid or self.open != invalid);
    }

    fn addOperand(self: *SequenceResolver, address: Pointer) void {
        std.debug.assert(self.expectsOperand());
        self.operand = address;
    }

    fn addTrailers(self: *SequenceResolver, trailers: Pointer) void {
        std.debug.assert(self.operand != invalid);
        self.operand = applyTrailers(self.context, self.operand, trailers);
    }

    fn flushOperand(self: *SequenceResolver) void {
        if (self.operand == invalid) return;
        self.attach(self.operand);
        self.tip = self.operand;
        self.open = invalid;
        self.operand = invalid;
        self.after_is = false;
    }

    fn addUnary(self: *SequenceResolver, address: Pointer) void {
        std.debug.assert(self.expectsOperand());
        const precedence = unaryPrecedence(ownText(self.context, self.context.node_allocator.at(address)));
        const belongs_to_is = self.after_is and precedence == Precedence.not;
        self.after_is = false;
        if (belongs_to_is) return;
        self.attach(address);
        self.open = address;
    }

    fn addBinary(self: *SequenceResolver, address: Pointer) void {
        std.debug.assert(self.operand != invalid);
        self.flushOperand();
        const context = self.context;
        const node_allocator = context.node_allocator;
        const operator_node = node_allocator.at(address);
        const operator_text = ownText(context, operator_node);
        const precedence = binaryPrecedence(operator_text);
        const tip_end = end(node_allocator.at(self.tip));

        var operand = self.tip;
        var parent = node_allocator.at(operand).parent;
        while (parent != invalid) : (parent = node_allocator.at(operand).parent) {
            const parent_precedence = spinePrecedence(context, parent);
            const climbs = parent_precedence > precedence or
                (parent_precedence == precedence and precedence != Precedence.power and precedence != Precedence.comparison);
            if (!climbs) break;
            setEnd(node_allocator.at(parent), tip_end);
            operand = parent;
        }
        self.after_is = std.mem.eql(u8, std.mem.trim(u8, operator_text, " "), "is");

        // Comparison chains stay one node: `a < b < c` has three operands. The
        // operator's own terminals, if any, move along between the operands.
        if (precedence == Precedence.comparison and parent != invalid and spinePrecedence(context, parent) == Precedence.comparison) {
            const terminals = Node.cleanChildren(address, node_allocator);
            if (terminals != invalid) Node.appendChildren(parent, node_allocator, terminals);
            self.open = parent;
            return;
        }

        // Operands go around the operator's own terminals, if any.
        if (parent != invalid) Node.removeSelf(operand, node_allocator);
        Node.insertChildren(address, node_allocator, 0, operand);
        operator_node.text_start = node_allocator.at(operand).text_start;
        if (parent == invalid) {
            self.root = address;
        } else {
            Node.appendChildren(parent, node_allocator, address);
        }
        self.open = address;
    }

    /// Gives every node on the right spine the end of the last operand.
    fn finishSpine(self: *SequenceResolver) void {
        const node_allocator = self.context.node_allocator;
        const tip_end = end(node_allocator.at(self.tip));
        var address = node_allocator.at(self.tip).parent;
        while (address != invalid) : (address = node_allocator.at(address).parent) {
            setEnd(node_allocator.at(address), tip_end);
        }
    }

    /// Conditional and NamedExpression bind loosest of all, so they take the
    /// whole sequence before them as their first operand.
    fn addSuffix(self: *SequenceResolver, address: Pointer) void {
        std.debug.assert(self.operand != invalid);
        self.flushOperand();
        self.finishSpine();
        prependOperand(self.context, address, self.root);
        self.root = address;
        self.tip = address;
    }

    fn finish(self: *SequenceResolver) Pointer {
        std.debug.assert(!self.expectsOperand());
        self.flushOperand();
        self.finishSpine();
        return self.root;
    }
};

/// Nests the sequence of an `Expression` or `Disjunction`. Its continuations
/// are flattened into it, so the whole sequence arrives as its children.
pub fn hook_resolveExpression(args: *ProcedureArguments) !void {
    if (comptime !galley.parser.is_ast_enabled) return;
    const node_address = args.node_address orelse return;
    const context = args.context;
    const node_allocator = context.node_allocator;
    if (node_allocator.at(node_address).children_count <= 1) return;

    var resolver = SequenceResolver{ .context = context };
    var child = node_allocator.at(node_address).first_child;
    while (child != invalid) {
        const next = node_allocator.at(child).next;
        Node.removeSelf(child, node_allocator);
        const variable = node_allocator.at(child).variable;
        if (variable == binary_operation_variable) {
            resolver.addBinary(child);
        } else if (variable == unary_operation_variable) {
            resolver.addUnary(child);
        } else if (variable == trailers_variable) {
            resolver.addTrailers(child);
        } else if (variable == conditional_variable or variable == named_expression_variable) {
            resolver.addSuffix(child);
        } else {
            resolver.addOperand(child);
        }
        child = next;
    }
    Node.appendChildren(node_address, node_allocator, resolver.finish());
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
    const head = firstOperand(context, node);
    if (head == invalid or node_allocator.at(head).variable != keyword_name_variable) return;
    // The keyword's terminals are the start of the name.
    while (node.first_child != head) Node.removeSelf(node.first_child, node_allocator);

    node.variable = expression_statement_variable;
    node_allocator.at(head).variable = name_variable;
    Node.removeSelf(head, node_allocator);
    var operand = head;
    const trailers = node.first_child;
    if (trailers != invalid and node_allocator.at(trailers).variable == trailers_variable) {
        Node.removeSelf(trailers, node_allocator);
        operand = applyTrailers(context, head, trailers);
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

/// A list wrapper is the last child of its owner and of the wrapper above it,
/// apart from trailing terminals, so lifting that wrapper repeatedly flattens
/// the list.
pub fn hook_flattenLists(args: *ProcedureArguments) !void {
    if (comptime !galley.parser.is_ast_enabled) return;
    const node_address = args.node_address orelse return;
    const node_allocator = args.context.node_allocator;
    while (true) {
        var wrapper = node_allocator.at(node_address).last_child;
        while (wrapper != invalid and isTerminal(node_allocator.at(wrapper))) wrapper = node_allocator.at(wrapper).prior;
        if (wrapper == invalid or !isListWrapper(node_allocator.at(wrapper).variable)) return;
        const children = Node.cleanChildren(wrapper, node_allocator);
        if (children != invalid) Node.insertBefore(wrapper, node_allocator, children);
        Node.removeSelf(wrapper, node_allocator);
    }
}
