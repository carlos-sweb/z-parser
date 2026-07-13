const std = @import("std");
const testing = std.testing;
const zparser = @import("zparser");
const helpers = @import("helpers.zig");

test "literals: number, string, bool, null, this" {
    try helpers.parseAndCheck("42", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .number_literal);
            try testing.expectEqual(@as(f64, 42), node.data.number_literal);
        }
    }.check);

    try helpers.parseAndCheck("\"hi\"", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .string_literal);
            try testing.expectEqualStrings("hi", node.data.string_literal);
        }
    }.check);

    try helpers.parseAndCheck("true", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .boolean_literal);
            try testing.expect(node.data.boolean_literal);
        }
    }.check);

    try helpers.parseAndCheck("null", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .null_literal);
        }
    }.check);

    try helpers.parseAndCheck("this", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .this_expr);
        }
    }.check);
}

test "identifier" {
    try helpers.parseAndCheck("myVar", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .identifier);
            try testing.expectEqualStrings("myVar", node.data.identifier);
        }
    }.check);
}

test "array literal with elision holes and spread" {
    try helpers.parseAndCheck("[1, , ...a]", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .array_literal);
            const els = node.data.array_literal;
            try testing.expectEqual(@as(usize, 3), els.len);
            try testing.expect(els[0] != null);
            try testing.expect(els[1] == null);
            try testing.expect(els[2] != null);
            try testing.expect(els[2].?.data == .spread);
        }
    }.check);
}

test "object literal: key:value, shorthand, computed, spread" {
    try helpers.parseAndCheck("({a: 1, b, [c]: 2, ...d})", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .paren);
            const obj = node.data.paren;
            try testing.expect(obj.data == .object_literal);
            const els = obj.data.object_literal;
            try testing.expectEqual(@as(usize, 4), els.len);
            try testing.expect(els[0] == .property);
            try testing.expect(!els[0].property.shorthand);
            try testing.expect(els[1] == .property);
            try testing.expect(els[1].property.shorthand);
            try testing.expect(els[2] == .property);
            try testing.expect(els[2].property.computed);
            try testing.expect(els[3] == .spread);
        }
    }.check);
}

test "object literal allows reserved words as keys" {
    try helpers.parseAndCheck("({if: 1, class: 2})", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const obj = node.data.paren;
            const els = obj.data.object_literal;
            try testing.expectEqualStrings("if", els[0].property.key.data.identifier);
        }
    }.check);
}

test "grouping expression wraps in .paren, not collapsed away" {
    try helpers.parseAndCheck("(1 + 2)", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .paren);
            try testing.expect(node.data.paren.data == .binary);
        }
    }.check);
}

test "sequence inside parens: (1, 2)" {
    try helpers.parseAndCheck("(1, 2)", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .paren);
            try testing.expect(node.data.paren.data == .sequence);
        }
    }.check);
}
