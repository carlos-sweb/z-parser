const std = @import("std");
const Allocator = std.mem.Allocator;
const zlexer = @import("zlexer");
const Lexer = zlexer.Lexer;
const Token = zlexer.Token;
const TokenType = zlexer.TokenType;
const LexContext = zlexer.LexContext;
const ast = @import("ast.zig");
const Node = ast.Node;
const NodeData = ast.NodeData;

pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEnd,
    InvalidAssignmentTarget,
    /// `a ?? b || c` / `a || b ?? c` without parens -- ECMA-262 forbids
    /// mixing `??` directly with `&&`/`||` at the same nesting level.
    NullishMixedWithLogical,
    /// `-a ** b` without parens -- the left operand of `**` may not be an
    /// un-parenthesized unary expression (`(-a) ** b` is fine).
    InvalidExponentiationOperand,
} || zlexer.LexError;

const ArgList = struct { args: []const *Node, end: usize };

/// `/` is either division or the start of a RegExpLiteral depending on
/// grammar position (ECMA-262 12.1's InputElementRegExp vs InputElementDiv).
/// False (division) after anything that can end a complete expression;
/// true (regex) everywhere else. `}` falls into the `true` (regex) default:
/// most `}` occurrences close a block/switch/try-catch-finally, after which
/// a fresh statement begins and a leading `/` is a regex. The one place `}`
/// closes an object literal instead (where division should follow) is
/// disambiguated explicitly at that call site via `advanceWithContext`
/// (see `parseObjectLiteral`), not through this default.
fn regexAllowedAfter(t: TokenType) bool {
    return switch (t) {
        .identifier,
        .private_identifier,
        .numeric_literal,
        .bigint_literal,
        .string_literal,
        .regex_literal,
        .template_no_substitution,
        .template_tail,
        .punct_rparen,
        .punct_rbracket,
        .punct_plusplus,
        .punct_minusminus,
        .keyword_this,
        .keyword_true,
        .keyword_false,
        .keyword_null,
        => false,
        else => true,
    };
}

fn isValidAssignmentTarget(node: *Node) bool {
    return switch (node.data) {
        .identifier, .member => true,
        .paren => |inner| isValidAssignmentTarget(inner),
        else => false,
    };
}

fn assignOpFor(t: TokenType) ?ast.AssignOp {
    return switch (t) {
        .punct_assign => .assign,
        .punct_plus_assign => .add,
        .punct_minus_assign => .sub,
        .punct_star_assign => .mul,
        .punct_slash_assign => .div,
        .punct_percent_assign => .mod,
        .punct_starstar_assign => .pow,
        .punct_shl_assign => .shl,
        .punct_shr_assign => .shr,
        .punct_ushr_assign => .ushr,
        .punct_amp_assign => .bitand,
        .punct_pipe_assign => .bitor,
        .punct_caret_assign => .bitxor,
        .punct_ampamp_assign => .logical_and,
        .punct_pipepipe_assign => .logical_or,
        .punct_question_question_assign => .nullish,
        else => null,
    };
}

fn unaryOpFor(t: TokenType) ?ast.UnaryOp {
    return switch (t) {
        .punct_bang => .not,
        .punct_tilde => .bitnot,
        .punct_plus => .plus,
        .punct_minus => .minus,
        .keyword_typeof => .typeof,
        .keyword_void => .void_op,
        .keyword_delete => .delete,
        else => null,
    };
}

