const ast_mod = @import("ast.zig");
const parser_mod = @import("parser.zig");

pub const Node = ast_mod.Node;
pub const NodeData = ast_mod.NodeData;
pub const UnaryOp = ast_mod.UnaryOp;
pub const BinaryOp = ast_mod.BinaryOp;
pub const LogicalOp = ast_mod.LogicalOp;
pub const AssignOp = ast_mod.AssignOp;
pub const ObjectProperty = ast_mod.ObjectProperty;
pub const ObjectLiteralElement = ast_mod.ObjectLiteralElement;

pub const Parser = parser_mod.Parser;
pub const ParseError = parser_mod.ParseError;
pub const isValidAssignmentPattern = parser_mod.isValidAssignmentPattern;
pub const FunctionHooks = parser_mod.FunctionHooks;
pub const FunctionHookResult = parser_mod.FunctionHookResult;

test {
    _ = @import("ast.zig");
    _ = @import("parser.zig");
}
