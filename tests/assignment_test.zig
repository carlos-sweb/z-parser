const std = @import("std");
const testing = std.testing;
const zparser = @import("zparser");
const helpers = @import("helpers.zig");

test "simple assignment to identifier and member expression" {
    try helpers.parseAndCheck("a = 1", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .assignment);
            try testing.expectEqual(zparser.AssignOp.assign, node.data.assignment.op);
            try testing.expect(node.data.assignment.target.data == .identifier);
        }
    }.check);
    try helpers.parseAndCheck("a.b = 1", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data.assignment.target.data == .member);
        }
    }.check);
}

test "compound assignment operators map to the right AssignOp" {
    const cases = .{
        .{ "a += 1", zparser.AssignOp.add },
        .{ "a -= 1", zparser.AssignOp.sub },
        .{ "a **= 1", zparser.AssignOp.pow },
        .{ "a &&= 1", zparser.AssignOp.logical_and },
        .{ "a ||= 1", zparser.AssignOp.logical_or },
        .{ "a ??= 1", zparser.AssignOp.nullish },
    };
    inline for (cases) |case| {
        try helpers.parseAndCheck(case[0], case[1], struct {
            fn check(expected: zparser.AssignOp, node: *zparser.Node) !void {
                try testing.expect(node.data == .assignment);
                try testing.expectEqual(expected, node.data.assignment.op);
            }
        }.check);
    }
}

test "(a) = 1 is valid -- parens around a simple target don't invalidate it" {
    try helpers.parseAndCheck("(a) = 1", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .assignment);
        }
    }.check);
}

test "invalid assignment targets are rejected" {
    try helpers.expectParseError("1 = 2", zparser.ParseError.InvalidAssignmentTarget);
    try helpers.expectParseError("(a + b) = 1", zparser.ParseError.InvalidAssignmentTarget);
    try helpers.expectParseError("(a, b) = 1", zparser.ParseError.InvalidAssignmentTarget);
}

test "ternary conditional, right-associative nesting" {
    try helpers.parseAndCheck("a ? b : c ? d : e", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .conditional);
            try testing.expect(node.data.conditional.alternate.data == .conditional);
        }
    }.check);
}

test "unary operators: typeof, void, delete, !, ~" {
    const cases = .{
        .{ "typeof a", zparser.UnaryOp.typeof },
        .{ "void a", zparser.UnaryOp.void_op },
        .{ "delete a", zparser.UnaryOp.delete },
        .{ "!a", zparser.UnaryOp.not },
        .{ "~a", zparser.UnaryOp.bitnot },
    };
    inline for (cases) |case| {
        try helpers.parseAndCheck(case[0], case[1], struct {
            fn check(expected: zparser.UnaryOp, node: *zparser.Node) !void {
                try testing.expect(node.data == .unary);
                try testing.expectEqual(expected, node.data.unary.op);
            }
        }.check);
    }
}