fn multiplicativeOp(t: TokenType) ?ast.BinaryOp {
    return switch (t) {
        .punct_star => .mul,
        .punct_slash => .div,
        .punct_percent => .mod,
        else => null,
    };
}
fn additiveOp(t: TokenType) ?ast.BinaryOp {
    return switch (t) {
        .punct_plus => .add,
        .punct_minus => .sub,
        else => null,
    };
}
fn shiftOp(t: TokenType) ?ast.BinaryOp {
    return switch (t) {
        .punct_shl => .shl,
        .punct_shr => .shr,
        .punct_ushr => .ushr,
        else => null,
    };
}
fn relationalOp(t: TokenType) ?ast.BinaryOp {
    return switch (t) {
        .punct_lt => .lt,
        .punct_gt => .gt,
        .punct_le => .le,
        .punct_ge => .ge,
        .keyword_instanceof => .instanceof,
        .keyword_in => .in,
        else => null,
    };
}
fn equalityOp(t: TokenType) ?ast.BinaryOp {
    return switch (t) {
        .punct_eq => .eq,
        .punct_ne => .ne,
        .punct_eqeqeq => .eqeqeq,
        .punct_noteqeq => .noteqeq,
        else => null,
    };
}
fn bitandOp(t: TokenType) ?ast.BinaryOp {
    return if (t == .punct_amp) .bitand else null;
}
fn bitxorOp(t: TokenType) ?ast.BinaryOp {
    return if (t == .punct_caret) .bitxor else null;
}
fn bitorOp(t: TokenType) ?ast.BinaryOp {
    return if (t == .punct_pipe) .bitor else null;
}

