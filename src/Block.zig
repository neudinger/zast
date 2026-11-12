//! An ordered, borrowed statement list enclosed in `{ ... }`.
//!
//! Used for function bodies and nested scopes; `Container` handles type members.
//! No allocator is stored and no deinit is needed on the description itself.
//! The supported statements are the `Block.Statement` variants defined below.
//! Labels, conditionals, loops, and `defer` statements are not represented by this API.
//!
//! ## Ownership and errors
//!
//! Descriptions borrow their strings and child descriptions until emission ends.
//! Emission copies spellings into an `AstContext` and allocates its nodes with the
//! supplied allocator. No description here needs its own `deinit`.
//!
//! Allocating emitters may leave partial syntax on failure; discard that output.
//! Spellings and semantic validity remain the caller's responsibility.
//!
//! ## Usage
//!
//! Import this struct with `const Block = @import("zast").Block;`.
//! Examples assume `AstContext = @import("zast").AstContext`, an `allocator`, and
//! `var context: AstContext = .{};` with node zero reserved as `.root`.
//! `AstContext` contains a complete example of finalizing and rendering it.
//!
//! ## Example
//!
//! ```zig
//! const statements = [_]Block.Statement{
//!     .{ .declaration = .{
//!         .name = "answer",
//!         .declaration = .{ .value = .{ .integer_literal = "42" } },
//!     } },
//!     .{ .return_value = .{ .identifier = "answer" } },
//! };
//! const body: Block = .{ .statements = &statements };
//! const body_node = try body.emit(allocator, &context);
//! // Attach body_node to a function declaration.
//! ```
//!
//! ## Expected output
//!
//! Formatted function body:
//!
//! ```zig
//! {
//!     const answer = 42;
//!     return answer;
//! }
//! ```

const std = @import("std");
const AstContext = @import("AstContext.zig");
const ChildNodes = @import("ChildNodes.zig");
const Expression = @import("Expression.zig").Expression;
const Declaration = @import("Declaration.zig");
/// Standard AST node and token definitions used by this emitter.
const Ast = std.zig.Ast;
/// This file is the component struct; descriptions own no allocations.
const Self = @This();

/// A borrowed statement description for a `Block`, not a container field.
///
/// Expressions, declarations, assignments, and returns emit their semicolon;
/// a nested block emits its own braces without a following semicolon.
/// Child descriptions must remain valid until emission finishes and be acyclic.
pub const Statement = union(enum) {
    /// An expression used as a statement; Zig must permit its result to be ignored.
    expression: Expression,
    /// A named local `const`/`var`. Its initializer and annotation reuse `Declaration`.
    declaration: struct {
        /// Complete identifier spelling for the local binding.
        name: []const u8,
        /// Binding kind, optional type annotation, and required initializer.
        declaration: Declaration,
    },
    /// `target = value;`. Assignment is a statement, not a value expression.
    ///
    /// Zig checks that `target` is writable, or `_` to discard the value.
    /// Compound and destructuring assignments are not supported here.
    ///
    /// Example: `.{ .assignment = .{ .target = .{ .identifier = "count" },
    /// .value = .{ .integer_literal = "42" } } }` emits `count = 42;`.
    assignment: struct {
        /// Writable expression, such as a local variable or a field access.
        target: Expression,
        /// New value, which can include a call or a `try` expression.
        value: Expression,
    },
    /// `return expression;`, or `return;` when the payload is null.
    return_value: ?Expression,
    /// A borrowed nested statement block. It is not registered as a root member.
    block: *const Self,

    /// Append this statement and return its node for the enclosing block.
    ///
    /// This performs no name resolution, return-type checks, or reachability checks.
    ///
    /// ### Errors
    ///
    /// Uses the supplied allocator. Allocation and child type errors propagate
    /// and may leave partial output.
    pub fn emit(statement: Statement, allocator: std.mem.Allocator, context: *AstContext) anyerror!Ast.Node.Index {
        const statement_node = switch (statement) {
            .expression => |expression| try expression.emit(allocator, context),
            .declaration => |binding| return binding.declaration.emitNode(allocator, context, binding.name, .private),
            .assignment => |assignment| assigned: {
                const target_node = try assignment.target.emit(allocator, context);
                const equal_token = try context.token(allocator, .equal, null);
                const value_node = try assignment.value.emit(allocator, context);
                break :assigned try context.addNode(allocator, .assign, equal_token, .{
                    .node_and_node = .{ target_node, value_node },
                });
            },
            .return_value => |value| returned: {
                const return_token = try context.token(allocator, .keyword_return, null);
                const value_node = try Expression.emitOptional(value, allocator, context, &.{}, &.{});
                break :returned try context.addNode(allocator, .@"return", return_token, .{ .opt_node = value_node });
            },
            .block => |body| return body.emit(allocator, context),
        };
        _ = try context.token(allocator, .semicolon, null);
        return statement_node;
    }
};

/// Borrowed statements in source order, including nested child descriptions.
statements: []const Statement = &.{},

/// Emit braces and statements, returning a block node without registration.
///
/// The caller supplies the function prototype or enclosing statement list and
/// attaches this node there. A block is not a container member or root declaration.
///
/// Zero through two statements use inline node slots; longer blocks reserve
/// a contiguous `extra_data` range before children can grow that buffer.
/// The last statement determines the AST's trailing-semicolon variant.
///
/// ### Errors
///
/// Uses the supplied allocator; allocation and child type errors propagate
/// and may leave partial output.
pub fn emit(body: Self, allocator: std.mem.Allocator, context: *AstContext) anyerror!Ast.Node.Index {
    var children = try ChildNodes.init(allocator, context, body.statements.len, 2);
    const opening_token = try context.token(allocator, .l_brace, null);
    for (body.statements, 0..) |statement, statement_index| {
        children.set(context, statement_index, try statement.emit(allocator, context));
    }
    _ = try context.token(allocator, .r_brace, null);
    const trailing_semicolon = body.statements.len != 0 and
        body.statements[body.statements.len - 1] != .block;
    if (!children.uses_extra) {
        return context.addNode(allocator, if (trailing_semicolon) .block_two_semicolon else .block_two, opening_token, .{
            .opt_node_and_opt_node = .{ children.inline_nodes[0], children.inline_nodes[1] },
        });
    }
    return context.addNode(allocator, if (trailing_semicolon) .block_semicolon else .block, opening_token, .{
        .extra_range = children.range,
    });
}
