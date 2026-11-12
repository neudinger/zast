//! A borrowed description of a named `const` or `var` with an initializer.
//!
//! - For a type alias, put a type expression in `value`: `const Bytes = []const u8;`.
//! - For a typed value, put its annotation in `type_expression` and its initializer
//!   in `value`: `var counter: u32 = 0;`.
//!
//! Use `Field` for a container field such as `counter: u32 = 0,`. A declaration
//! always requires an initializer; its name and visibility are supplied at emission,
//! so the same description can be emitted with different names.
//!
//! ## Ownership and errors
//!
//! Descriptions borrow their strings and child descriptions until emission ends.
//! Emission copies spellings into an `AstContext` and allocates its nodes with the
//! supplied allocator. This descriptor owns no allocations and needs no `deinit`.
//!
//! Allocating emitters may leave partial syntax on failure; discard that output.
//! Spellings and semantic validity remain the caller's responsibility.
//!
//! ## Usage
//!
//! Import this struct with `const Declaration = @import("zast").Declaration;`.
//! Its example also uses `const Expression = @import("zast").Expression;`.
//! Examples assume `AstContext = @import("zast").AstContext`, an `allocator`, and
//! `var context: AstContext = .{};` with node zero reserved as `.root`.
//! `AstContext` contains a complete example of finalizing and rendering it.
//!
//! ## Example
//!
//! ```zig
//! const counter: Declaration = .{
//!     .kind = .variable,
//!     .type_expression = .{ .identifier = "u32" },
//!     .value = .{ .integer_literal = "0" },
//! };
//! try counter.emit(allocator, &context, "counter", .private);
//!
//! const byte_type: Expression = .{ .identifier = "u8" };
//! const bytes_alias: Declaration = .{
//!     .value = .{ .slice_type = .{
//!         .child_type = &byte_type,
//!         .is_const = true,
//!     } },
//! };
//! try bytes_alias.emit(allocator, &context, "Bytes", .public);
//! ```
//!
//! ## Expected output
//!
//! Formatted declarations:
//!
//! ```zig
//! var counter: u32 = 0;
//! pub const Bytes = []const u8;
//! ```

const std = @import("std");
const AstContext = @import("AstContext.zig");
const Expression = @import("Expression.zig").Expression;
/// Standard AST node and token definitions used by this emitter.
const Ast = std.zig.Ast;
/// This file is the component struct; descriptions own no allocations.
const Self = @This();

/// Visibility of a named declaration. This controls its optional `pub` token.
pub const Visibility = enum {
    /// Omit `pub` on a `const`, `var`, or function declaration.
    private,
    /// Include `pub` on a `const`, `var`, or function declaration.
    public,
};

/// `.constant` writes `const`; `.variable` writes `var` for a mutable binding.
kind: enum {
    /// An immutable `const` binding, including a type alias.
    constant,
    /// A reassignable `var` binding.
    variable,
} = .constant,
/// Optional `: T` annotation. Null lets Zig infer the type from `value`.
type_expression: ?Expression = null,
/// Required initializer after `=`; may represent either a value or a type.
value: Expression,

/// Emit `[pub] const/var name[: type] = value;` and register its root node.
///
/// `name` must already be a valid identifier spelling; it is not escaped.
/// Reserve the context's root first. Use the context's allocator and finalize
/// its declaration range before rendering. Does not compile or type-check.
///
/// ### Errors
///
/// Allocation and child type errors propagate; partial output is retained.
pub fn emit(
    declaration: Self,
    allocator: std.mem.Allocator,
    context: *AstContext,
    name: []const u8,
    visibility: Visibility,
) !void {
    const declaration_node = try declaration.emitNode(allocator, context, name, visibility);
    try context.declarations.append(allocator, @backingInt(declaration_node));
}

/// Emit the declaration and return its node without registering it at root.
///
/// Blocks use this for local bindings; container emitters can attach it as a
/// member. Use `.private` inside blocks. Names and errors follow `emit`.
///
/// ### Example
///
/// With `counter` from the module example and a fresh context:
///
/// ```zig
/// const binding_node = try counter.emitNode(allocator, &context, "counter", .private);
/// // Attach binding_node to a block or container member list.
/// ```
///
/// ### Expected output
///
/// Formatted binding inside its enclosing construct:
///
/// ```zig
/// var counter: u32 = 0;
/// ```
pub fn emitNode(
    declaration: Self,
    allocator: std.mem.Allocator,
    context: *AstContext,
    name: []const u8,
    visibility: Visibility,
) !Ast.Node.Index {
    if (visibility == .public) _ = try context.token(allocator, .keyword_pub, null);
    const keyword: std.zig.Token.Tag = if (declaration.kind == .constant) .keyword_const else .keyword_var;
    const declaration_token = try context.token(allocator, keyword, null);
    _ = try context.token(allocator, .identifier, name);

    const type_node = try Expression.emitOptional(declaration.type_expression, allocator, context, &.{.colon}, &.{});
    _ = try context.token(allocator, .equal, null);
    const value_node = try declaration.value.emit(allocator, context);
    _ = try context.token(allocator, .semicolon, null);

    return context.addNode(allocator, .simple_var_decl, declaration_token, .{
        .opt_node_and_opt_node = .{ type_node, value_node.toOptional() },
    });
}

/// Emit `[pub] const name = type;` and register its declaration node at the root.
///
/// Prefer the description's public `emit` method, which performs its own
/// validation before any writes.
///
/// ### Usage
///
/// `type_description` must provide
/// `emitType(allocator, context) !std.zig.Ast.Node.Index`, as enum, union, struct,
/// and function descriptions do. That method emits an anonymous type in the same
/// context. For a function description this creates a type alias, not a definition.
///
/// Validate the description and reserve the root before calling: this helper
/// writes the declaration prefix before invoking `emitType`. Names must be valid
/// identifier spellings. The context allocator is required.
///
/// ### Errors
///
/// Errors from the type emitter propagate and may leave partial syntax.
///
/// ### Example
///
/// This empty struct has no members to validate:
///
/// ```zig
/// const StructDeclaration = @import("zast").StructDeclaration;
/// const empty: StructDeclaration = .{};
/// try Declaration.emitTypeDeclaration(allocator, &context, &empty, "Empty", .public);
/// ```
///
/// ### Expected output
///
/// ```zig
/// pub const Empty = struct {};
/// ```
pub fn emitTypeDeclaration(
    allocator: std.mem.Allocator,
    context: *AstContext,
    type_description: anytype,
    name: []const u8,
    visibility: Visibility,
) !void {
    if (visibility == .public) _ = try context.token(allocator, .keyword_pub, null);
    const declaration_token = try context.token(allocator, .keyword_const, null);
    _ = try context.token(allocator, .identifier, name);
    _ = try context.token(allocator, .equal, null);
    const type_node = try type_description.emitType(allocator, context);
    _ = try context.token(allocator, .semicolon, null);

    const declaration_node = try context.addNode(allocator, .simple_var_decl, declaration_token, .{
        .opt_node_and_opt_node = .{ .none, type_node.toOptional() },
    });
    try context.declarations.append(allocator, @backingInt(declaration_node));
}
