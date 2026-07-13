const std = @import("std");
const testing = std.testing;
const zparser = @import("zparser");
const helpers = @import("helpers.zig");

test "member access: a.b.c" {
    try helpers.parseAndCheck("a.b.c", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .member);
            try testing.expectEqualStrings("c", node.data.member.property.data.identifier);
            try testing.expect(!node.data.member.computed);
            const inner = node.data.member.object;
            try testing.expect(inner.data == .member);
            try testing.expectEqualStrings("b", inner.data.member.property.data.identifier);
        }
    }.check);
}

test "computed member access: a[b]" {
    try helpers.parseAndCheck("a[b]", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .member);
            try testing.expect(node.data.member.computed);
        }
    }.check);
}

test "call expression: f(1, 2)" {
    try helpers.parseAndCheck("f(1, 2)", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .call);
            try testing.expectEqual(@as(usize, 2), node.data.call.args.len);
            try testing.expect(!node.data.call.optional);
        }
    }.check);
}

test "chained calls and member access: f().g.h()" {
    try helpers.parseAndCheck("f().g.h()", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .call); // outermost: h()
            const h_member = node.data.call.callee;
            try testing.expect(h_member.data == .member);
            try testing.expectEqualStrings("h", h_member.data.member.property.data.identifier);
            const g_member = h_member.data.member.object;
            try testing.expect(g_member.data == .member);
            try testing.expectEqualStrings("g", g_member.data.member.property.data.identifier);
            try testing.expect(g_member.data.member.object.data == .call); // f()
        }
    }.check);
}

test "optional chaining: a?.b, a?.[b], a?.()" {
    try helpers.parseAndCheck("a?.b", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .member);
            try testing.expect(node.data.member.optional);
        }
    }.check);
    try helpers.parseAndCheck("a?.[b]", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .member);
            try testing.expect(node.data.member.optional);
            try testing.expect(node.data.member.computed);
        }
    }.check);
    try helpers.parseAndCheck("a?.()", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .call);
            try testing.expect(node.data.call.optional);
        }
    }.check);
}

test "optional chaining short-circuits the rest of the chain: a?.b.c" {
    try helpers.parseAndCheck("a?.b.c", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .member);
            try testing.expectEqualStrings("c", node.data.member.property.data.identifier);
            try testing.expect(!node.data.member.optional);
            try testing.expect(node.data.member.object.data.member.optional);
        }
    }.check);
}

test "new Foo() vs new Foo (no parens) vs new Foo.Bar()" {
    try helpers.parseAndCheck("new Foo()", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .new_expr);
            try testing.expect(node.data.new_expr.args != null);
            try testing.expectEqual(@as(usize, 0), node.data.new_expr.args.?.len);
        }
    }.check);
    try helpers.parseAndCheck("new Foo", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .new_expr);
            try testing.expect(node.data.new_expr.args == null);
        }
    }.check);
    try helpers.parseAndCheck("new Foo.Bar()", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .new_expr);
            try testing.expect(node.data.new_expr.callee.data == .member);
        }
    }.check);
}

test "new new Foo()() parses as new (new Foo())()" {
    try helpers.parseAndCheck("new new Foo()()", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .new_expr);
            try testing.expect(node.data.new_expr.args != null);
            try testing.expectEqual(@as(usize, 0), node.data.new_expr.args.?.len);
            const inner = node.data.new_expr.callee;
            try testing.expect(inner.data == .new_expr);
            try testing.expectEqualStrings("Foo", inner.data.new_expr.callee.data.identifier);
        }
    }.check);
}

test "spread in call arguments: f(...a, b)" {
    try helpers.parseAndCheck("f(...a, b)", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .call);
            try testing.expectEqual(@as(usize, 2), node.data.call.args.len);
            try testing.expect(node.data.call.args[0].data == .spread);
        }
    }.check);
}

test "prefix and postfix increment, assignment target validation" {
    try helpers.parseAndCheck("++a", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .unary);
            try testing.expectEqual(zparser.UnaryOp.pre_inc, node.data.unary.op);
        }
    }.check);
    try helpers.parseAndCheck("a++", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .unary);
            try testing.expectEqual(zparser.UnaryOp.post_inc, node.data.unary.op);
        }
    }.check);
    try helpers.expectParseError("1++", zparser.ParseError.InvalidAssignmentTarget);
    try helpers.expectParseError("++1", zparser.ParseError.InvalidAssignmentTarget);
}

test "no LineTerminator allowed before postfix ++/-- (ASI restricted production)" {
    // `a\n++b` must parse as two separate expressions in a real program
    // (ASI inserts a semicolon); at the single-expression level tested
    // here, the postfix operator simply doesn't attach across the newline,
    // so `++b` is parsed instead as its own prefix-increment leftover token
    // stream -- confirm postfix is rejected by checking the top node is NOT
    // a postfix unary on `a`.
    try helpers.parseAndCheck("a\n++b", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .identifier);
            try testing.expectEqualStrings("a", node.data.identifier);
        }
    }.check);
}
