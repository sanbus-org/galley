//! Python expression trees: `resolveExpression` nests each flat operator
//! sequence once, at its outermost node, with Python's precedence and
//! associativity. Runs against every matrix build of the Python grammar.

const std = @import("std");
const parser = @import("parser-under-test");

const Node = parser.data_structures.Node;
const invalid = Node.invalid_pointer;

const builds_trees = parser.parser.is_ast_enabled and parser.parser.are_procedures_enabled;

const Tree = struct {
    parsed: parser.ParsedInput,
    input: []const u8,

    fn parse(input: []const u8) !Tree {
        var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
        errdefer parsed.deinit();
        try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);
        return .{ .parsed = parsed, .input = input };
    }

    fn deinit(self: *Tree) void {
        self.parsed.deinit();
    }

    fn at(self: *Tree, address: Node.Pointer) *Node {
        return self.parsed.session.node_allocator.at(address);
    }

    fn name(self: *Tree, address: Node.Pointer) []const u8 {
        const variable = self.at(address).variable;
        if (variable == Node.invalid_variable) return "";
        return parser.parser.variables[variable];
    }

    fn text(self: *Tree, start: usize, stop: usize) []const u8 {
        return self.input[start..stop];
    }

    fn end(self: *Tree, address: Node.Pointer) usize {
        const node = self.at(address);
        return node.text_start + node.text_length;
    }

    fn isTerminal(self: *Tree, address: Node.Pointer) bool {
        return self.at(address).variable == Node.invalid_variable;
    }

    /// The first child that is not a terminal's, starting at `address`.
    fn operandFrom(self: *Tree, address: Node.Pointer) Node.Pointer {
        var current = address;
        while (current != invalid and self.isTerminal(current)) current = self.at(current).next;
        return current;
    }

    fn firstOperand(self: *Tree, address: Node.Pointer) Node.Pointer {
        return self.operandFrom(self.at(address).first_child);
    }

    fn nextOperand(self: *Tree, address: Node.Pointer) Node.Pointer {
        return self.operandFrom(self.at(address).next);
    }

    fn lastOperand(self: *Tree, address: Node.Pointer) Node.Pointer {
        var last = invalid;
        var operand = self.firstOperand(address);
        while (operand != invalid) : (operand = self.nextOperand(operand)) last = operand;
        return last;
    }

    /// The first node named `variable_name`, in depth-first order.
    fn find(self: *Tree, variable_name: []const u8) !Node.Pointer {
        var stack: std.ArrayList(Node.Pointer) = .empty;
        defer stack.deinit(std.testing.allocator);
        try stack.append(std.testing.allocator, self.parsed.result.ast_root orelse return error.MissingAstRoot);
        while (stack.pop()) |address| {
            if (std.mem.eql(u8, self.name(address), variable_name)) return address;
            var child = self.at(address).last_child;
            while (child != invalid) : (child = self.at(child).prior) try stack.append(std.testing.allocator, child);
        }
        return error.MissingNode;
    }

    /// The resolved expression of the first `<variable_name>`'s first operand.
    fn expression(self: *Tree, variable_name: []const u8) !Node.Pointer {
        const expression_node = self.firstOperand(try self.find(variable_name));
        try std.testing.expectEqualStrings("Expression", self.name(expression_node));
        return self.firstOperand(expression_node);
    }

    /// Writes `address` as an S-expression: operators infix between their
    /// operands, `(op operand)` for prefix operators, `(Variable operands)`
    /// for trailers and other inner nodes, and source text for leaves.
    fn render(self: *Tree, writer: *std.Io.Writer, address: Node.Pointer) !void {
        const node_name = self.name(address);
        const first = self.firstOperand(address);
        if (first == invalid) return writer.writeAll(self.text(self.at(address).text_start, self.end(address)));
        if (isWrapper(node_name)) return self.render(writer, first);

        try writer.writeAll("(");
        if (std.mem.eql(u8, node_name, "UnaryOperation")) {
            try writeCollapsed(writer, self.text(self.at(address).text_start, self.at(first).text_start));
            try writer.writeAll(" ");
            try self.render(writer, first);
        } else if (isInfix(node_name)) {
            try self.render(writer, first);
            var previous = first;
            var operand = self.nextOperand(first);
            while (operand != invalid) : (operand = self.nextOperand(operand)) {
                try writer.writeAll(" ");
                try writeCollapsed(writer, self.text(self.end(previous), self.at(operand).text_start));
                try writer.writeAll(" ");
                try self.render(writer, operand);
                previous = operand;
            }
        } else {
            try writer.writeAll(node_name);
            var operand = first;
            while (operand != invalid) : (operand = self.nextOperand(operand)) {
                try writer.writeAll(" ");
                try self.render(writer, operand);
            }
        }
        try writer.writeAll(")");
    }

    /// Every node lies inside its parent, and an infix node spans exactly
    /// from its first operand to its last.
    fn expectSpans(self: *Tree) !void {
        var stack: std.ArrayList(Node.Pointer) = .empty;
        defer stack.deinit(std.testing.allocator);
        try stack.append(std.testing.allocator, self.parsed.result.ast_root orelse return error.MissingAstRoot);
        while (stack.pop()) |address| {
            const node = self.at(address);
            if (isInfix(self.name(address))) {
                try std.testing.expectEqual(self.at(self.firstOperand(address)).text_start, node.text_start);
                try std.testing.expectEqual(self.end(self.lastOperand(address)), self.end(address));
            }
            var child = node.first_child;
            while (child != invalid) : (child = self.at(child).next) {
                try std.testing.expect(self.at(child).text_start >= node.text_start);
                try std.testing.expect(self.end(child) <= self.end(address));
                try stack.append(std.testing.allocator, child);
            }
        }
    }
};

