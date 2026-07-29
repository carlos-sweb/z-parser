//! `Parser.stack_limit`/`checkStackDepth` -- z-parser-improve.md's Point 3
//! (native-stack-overflow guard for unbounded nesting). Mirrors
//! z-interpreter's own `@frameAddress()`-based `evalExpression` guard.
const std = @import("std");
const testing = std.testing;
const zparser = @import("zparser");

fn nestedParens(arena: std.mem.Allocator, n: usize) ![]u8 {
    var src: std.ArrayList(u8) = .empty;
    for (0..n) |_| try src.append(arena, '(');
    try src.append(arena, '1');
    for (0..n) |_| try src.append(arena, ')');
    return src.toOwnedSlice(arena);
}

test "stack_limit = 0 (the default) never trips the guard, however deep" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src = try nestedParens(arena, 50);
    var parser = try zparser.Parser.init(arena, src);
    try testing.expectEqual(@as(usize, 0), parser.stack_limit);
    _ = try parser.parseExpression();
}

test "an already-exceeded stack_limit fails fast as MaxNestingDepthExceeded, not a crash" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var parser = try zparser.Parser.init(arena, "1");
    // Stack grows down: any frame at or below the CURRENT one already
    // trips `@frameAddress() < stack_limit` the moment parseAssignment is
    // entered -- no real nesting needed to exercise the mechanism itself.
    parser.stack_limit = @frameAddress();
    try testing.expectError(zparser.ParseError.MaxNestingDepthExceeded, parser.parseExpression());
}

test "a moderate stack_limit budget still allows moderately-nested real input" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src = try nestedParens(arena, 50);
    var parser = try zparser.Parser.init(arena, src);
    parser.stack_limit = @frameAddress() -| (2 * 1024 * 1024);
    _ = try parser.parseExpression();
}

test "deep-enough real nesting trips the guard under a small budget (end-to-end, not synthetic)" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src = try nestedParens(arena, 5_000);
    var parser = try zparser.Parser.init(arena, src);
    parser.stack_limit = @frameAddress() -| (64 * 1024);
    try testing.expectError(zparser.ParseError.MaxNestingDepthExceeded, parser.parseExpression());
}

test "checkStackDepth also guards parseUnary's prefix-operator recursion" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var src: std.ArrayList(u8) = .empty;
    for (0..5_000) |_| try src.append(arena, '!');
    try src.append(arena, 'x');

    var parser = try zparser.Parser.init(arena, src.items);
    parser.stack_limit = @frameAddress() -| (64 * 1024);
    try testing.expectError(zparser.ParseError.MaxNestingDepthExceeded, parser.parseExpression());
}

test "checkStackDepth also guards parseMemberExpressionImpl's new-chain recursion" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var src: std.ArrayList(u8) = .empty;
    for (0..5_000) |_| try src.appendSlice(arena, "new ");
    try src.appendSlice(arena, "Foo");

    var parser = try zparser.Parser.init(arena, src.items);
    parser.stack_limit = @frameAddress() -| (64 * 1024);
    try testing.expectError(zparser.ParseError.MaxNestingDepthExceeded, parser.parseExpression());
}
