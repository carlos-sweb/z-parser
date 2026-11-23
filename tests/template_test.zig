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

test "tagged template: basic, chained, and raw vs cooked" {
    try helpers.parseAndCheck("obj.tag`a\\nb${1}c`", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .tagged_template);
            const tt = node.data.tagged_template;
            try testing.expect(tt.tag.data == .member);
            try testing.expectEqual(@as(usize, 2), tt.cooked.len);
            try testing.expectEqualStrings("a\nb", tt.cooked[0].?);
            try testing.expectEqualStrings("a\\nb", tt.raw[0]);
            try testing.expectEqualStrings("c", tt.cooked[1].?);
            try testing.expectEqual(@as(usize, 1), tt.expressions.len);
        }
    }.check);

    try helpers.parseAndCheck("tag`a``b`.prop()", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .call);
            try testing.expect(node.data.call.callee.data == .member);
            try testing.expect(node.data.call.callee.data.member.object.data == .tagged_template);
            try testing.expect(node.data.call.callee.data.member.object.data.tagged_template.tag.data == .tagged_template);
        }
    }.check);
}

test "tagged template: invalid escapes produce null cooked and preserve raw, untagged rejects" {
    try helpers.parseAndCheck("tag`\\unicode${1}\\x1\\8\\01`", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const tt = node.data.tagged_template;
            try testing.expectEqual(@as(usize, 2), tt.cooked.len);
            try testing.expect(tt.cooked[0] == null);
            try testing.expectEqualStrings("\\unicode", tt.raw[0]);
            try testing.expect(tt.cooked[1] == null);
            try testing.expectEqualStrings("\\x1\\8\\01", tt.raw[1]);
        }
    }.check);

    try helpers.parseAndCheck("tag`a\r\nb\rc`", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const tt = node.data.tagged_template;
            try testing.expectEqualStrings("a\nb\nc", tt.raw[0]);
            try testing.expectEqualStrings("a\nb\nc", tt.cooked[0].?);
        }
    }.check);

    try helpers.expectParseError("(`\\unicode`)", zparser.ParseError.InvalidEscapeSequence);
    try helpers.expectParseError("`\\8`", zparser.ParseError.InvalidEscapeSequence);
    try helpers.expectParseError("new tag`a`", zparser.ParseError.UnexpectedToken);
    try helpers.expectParseError("a?.b`x`", zparser.ParseError.UnexpectedToken);
}
