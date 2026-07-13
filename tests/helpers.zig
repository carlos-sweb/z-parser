const std = @import("std");
const zparser = @import("zparser");

/// Parses `source` as a single Expression using a fresh arena, and hands
/// both the resulting root node and the arena to `check` so it can inspect
/// the tree; the arena (and everything allocated in it -- nodes, lexer
/// owned_values) is torn down in one shot afterward.
pub fn parseAndCheck(source: []const u8, context: anytype, comptime check: fn (@TypeOf(context), *zparser.Node) anyerror!void) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var parser = try zparser.Parser.init(arena, source);
    const node = try parser.parseExpression();
    try check(context, node);
}

pub fn expectParseError(source: []const u8, expected: zparser.ParseError) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var parser = try zparser.Parser.init(arena, source);
    try std.testing.expectError(expected, parser.parseExpression());
}
