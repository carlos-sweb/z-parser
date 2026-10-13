//! ECMAScript expression parser (ECMA-262 section 13).
//!
//! Create a `Parser` with an arena allocator and a borrowed source string,
//! then call `Parser.parseExpression` to obtain an arena-owned `Node` tree.
//! Keep the source and arena alive while using the parser or AST; releasing
//! the arena frees the entire parse result. Parsing consumes one expression
//! and leaves `Parser.current` at the following token, allowing statement
//! parsers to share the same stream.
//!
//! `NodeData` describes expression variants. `FunctionHooks` lets consumers
//! provide function and class grammar without adding statement dependencies.
//! Fallible parser operations return `ParseError`, including lexer errors
//! and allocator failure.

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
pub const PropertyKind = ast_mod.PropertyKind;
pub const MethodKind = parser_mod.MethodKind;

pub const Parser = parser_mod.Parser;
pub const ParseError = parser_mod.ParseError;
pub const isValidAssignmentPattern = parser_mod.isValidAssignmentPattern;
pub const FunctionHooks = parser_mod.FunctionHooks;
pub const FunctionHookResult = parser_mod.FunctionHookResult;

test {
    _ = @import("ast.zig");
    _ = @import("parser.zig");
}
