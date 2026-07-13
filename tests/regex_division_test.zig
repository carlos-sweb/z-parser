const std = @import("std");
const testing = std.testing;
const zparser = @import("zparser");
const helpers = @import("helpers.zig");

test "a regex literal at the start of an expression" {
    try helpers.parseAndCheck("/abc/g", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .regex_literal);
            try testing.expectEqualStrings("abc", node.data.regex_literal.pattern);
            try testing.expectEqualStrings("g", node.data.regex_literal.flags);
        }
    }.check);
}

test "a regex literal after an operator (where '/' can't mean division)" {
    try helpers.parseAndCheck("a || /abc/", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .logical);
            try testing.expect(node.data.logical.right.data == .regex_literal);
        }
    }.check);
}

test "division after an identifier: a / b" {
    try helpers.parseAndCheck("a / b", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .binary);
            try testing.expectEqual(zparser.BinaryOp.div, node.data.binary.op);
        }
    }.check);
}

test "division chained after a call/member/literal all correctly treat / as division" {
    try helpers.parseAndCheck("f() / 2", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .binary);
            try testing.expectEqual(zparser.BinaryOp.div, node.data.binary.op);
        }
    }.check);
    try helpers.parseAndCheck("a.b / 2", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .binary);
        }
    }.check);
    try helpers.parseAndCheck("(1) / 2", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .binary);
        }
    }.check);
}

test "chained division: a / b / c parses left-associatively" {
    try helpers.parseAndCheck("a / b / c", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .binary);
            try testing.expectEqual(zparser.BinaryOp.div, node.data.binary.op);
            try testing.expect(node.data.binary.left.data == .binary);
        }
    }.check);
}