pub const Parser = struct {
    lexer: Lexer,
    arena: Allocator,
    current: Token,

    pub fn init(arena: Allocator, source: []const u8) ParseError!Parser {
        var self: Parser = .{
            .lexer = Lexer.init(arena, source),
            .arena = arena,
            .current = undefined,
        };
        self.current = try self.lexer.nextToken(.regex_allowed);
        return self;
    }

    pub fn advance(self: *Parser) ParseError!void {
        const ctx: LexContext = if (regexAllowedAfter(self.current.type)) .regex_allowed else .div_allowed;
        try self.advanceWithContext(ctx);
    }

    /// Same as `advance`, but with an explicit `LexContext` instead of the
    /// one `regexAllowedAfter` infers from the outgoing token. Needed at the
    /// handful of call sites where the outgoing token's regex-vs-division
    /// context is ambiguous from its type alone (see `parseObjectLiteral`'s
    /// closing `}`) or where a caller in a dependent repo (e.g. a future
    /// statement parser) needs to drive the lexer through a context this
    /// parser has no way to infer on its own.
    pub fn advanceWithContext(self: *Parser, ctx: LexContext) ParseError!void {
        self.current = try self.lexer.nextToken(ctx);
    }

    pub fn expect(self: *Parser, t: TokenType) ParseError!Token {
        if (self.current.type != t) return ParseError.UnexpectedToken;
        const tok = self.current;
        try self.advance();
        return tok;
    }

    fn newNode(self: *Parser, start: usize, end: usize, data: NodeData) ParseError!*Node {
        const node = try self.arena.create(Node);
        node.* = .{ .start = start, .end = end, .data = data };
        return node;
    }

    // ===== Entry point =====

    /// Full Expression production (comma operator included).
    pub fn parseExpression(self: *Parser) ParseError!*Node {
        const first = try self.parseAssignment();
        if (self.current.type != .punct_comma) return first;
        var items: std.ArrayList(*Node) = .empty;
        try items.append(self.arena, first);
        while (self.current.type == .punct_comma) {
            try self.advance();
            try items.append(self.arena, try self.parseAssignment());
        }
        const last = items.items[items.items.len - 1];
        return self.newNode(first.start, last.end, .{ .sequence = try items.toOwnedSlice(self.arena) });
    }

    // ===== Assignment / Conditional / Short-circuit (&&, ||, ??) =====

    /// Public entry point for the AssignmentExpression production (no comma
    /// operator) -- needed by grammar positions that are spec'd one level
    /// below full `Expression`, e.g. a variable declarator's initializer or
    /// a `for-of` loop's iterable clause.
    pub fn parseAssignmentExpression(self: *Parser) ParseError!*Node {
        return self.parseAssignment();
    }

    fn parseAssignment(self: *Parser) ParseError!*Node {
        const left = try self.parseConditional();
        if (assignOpFor(self.current.type)) |op| {
            if (!isValidAssignmentTarget(left)) return ParseError.InvalidAssignmentTarget;
            try self.advance();
            const right = try self.parseAssignment(); // right-associative
            return self.newNode(left.start, right.end, .{ .assignment = .{ .op = op, .target = left, .value = right } });
        }
        return left;
    }

    fn parseConditional(self: *Parser) ParseError!*Node {
        const test_expr = try self.parseShortCircuit();
        if (self.current.type != .punct_question) return test_expr;
        try self.advance();
        const consequent = try self.parseAssignment();
        _ = try self.expect(.punct_colon);
        const alternate = try self.parseAssignment(); // right-associative nesting for chained ternaries
        return self.newNode(test_expr.start, alternate.end, .{ .conditional = .{ .test_expr = test_expr, .consequent = consequent, .alternate = alternate } });
    }

    /// ECMA-262's ShortCircuitExpression: either a LogicalORExpression tree
    /// (&&/|| freely mixed, && binding tighter) or a CoalesceExpression tree
    /// (?? chained over BitwiseOR-level operands) -- never both without
    /// explicit parens breaking up the levels.
    fn parseShortCircuit(self: *Parser) ParseError!*Node {
        const first = try self.parseBitOr();

        if (self.current.type == .punct_question_question) {
            var left = first;
            while (self.current.type == .punct_question_question) {
                try self.advance();
                const right = try self.parseBitOr();
                left = try self.newNode(left.start, right.end, .{ .logical = .{ .op = .nullish, .left = left, .right = right } });
            }
            if (self.current.type == .punct_ampamp or self.current.type == .punct_pipepipe) {
                return ParseError.NullishMixedWithLogical;
            }
            return left;
        }

        var left = first;
        while (self.current.type == .punct_ampamp) {
            try self.advance();
            const right = try self.parseBitOr();
            left = try self.newNode(left.start, right.end, .{ .logical = .{ .op = .and_op, .left = left, .right = right } });
        }
        while (self.current.type == .punct_pipepipe) {
            try self.advance();
            var right = try self.parseBitOr();
            while (self.current.type == .punct_ampamp) {
                try self.advance();
                const rhs = try self.parseBitOr();
                right = try self.newNode(right.start, rhs.end, .{ .logical = .{ .op = .and_op, .left = right, .right = rhs } });
            }
            left = try self.newNode(left.start, right.end, .{ .logical = .{ .op = .or_op, .left = left, .right = right } });
        }
        if (self.current.type == .punct_question_question) return ParseError.NullishMixedWithLogical;
        return left;
    }

    // ===== Binary operator precedence chain =====

    fn parseBinaryLevel(self: *Parser, comptime opFor: fn (TokenType) ?ast.BinaryOp, comptime next: fn (*Parser) ParseError!*Node) ParseError!*Node {
        var left = try next(self);
        while (opFor(self.current.type)) |op| {
            try self.advance();
            const right = try next(self);
            left = try self.newNode(left.start, right.end, .{ .binary = .{ .op = op, .left = left, .right = right } });
        }
        return left;
    }

    fn parseBitOr(self: *Parser) ParseError!*Node {
        return self.parseBinaryLevel(bitorOp, parseBitXor);
    }
    fn parseBitXor(self: *Parser) ParseError!*Node {
        return self.parseBinaryLevel(bitxorOp, parseBitAnd);
    }
    fn parseBitAnd(self: *Parser) ParseError!*Node {
        return self.parseBinaryLevel(bitandOp, parseEquality);
    }
    fn parseEquality(self: *Parser) ParseError!*Node {
        return self.parseBinaryLevel(equalityOp, parseRelational);
    }
    fn parseRelational(self: *Parser) ParseError!*Node {
        return self.parseBinaryLevel(relationalOp, parseShift);
    }
    fn parseShift(self: *Parser) ParseError!*Node {
        return self.parseBinaryLevel(shiftOp, parseAdditive);
    }
    fn parseAdditive(self: *Parser) ParseError!*Node {
        return self.parseBinaryLevel(additiveOp, parseMultiplicative);
    }
    fn parseMultiplicative(self: *Parser) ParseError!*Node {
        return self.parseBinaryLevel(multiplicativeOp, parseExponentiation);
    }

    fn parseExponentiation(self: *Parser) ParseError!*Node {
        const left = try self.parseUnary();
        if (self.current.type != .punct_starstar) return left;
        if (left.data == .unary) return ParseError.InvalidExponentiationOperand;
        try self.advance();
        const right = try self.parseExponentiation(); // right-associative
        return self.newNode(left.start, right.end, .{ .binary = .{ .op = .pow, .left = left, .right = right } });
    }

    // ===== Unary / postfix =====

    fn parseUnary(self: *Parser) ParseError!*Node {
        if (unaryOpFor(self.current.type)) |op| {
            const start = self.current.start;
            try self.advance();
            const operand = try self.parseUnary();
            return self.newNode(start, operand.end, .{ .unary = .{ .op = op, .operand = operand } });
        }
        if (self.current.type == .punct_plusplus or self.current.type == .punct_minusminus) {
            const is_inc = self.current.type == .punct_plusplus;
            const start = self.current.start;
            try self.advance();
            const operand = try self.parseUnary();
            if (!isValidAssignmentTarget(operand)) return ParseError.InvalidAssignmentTarget;
            return self.newNode(start, operand.end, .{ .unary = .{ .op = if (is_inc) .pre_inc else .pre_dec, .operand = operand } });
        }
        return self.parsePostfix();
    }

    fn parsePostfix(self: *Parser) ParseError!*Node {
        const operand = try self.parseMemberExpression();
        if ((self.current.type == .punct_plusplus or self.current.type == .punct_minusminus) and !self.current.had_line_terminator_before) {
            if (!isValidAssignmentTarget(operand)) return ParseError.InvalidAssignmentTarget;
            const op: ast.UnaryOp = if (self.current.type == .punct_plusplus) .post_inc else .post_dec;
            const end = self.current.end;
            try self.advance();
            return self.newNode(operand.start, end, .{ .unary = .{ .op = op, .operand = operand } });
        }
        return operand;
    }

    // ===== Member / New / Call =====

    fn parseArguments(self: *Parser) ParseError!ArgList {
        _ = try self.expect(.punct_lparen);
        var args: std.ArrayList(*Node) = .empty;
        while (self.current.type != .punct_rparen) {
            if (self.current.type == .punct_ellipsis) {
                const spread_start = self.current.start;
                try self.advance();
                const arg = try self.parseAssignment();
                try args.append(self.arena, try self.newNode(spread_start, arg.end, .{ .spread = arg }));
            } else {
                try args.append(self.arena, try self.parseAssignment());
            }
            if (self.current.type != .punct_rparen) _ = try self.expect(.punct_comma);
        }
        const end = self.current.end;
        try self.advance();
        return .{ .args = try args.toOwnedSlice(self.arena), .end = end };
    }

    fn parsePropertyNameAfterDot(self: *Parser) ParseError!*Node {
        const tok = self.current;
        // IdentifierName: any identifier OR reserved keyword is valid after
        // `.`/`?.` (e.g. `obj.if`, `obj.class`).
        if (tok.type != .identifier and zlexer.keywordFromLexeme(tok.lexeme) == null) {
            return ParseError.UnexpectedToken;
        }
        const name = tok.owned_value orelse tok.lexeme;
        try self.advance();
        return self.newNode(tok.start, tok.end, .{ .identifier = name });
    }

    /// Chains `.prop`, `[expr]`, and (when `allow_calls`) `(...)`/`?.`
    /// suffixes onto `base_in`. `allow_calls` is false while parsing a
    /// `new` expression's callee: the call parens right after it belong to
    /// `new` itself (or to nothing, for `new Foo` with no parens at all),
    /// never to a nested call baked into the callee.
    fn parseMemberSuffixes(self: *Parser, base_in: *Node, comptime allow_calls: bool) ParseError!*Node {
        var base = base_in;
        while (true) {
            if (self.current.type == .punct_dot) {
                try self.advance();
                const prop = try self.parsePropertyNameAfterDot();
                base = try self.newNode(base.start, prop.end, .{ .member = .{ .object = base, .property = prop, .computed = false, .optional = false } });
            } else if (self.current.type == .punct_lbracket) {
                try self.advance();
                const prop = try self.parseExpression();
                const end = self.current.end;
                _ = try self.expect(.punct_rbracket);
                base = try self.newNode(base.start, end, .{ .member = .{ .object = base, .property = prop, .computed = true, .optional = false } });
            } else if (allow_calls and self.current.type == .punct_question_dot) {
                try self.advance();
                if (self.current.type == .punct_lbracket) {
                    try self.advance();
                    const prop = try self.parseExpression();
                    const end = self.current.end;
                    _ = try self.expect(.punct_rbracket);
                    base = try self.newNode(base.start, end, .{ .member = .{ .object = base, .property = prop, .computed = true, .optional = true } });
                } else if (self.current.type == .punct_lparen) {
                    const parsed = try self.parseArguments();
                    base = try self.newNode(base.start, parsed.end, .{ .call = .{ .callee = base, .args = parsed.args, .optional = true } });
                } else {
                    const prop = try self.parsePropertyNameAfterDot();
                    base = try self.newNode(base.start, prop.end, .{ .member = .{ .object = base, .property = prop, .computed = false, .optional = true } });
                }
            } else if (allow_calls and self.current.type == .punct_lparen) {
                const parsed = try self.parseArguments();
                base = try self.newNode(base.start, parsed.end, .{ .call = .{ .callee = base, .args = parsed.args, .optional = false } });
            } else {
                break;
            }
        }
        return base;
    }

    fn parseMemberExpressionImpl(self: *Parser, comptime allow_calls: bool) ParseError!*Node {
        var base: *Node = undefined;
        if (self.current.type == .keyword_new) {
            const start = self.current.start;
            try self.advance();
            // `new`'s own callee never claims a trailing '(' as a nested
            // call -- that '(' belongs to this `new`, or to nothing.
            const callee = try self.parseMemberExpressionImpl(false);
            var end = callee.end;
            var args: ?[]const *Node = null;
            if (self.current.type == .punct_lparen) {
                const parsed = try self.parseArguments();
                args = parsed.args;
                end = parsed.end;
            }
            base = try self.newNode(start, end, .{ .new_expr = .{ .callee = callee, .args = args } });
        } else {
            base = try self.parsePrimary();
        }
        return self.parseMemberSuffixes(base, allow_calls);
    }

    fn parseMemberExpression(self: *Parser) ParseError!*Node {
        return self.parseMemberExpressionImpl(true);
    }

    // ===== Primary expressions =====

    fn parsePrimary(self: *Parser) ParseError!*Node {
        const tok = self.current;
        switch (tok.type) {
            .numeric_literal => {
                try self.advance();
                return self.newNode(tok.start, tok.end, .{ .number_literal = tok.numeric_value.? });
            },
            .bigint_literal => {
                try self.advance();
                return self.newNode(tok.start, tok.end, .{ .bigint_literal = tok.owned_value orelse tok.lexeme });
            },
            .string_literal => {
                try self.advance();
                const value = tok.owned_value orelse tok.lexeme[1 .. tok.lexeme.len - 1];
                return self.newNode(tok.start, tok.end, .{ .string_literal = value });
            },
            .keyword_true => {
                try self.advance();
                return self.newNode(tok.start, tok.end, .{ .boolean_literal = true });
            },
            .keyword_false => {
                try self.advance();
                return self.newNode(tok.start, tok.end, .{ .boolean_literal = false });
            },
            .keyword_null => {
                try self.advance();
                return self.newNode(tok.start, tok.end, .{ .null_literal = {} });
            },
            .keyword_this => {
                try self.advance();
                return self.newNode(tok.start, tok.end, .{ .this_expr = {} });
            },
            .identifier => {
                try self.advance();
                return self.newNode(tok.start, tok.end, .{ .identifier = tok.owned_value orelse tok.lexeme });
            },
            .template_no_substitution, .template_head => return self.parseTemplateLiteral(),
            .regex_literal => {
                try self.advance();
                return self.newNode(tok.start, tok.end, .{ .regex_literal = .{ .pattern = tok.lexeme, .flags = tok.regex_flags.? } });
            },
            .punct_lparen => {
                const start = tok.start;
                try self.advance();
                const expr = try self.parseExpression();
                const end = self.current.end;
                _ = try self.expect(.punct_rparen);
                return self.newNode(start, end, .{ .paren = expr });
            },
            .punct_lbracket => return self.parseArrayLiteral(),
            .punct_lbrace => return self.parseObjectLiteral(),
            else => return ParseError.UnexpectedToken,
        }
    }

    fn parseArrayLiteral(self: *Parser) ParseError!*Node {
        const start = self.current.start;
        try self.advance(); // '['
        var elements: std.ArrayList(?*Node) = .empty;
        while (self.current.type != .punct_rbracket) {
            if (self.current.type == .punct_comma) {
                try elements.append(self.arena, null); // elision hole
                try self.advance();
                continue;
            }
            if (self.current.type == .punct_ellipsis) {
                const spread_start = self.current.start;
                try self.advance();
                const arg = try self.parseAssignment();
                try elements.append(self.arena, try self.newNode(spread_start, arg.end, .{ .spread = arg }));
            } else {
                try elements.append(self.arena, try self.parseAssignment());
            }
            if (self.current.type != .punct_rbracket) _ = try self.expect(.punct_comma);
        }
        const end = self.current.end;
        try self.advance();
        return self.newNode(start, end, .{ .array_literal = try elements.toOwnedSlice(self.arena) });
    }

    fn parseObjectLiteral(self: *Parser) ParseError!*Node {
        const start = self.current.start;
        try self.advance(); // '{'
        var elements: std.ArrayList(ast.ObjectLiteralElement) = .empty;
        while (self.current.type != .punct_rbrace) {
            if (self.current.type == .punct_ellipsis) {
                const spread_start = self.current.start;
                try self.advance();
                const arg = try self.parseAssignment();
                try elements.append(self.arena, .{ .spread = try self.newNode(spread_start, arg.end, .{ .spread = arg }) });
            } else {
                try elements.append(self.arena, .{ .property = try self.parseObjectProperty() });
            }
            if (self.current.type != .punct_rbrace) _ = try self.expect(.punct_comma);
        }
        const end = self.current.end;
        // This `}` closes an object literal, not a block -- division, not
        // regex, follows (e.g. `({}) / 2`). Explicit, not inferred: see
        // `regexAllowedAfter`'s doc comment.
        try self.advanceWithContext(.div_allowed);
        return self.newNode(start, end, .{ .object_literal = try elements.toOwnedSlice(self.arena) });
    }

    fn parseObjectProperty(self: *Parser) ParseError!ast.ObjectProperty {
        var computed = false;
        var key: *Node = undefined;

        if (self.current.type == .punct_lbracket) {
            computed = true;
            try self.advance();
            key = try self.parseAssignment();
            _ = try self.expect(.punct_rbracket);
        } else {
            const tok = self.current;
            switch (tok.type) {
                .identifier => {
                    key = try self.newNode(tok.start, tok.end, .{ .identifier = tok.owned_value orelse tok.lexeme });
                    try self.advance();
                },
                .string_literal => {
                    const v = tok.owned_value orelse tok.lexeme[1 .. tok.lexeme.len - 1];
                    key = try self.newNode(tok.start, tok.end, .{ .string_literal = v });
                    try self.advance();
                },
                .numeric_literal => {
                    key = try self.newNode(tok.start, tok.end, .{ .number_literal = tok.numeric_value.? });
                    try self.advance();
                },
                else => {
                    // Reserved words are valid (unquoted) property keys too, e.g. `{ if: 1 }`.
                    if (zlexer.keywordFromLexeme(tok.lexeme) != null) {
                        key = try self.newNode(tok.start, tok.end, .{ .identifier = tok.lexeme });
                        try self.advance();
                    } else return ParseError.UnexpectedToken;
                },
            }
        }

        if (!computed and key.data == .identifier and (self.current.type == .punct_comma or self.current.type == .punct_rbrace)) {
            // Shorthand `{x}` -- value is the same identifier node as the key.
            return .{ .key = key, .value = key, .computed = false, .shorthand = true };
        }
        _ = try self.expect(.punct_colon);
        const value = try self.parseAssignment();
        return .{ .key = key, .value = value, .computed = computed, .shorthand = false };
    }

    // ===== Template literals =====

    fn templateContent(tok: Token) []const u8 {
        if (tok.owned_value) |v| return v;
        var s = tok.lexeme[1..]; // strip leading '`' or '}'
        if (tok.type == .template_head or tok.type == .template_middle) {
            s = s[0 .. s.len - 2]; // strip trailing "${"
        } else {
            s = s[0 .. s.len - 1]; // strip trailing '`'
        }
        return s;
    }

    /// Implements the same lexer/parser cooperation pattern proven by
    /// z-lexer's own tests/template_test.zig TemplateDriver, now as
    /// production code: a real recursive-descent parser gets brace-depth
    /// tracking "for free" through its own call structure -- any '{' opened
    /// while parsing the substitution expression (e.g. an object literal)
    /// is already closed by its own parseObjectLiteral() call before control
    /// returns here, so whatever '}' `self.current` holds when
    /// parseExpression() returns must be this substitution's own closing
    /// delimiter.
    fn parseTemplateLiteral(self: *Parser) ParseError!*Node {
        const start = self.current.start;
        var quasis: std.ArrayList([]const u8) = .empty;
        var expressions: std.ArrayList(*Node) = .empty;

        var tok = self.current;
        try quasis.append(self.arena, templateContent(tok));

        if (tok.type == .template_no_substitution) {
            const end = tok.end;
            try self.advance();
            return self.newNode(start, end, .{ .template_literal = .{
                .quasis = try quasis.toOwnedSlice(self.arena),
                .expressions = try expressions.toOwnedSlice(self.arena),
            } });
        }

        self.current = try self.lexer.nextToken(.regex_allowed); // enter the first substitution
        while (true) {
            try expressions.append(self.arena, try self.parseExpression());

            if (self.current.type != .punct_rbrace) return ParseError.UnexpectedToken;
            self.lexer.pos = self.current.start;
            self.lexer.line = self.current.line;
            self.lexer.column = self.current.column;
            tok = try self.lexer.continueTemplate();
            try quasis.append(self.arena, templateContent(tok));

            if (tok.type == .template_tail) {
                const end = tok.end;
                const ctx: LexContext = if (regexAllowedAfter(tok.type)) .regex_allowed else .div_allowed;
                self.current = try self.lexer.nextToken(ctx);
                return self.newNode(start, end, .{ .template_literal = .{
                    .quasis = try quasis.toOwnedSlice(self.arena),
                    .expressions = try expressions.toOwnedSlice(self.arena),
                } });
            }
            self.current = try self.lexer.nextToken(.regex_allowed); // template_middle: another substitution follows
        }
    }
};
