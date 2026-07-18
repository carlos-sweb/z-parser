const std = @import("std");

pub const Node = struct {
    start: usize,
    end: usize,
    data: NodeData,
};

pub const UnaryOp = enum { not, bitnot, plus, minus, typeof, void_op, delete, pre_inc, pre_dec, post_inc, post_dec };

pub const BinaryOp = enum {
    add,
    sub,
    mul,
    div,
    mod,
    pow,
    bitand,
    bitor,
    bitxor,
    shl,
    shr,
    ushr,
    eq,
    ne,
    eqeqeq,
    noteqeq,
    lt,
    gt,
    le,
    ge,
    instanceof,
    in,
};

pub const LogicalOp = enum { and_op, or_op, nullish };

pub const AssignOp = enum {
    assign,
    add,
    sub,
    mul,
    div,
    mod,
    pow,
    shl,
    shr,
    ushr,
    bitand,
    bitor,
    bitxor,
    logical_and,
    logical_or,
    nullish,
};

/// `.init` = ordinary `key: value` / shorthand; `.method` = `m() {}`;
/// `.get`/`.set` = accessor clauses. For the last three, `value` is the
/// opaque `.function_like` node produced by the parseMethod hook.
pub const PropertyKind = enum { init, method, get, set };

pub const ObjectProperty = struct {
    key: *Node,
    value: *Node,
    computed: bool,
    shorthand: bool,
    kind: PropertyKind,
};

pub const ObjectLiteralElement = union(enum) {
    property: ObjectProperty,
    /// `...expr` inside an object literal.
    spread: *Node,
};

pub const NodeData = union(enum) {
    number_literal: f64,
    /// Raw digit text (no evaluated value -- there's no BigInt runtime type
    /// yet; see z-lexer's own bigint_literal token for the same deferral).
    bigint_literal: []const u8,
    string_literal: []const u8,
    boolean_literal: bool,
    null_literal: void,
    identifier: []const u8,
    regex_literal: struct { pattern: []const u8, flags: []const u8 },
    this_expr: void,

    template_literal: struct {
        /// quasis.len == expressions.len + 1 (the literal chunks around each
        /// substitution, cooked value -- no `.raw` TRV, see README).
        quasis: []const []const u8,
        expressions: []const *Node,
    },
    /// null element = an elision hole, e.g. the middle of `[1,,3]`.
    array_literal: []const ?*Node,
    object_literal: []const ObjectLiteralElement,
    /// `...expr` inside an array literal or a call's argument list (object
    /// literals use ObjectLiteralElement.spread instead, since a spread
    /// there is a sibling of properties, not a value).
    spread: *Node,
    /// An explicitly parenthesized expression -- kept as its own node (not
    /// collapsed away) because parenthesization is semantically load-bearing
    /// in a few spots: `-2 ** 2` is a SyntaxError but `(-2) ** 2` isn't, and
    /// `(a) = 1` is a valid assignment target but `(a + b) = 1` isn't.
    paren: *Node,

    unary: struct { op: UnaryOp, operand: *Node },
    binary: struct { op: BinaryOp, left: *Node, right: *Node },
    logical: struct { op: LogicalOp, left: *Node, right: *Node },
    assignment: struct { op: AssignOp, target: *Node, value: *Node },
    conditional: struct { test_expr: *Node, consequent: *Node, alternate: *Node },
    sequence: []const *Node,

    call: struct { callee: *Node, args: []const *Node, optional: bool },
    /// args == null: `new Foo` with no argument list at all (distinct from
    /// `new Foo()`, which has args.len == 0).
    new_expr: struct { callee: *Node, args: ?[]const *Node },
    member: struct { object: *Node, property: *Node, computed: bool, optional: bool },
    /// A function/arrow-function expression node, typed and owned solely by
    /// z-functions -- this repo never dereferences it. See z-functions'
    /// `asFunctionNode()`.
    function_like: *anyopaque,
    /// A class expression node, typed and owned solely by z-functions --
    /// this repo never dereferences it. See z-functions' `asClassNode()`.
    class_like: *anyopaque,
    /// `yield` / `yield expr` -- only parsed inside generator bodies
    /// (Parser.yield_allowed, set by z-functions). `yield*` delegation
    /// is deferred.
    yield_expr: struct { argument: ?*Node },
    /// `await expr` -- only parsed inside async function bodies
    /// (Parser.await_allowed); elsewhere `await` stays an ordinary
    /// identifier (it's contextual, not a keyword).
    await_expr: *Node,
    /// The `super` keyword in expression position. Only meaningful as a
    /// call callee (`super(...)`) or member object (`super.m`) inside
    /// class bodies -- both shapes fall out of the ordinary call/member
    /// machinery; the interpreter validates placement at runtime.
    super_expr: void,
};