fn isWrapper(node_name: []const u8) bool {
    return std.mem.eql(u8, node_name, "Expression") or std.mem.eql(u8, node_name, "Disjunction");
}

fn isInfix(node_name: []const u8) bool {
    return std.mem.eql(u8, node_name, "BinaryOperation") or
        std.mem.eql(u8, node_name, "Conditional") or
        std.mem.eql(u8, node_name, "NamedExpression");
}

/// Writes operator source with surrounding blanks trimmed and inner runs
/// of blanks collapsed to one space (`is  not` becomes `is not`).
fn writeCollapsed(writer: *std.Io.Writer, source: []const u8) !void {
    var words = std.mem.tokenizeScalar(u8, source, ' ');
    var first = true;
    while (words.next()) |word| {
        if (!first) try writer.writeAll(" ");
        try writer.writeAll(word);
        first = false;
    }
}

fn expectRendered(tree: *Tree, address: Node.Pointer, expected: []const u8) !void {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try tree.render(&output.writer, address);
    try std.testing.expectEqualStrings(expected, output.written());
}

/// Parses `x = <source>` and compares the assigned value's tree.
fn expectValue(comptime source: []const u8, expected: []const u8) !void {
    var tree = try Tree.parse("x = " ++ source ++ "\n");
    defer tree.deinit();
    try tree.expectSpans();
    try expectRendered(&tree, try tree.expression("AssignedValue"), expected);
}

test "python binary operators follow precedence and associativity" {
    if (comptime !builds_trees) return error.SkipZigTest;
    try expectValue("a + b * c - d / e % f // g @ h", "((a + (b * c)) - ((((d / e) % f) // g) @ h))");
    try expectValue("a ** b ** c", "(a ** (b ** c))");
    try expectValue("a ** b * c ** d", "((a ** b) * (c ** d))");
    try expectValue("a * b ** c * d", "((a * (b ** c)) * d)");
    try expectValue("a | b ^ c & d << e >> f", "(a | (b ^ (c & ((d << e) >> f))))");
    try expectValue("a + b < c * d and e or f", "((((a + b) < (c * d)) and e) or f)");
    try expectValue("a and b < c or d", "((a and (b < c)) or d)");
}

test "python comparison chains stay one node" {
    if (comptime !builds_trees) return error.SkipZigTest;
    try expectValue("a < b <= c == d != e > f >= g", "(a < b <= c == d != e > f >= g)");
    try expectValue("a is not b is c", "(a is not b is c)");
    try expectValue("a not in b in c", "(a not in b in c)");
    try expectValue("a in b < c", "(a in b < c)");
    try expectValue("a == b == c", "(a == b == c)");
}

test "python prefix operators bind by their own precedence" {
    if (comptime !builds_trees) return error.SkipZigTest;
    try expectValue("-a ** b", "(- (a ** b))");
    try expectValue("a ** -b ** c", "(a ** (- (b ** c)))");
    try expectValue("- - ~a + +b", "((- (- (~ a))) + (+ b))");
    try expectValue("-a * b", "((- a) * b)");
    try expectValue("not a and b or not c and not not d", "(((not a) and b) or ((not c) and (not (not d))))");
    try expectValue("not a < b", "(not (a < b))");
    try expectValue("not a == b", "(not (a == b))");
    try expectValue("await a ** b + await c", "(((await a) ** b) + (await c))");
}

