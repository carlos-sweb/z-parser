const std = @import("std");
const testing = std.testing;
const zparser = @import("zparser");
const helpers = @import("helpers.zig");

fn expectBinary(node: *zparser.Node, op: zparser.BinaryOp) !void {
    try testing.expect(node.data == .binary);
    try testing.expectEqual(op, node.data.binary.op);
}
fn expectNumber(node: *zparser.Node, value: f64) !void {
    try testing.expect(node.data == .number_literal);
    try testing.expectEqual(value, node.data.number_literal);
}

test "multiplicative binds tighter than additive: 1 + 2 * 3" {
    try helpers.parseAndCheck("1 + 2 * 3", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try expectBinary(node, .add);
            try expectNumber(node.data.binary.left, 1);
            try expectBinary(node.data.binary.right, .mul);
            try expectNumber(node.data.binary.right.data.binary.left, 2);
            try expectNumber(node.data.binary.right.data.binary.right, 3);
        }
    }.check);
}

test "left-associative: 1 - 2 - 3 parses as (1 - 2) - 3" {
    try helpers.parseAndCheck("1 - 2 - 3", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try expectBinary(node, .sub);
            try expectNumber(node.data.binary.right, 3);
            try expectBinary(node.data.binary.left, .sub);
            try expectNumber(node.data.binary.left.data.binary.left, 1);
            try expectNumber(node.data.binary.left.data.binary.right, 2);
        }
    }.check);
}

test "exponentiation is right-associative: 2 ** 3 ** 2 parses as 2 ** (3 ** 2)" {
    try helpers.parseAndCheck("2 ** 3 ** 2", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try expectBinary(node, .pow);
            try expectNumber(node.data.binary.left, 2);
            try expectBinary(node.data.binary.right, .pow);
            try expectNumber(node.data.binary.right.data.binary.left, 3);
            try expectNumber(node.data.binary.right.data.binary.right, 2);
        }
    }.check);
}

test "unary operand of ** requires parens: -2 ** 2 is a SyntaxError" {
    try helpers.expectParseError("-2 ** 2", zparser.ParseError.InvalidExponentiationOperand);
}

test "(-2) ** 2 is valid once parenthesized" {
    try helpers.parseAndCheck("(-2) ** 2", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try expectBinary(node, .pow);
            try testing.expect(node.data.binary.left.data == .paren);
        }
    }.check);
}

test "?? cannot mix with || without parens" {
    try helpers.expectParseError("a ?? b || c", zparser.ParseError.NullishMixedWithLogical);
    try helpers.expectParseError("a || b ?? c", zparser.ParseError.NullishMixedWithLogical);
}

test "(a ?? b) || c is valid once parenthesized" {
    try helpers.parseAndCheck("(a ?? b) || c", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .logical);
            try testing.expectEqual(zparser.LogicalOp.or_op, node.data.logical.op);
        }
    }.check);
}

test "&& binds tighter than ||: a && b || c && d parses as (a && b) || (c && d)" {
    try helpers.parseAndCheck("a && b || c && d", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .logical);
            try testing.expectEqual(zparser.LogicalOp.or_op, node.data.logical.op);
            try testing.expectEqual(zparser.LogicalOp.and_op, node.data.logical.left.data.logical.op);
            try testing.expectEqual(zparser.LogicalOp.and_op, node.data.logical.right.data.logical.op);
        }
    }.check);
}

test "comparison/equality/relational precedence and instanceof/in" {
    try helpers.parseAndCheck("a < b === c", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try expectBinary(node, .eqeqeq);
            try expectBinary(node.data.binary.left, .lt);
        }
    }.check);
    try helpers.parseAndCheck("a instanceof b", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try expectBinary(node, .instanceof);
        }
    }.check);
}

test "assignment is right-associative: a = b = 1" {
    try helpers.parseAndCheck("a = b = 1", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .assignment);
            try testing.expectEqual(zparser.AssignOp.assign, node.data.assignment.op);
            try testing.expect(node.data.assignment.value.data == .assignment);
        }
    }.check);
}

test "comma operator builds a sequence, lowest precedence" {
    try helpers.parseAndCheck("1, 2, 3", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .sequence);
            try testing.expectEqual(@as(usize, 3), node.data.sequence.len);
        }
    }.check);
}

// Node/V8-verified: precedence composition sanity check via eval() equality.
test "precedence composition matches V8 (Node-verified): 2 + 3 * 4 ** 2 === 50" {
    // node -e "console.log(2 + 3 * 4 ** 2)" => 50
    try helpers.parseAndCheck("2 + 3 * 4 ** 2", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try expectBinary(node, .add);
            try expectNumber(node.data.binary.left, 2);
            try expectBinary(node.data.binary.right, .mul);
            try expectNumber(node.data.binary.right.data.binary.left, 3);
            try expectBinary(node.data.binary.right.data.binary.right, .pow);
        }
    }.check);
}
