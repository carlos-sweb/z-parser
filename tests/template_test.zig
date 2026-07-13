const std = @import("std");
const testing = std.testing;
const zparser = @import("zparser");
const helpers = @import("helpers.zig");

test "template with no substitution" {
    try helpers.parseAndCheck("`plain text`", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .template_literal);
            try testing.expectEqual(@as(usize, 1), node.data.template_literal.quasis.len);
            try testing.expectEqualStrings("plain text", node.data.template_literal.quasis[0]);
            try testing.expectEqual(@as(usize, 0), node.data.template_literal.expressions.len);
        }
    }.check);
}

test "template with one substitution" {
    try helpers.parseAndCheck("`a${1+2}b`", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .template_literal);
            const t = node.data.template_literal;
            try testing.expectEqual(@as(usize, 2), t.quasis.len);
            try testing.expectEqualStrings("a", t.quasis[0]);
            try testing.expectEqualStrings("b", t.quasis[1]);
            try testing.expectEqual(@as(usize, 1), t.expressions.len);
            try testing.expect(t.expressions[0].data == .binary);
        }
    }.check);
}

test "template with multiple substitutions" {
    try helpers.parseAndCheck("`${1}-${2}`", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const t = node.data.template_literal;
            try testing.expectEqual(@as(usize, 3), t.quasis.len);
            try testing.expectEqualStrings("", t.quasis[0]);
            try testing.expectEqualStrings("-", t.quasis[1]);
            try testing.expectEqualStrings("", t.quasis[2]);
            try testing.expectEqual(@as(usize, 2), t.expressions.len);
        }
    }.check);
}

test "object literal inside a substitution: nested braces don't confuse the driver" {
    try helpers.parseAndCheck("`x${ {a:1}.a }y`", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const t = node.data.template_literal;
            try testing.expectEqual(@as(usize, 1), t.expressions.len);
            try testing.expect(t.expressions[0].data == .member);
            try testing.expect(t.expressions[0].data.member.object.data == .object_literal);
        }
    }.check);
}

test "nested template inside a substitution" {
    try helpers.parseAndCheck("`outer${`inner`}end`", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const t = node.data.template_literal;
            try testing.expectEqualStrings("outer", t.quasis[0]);
            try testing.expectEqualStrings("end", t.quasis[1]);
            try testing.expectEqual(@as(usize, 1), t.expressions.len);
            try testing.expect(t.expressions[0].data == .template_literal);
            try testing.expectEqualStrings("inner", t.expressions[0].data.template_literal.quasis[0]);
        }
    }.check);
}

test "sequence expression inside a substitution: `${1, 2}`" {
    try helpers.parseAndCheck("`${1, 2}`", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const t = node.data.template_literal;
            try testing.expect(t.expressions[0].data == .sequence);
        }
    }.check);
}

test "escape sequence inside a template quasi" {
    try helpers.parseAndCheck("`a\\nb`", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expectEqualStrings("a\nb", node.data.template_literal.quasis[0]);
        }
    }.check);
}