test "python trailers bind tighter than every operator" {
    if (comptime !builds_trees) return error.SkipZigTest;
    try expectValue("-a.b", "(- (Attribute a b))");
    try expectValue("a.b.c(d)[e] + f(g).h ** i[j]", "((Subscript (Call (Attribute (Attribute a b) c) d) e) + ((Attribute (Call f g) h) ** (Subscript i j)))");
}

test "python conditionals and walrus take the whole sequence before them" {
    if (comptime !builds_trees) return error.SkipZigTest;
    try expectValue("a if b else c", "(a if b else c)");
    try expectValue("a + b if c and d else e - f if g else h", "((a + b) if (c and d) else ((e - f) if g else h))");
    try expectValue("a or b if c else d and e", "((a or b) if c else (d and e))");
    try expectValue("not a if b else c", "((not a) if b else c)");
    try expectValue("f(z := a or b)", "(Call f (z := (a or b)))");
}

/// Checks the first `Disjunction` of `source`.
fn expectDisjunction(comptime source: []const u8, expected: []const u8) !void {
    var tree = try Tree.parse(source);
    defer tree.deinit();
    try tree.expectSpans();
    try expectRendered(&tree, tree.firstOperand(try tree.find("Disjunction")), expected);
}

test "python disjunctions resolve like expressions" {
    if (comptime !builds_trees) return error.SkipZigTest;
    try expectDisjunction("x = [y for y in a < b < c + d]\n", "(a < b < (c + d))");
    try expectDisjunction("x = [y for y in not a is not b and c ** -d.e]\n", "((not (a is not b)) and (c ** (- (Attribute d e))))");
    try expectDisjunction("match x:\n    case a | b ^ c(d) if e:\n        pass\n", "(a | (b ^ (Call c d)))");
}

test "python keyword-named statements chain their trailers" {
    if (comptime !builds_trees) return error.SkipZigTest;
    var tree = try Tree.parse("print_x(a).b += 1\nreturn_value.x = c * d\n");
    defer tree.deinit();
    try tree.expectSpans();
    try expectRendered(&tree, try tree.expression("ExpressionStatement"), "(Attribute (Call print_x a) b)");
}

/// `x = a<separator>a<separator>...a` with `length` operands.
fn chainInput(separator: []const u8, length: usize) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    errdefer output.deinit();
    try output.writer.writeAll("x = ");
    for (0..length) |index| {
        if (index != 0) try output.writer.writeAll(separator);
        try output.writer.writeAll("a");
    }
    try output.writer.writeAll("\n");
    return output.toOwnedSlice();
}

/// The operand side a chain continues on: left for left-associative
/// operators and trailers, right for `**`.
const Descend = enum { first, last };

/// Walks a chain built from `link` nodes down the side `descend` names,
/// checking each link holds a plain `Name` on the other side, and returns
/// the number of links.
fn expectChain(tree: *Tree, root: Node.Pointer, link: []const u8, descend: Descend) !usize {
    var links: usize = 0;
    var address = root;
    while (std.mem.eql(u8, tree.name(address), link)) : (links += 1) {
        const first = tree.firstOperand(address);
        const last = tree.lastOperand(address);
        const kept, const next = if (descend == .first) .{ last, first } else .{ first, last };
        try std.testing.expectEqualStrings("Name", tree.name(kept));
        try std.testing.expectEqual(tree.at(first).text_start, tree.at(address).text_start);
        address = next;
    }
    try std.testing.expectEqualStrings("Name", tree.name(address));
    return links;
}

/// Parses a chain of `length` operands joined by `separator` and checks it
/// nests into `length - 1` links of `link`.
fn expectLongChain(separator: []const u8, length: usize, link: []const u8, descend: Descend) !void {
    const input = try chainInput(separator, length);
    defer std.testing.allocator.free(input);
    var tree = try Tree.parse(input);
    defer tree.deinit();
    if (comptime !builds_trees) return;
    const root = try tree.expression("AssignedValue");
    try std.testing.expectEqual(input.len - 1, tree.end(root));
    try std.testing.expectEqual(length - 1, try expectChain(&tree, root, link, descend));
}

/// Long enough that re-resolving the rest of the sequence at every level
/// would take minutes.
const long_chain = 100_000;

test "python long operator chains resolve in one pass" {
    try expectLongChain(" + ", long_chain, "BinaryOperation", .first);
    try expectLongChain(" or ", long_chain, "BinaryOperation", .first);
    // Each `**` level nests at the bottom of the right spine, and Debug
    // builds check every insertion against all of its new ancestors, which
    // is quadratic in the depth there.
    try expectLongChain(" ** ", long_chain / 10, "BinaryOperation", .last);
}

test "python long trailer chains nest every trailer" {
    try expectLongChain(".", long_chain, "Attribute", .first);
}
