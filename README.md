# Z-Parser

[![Zig Version](https://img.shields.io/badge/zig-0.16-orange.svg)](https://ziglang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

ECMAScript **expression parser** (ECMA-262 §13) in Zig 0.16 — the second repo of the JS engine, consuming [z-lexer](https://github.com/carlos-sweb/z-lexer)'s token stream. Part of the [z-*](https://github.com/carlos-sweb) micro-library family.

## Scope: expressions only

The full ECMA-262 grammar (expressions + statements/declarations + functions/arrow functions + classes + destructuring + modules) is too large for one repo — this mirrors the spec's own split (§13 Expressions vs. §14 Statements/Declarations vs. §15 Functions/Classes). This repo covers **§13 in full**, with one deliberate omission: expressions whose value *is* a function (arrow functions, `function` expressions, class expressions) need parameter/body grammar that reaches into §14/§15, and are left for the next phase. See [Known gaps](#known-gaps-deferred-to-future-phases).

No dependency on [z-value](https://github.com/carlos-sweb/z-value): the AST holds raw parsed data (`f64`, `[]const u8`), not `JSValue` — that connection is the interpreter's job, not the parser's, same independence [z-lexer](https://github.com/carlos-sweb/z-lexer) already has from the rest of the ecosystem.

## Design

- **Arena-allocated AST, not `Rc`-boxed**: unlike `JSValue` (shared, independently-lived runtime values that genuinely need `Rc(T)`), an AST is built once during parsing and walked/discarded as a unit — there's no sharing to manage. One `std.heap.ArenaAllocator` per parse frees the whole tree (and the lexer's `owned_value` allocations, which reuse the same arena) in a single `deinit()`.
- **Recursive descent + precedence climbing**: each precedence level (comma → assignment → conditional → nullish/logical → bitwise → equality → relational → shift → additive → multiplicative → exponentiation → unary → postfix → member/call/new → primary) is its own small function, chained top-down. The binary-operator levels that share the same left-associative shape (bitwise/equality/relational/shift/additive/multiplicative) go through one generic `parseBinaryLevel(opFor, next)` helper parameterized by a comptime operator table and the next-tighter level.
- **Two real spec restrictions, not just precedence**:
  - `??` cannot be mixed directly with `&&`/`||` without parens (`a ?? b || c` is a `SyntaxError`) — `parseShortCircuit()` commits to one family after the first operand and errors if the other appears at the same level.
  - The left operand of `**` may not be an un-parenthesized unary expression (`-2 ** 2` is a `SyntaxError`, `(-2) ** 2` isn't) — enforced by checking the operand's `NodeData` tag, which is exactly why parenthesization is tracked as its own `.paren` node instead of being collapsed away during parsing.
- **`new`/`MemberExpression`/`CallExpression` interplay, handled per spec**: `new Foo.Bar()` is `new (Foo.Bar)()`; `new Foo` (no parens) is distinct from `new Foo()`; `new new Foo()()` is `new (new Foo())()`. One suffix-chaining loop (`parseMemberSuffixes`) handles `.`/`[]`/`()`/`?.` uniformly for both plain member access and call chains; it's parameterized by a comptime `allow_calls` flag so a `new` callee's own suffix scan stops before an unclaimed `(`, leaving it for `new` to claim as its constructor arguments (or for nothing, if there isn't one).
- **Lexer cooperation is real, not a stub**: this is the actual consumer [z-lexer](https://github.com/carlos-sweb/z-lexer)'s `LexContext`/`continueTemplate()` were built for.
  - **Regex vs. division**: `regexAllowedAfter(prev_token_type)` decides `.regex_allowed` vs. `.div_allowed` for every token fetch, based on whether the previous token could end a complete expression.
  - **Template literals**: a real recursive-descent parser gets `${...}` brace-depth tracking *for free* through its own call structure — any `{` opened while parsing a substitution (e.g. an object literal) is closed by its own `parseObjectLiteral()` call before control returns, so whatever `}` remains when the substitution's expression finishes parsing must be the template's own closing delimiter. `parseTemplateLiteral()` rewinds the lexer to that token's `start`/`line`/`column` and calls `continueTemplate()` — the same pattern z-lexer's own `tests/template_test.zig` proved with a hand-written driver, now as production code with no manual depth stack needed.

## Known gaps (deferred to future phases)

- **Functions/arrow functions**: need parameter-list + statement-body grammar; arrow functions additionally need a "cover grammar" (`(a, b)` parses as a possible grouped/sequence expression first, reinterpreted as parameters if `=>` follows) — real, self-contained work for its own phase.
- **Statements/declarations** (`if`/`for`/`while`/`var`/`let`/`const`/blocks): natural next phase after functions, since function bodies *are* statement lists.
- **Object literal method/getter/setter shorthand** (`{ method() {}, get x() {} }`): needs function bodies, same as above. This phase's object literals cover `key: value`, shorthand `{x}`, computed `{[k]: v}`, and spread `{...obj}` only.
- **Destructuring patterns** (`[a,b] = arr`, `{x,y} = obj`, and the same in parameters): `parseAssignment`'s target validation only accepts an identifier or member expression; an array/object literal as the LHS of `=` is `error.InvalidAssignmentTarget` for now.
- **Classes, `super`, generators, `async`/`await`, modules** (`import`/`export`).
- Template literals expose only the cooked value (`TV`), not the raw value (`TRV`) tagged templates need for `.raw` — not needed until tagged templates exist at the parser/interpreter level.

## Usage

```zig
const zparser = @import("zparser");

var arena_state = std.heap.ArenaAllocator.init(allocator);
defer arena_state.deinit();

var parser = try zparser.Parser.init(arena_state.allocator(), "1 + 2 * 3");
const ast = try parser.parseExpression();
// ast.data == .binary, ast.data.binary.op == .add, ...
```

## Testing

```bash
zig build test
```

## License

MIT
