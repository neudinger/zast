//! Shared construction of a container body from borrowed member descriptions.
//!
//! Prefer `EnumDeclaration`, `UnionDeclaration`, or `StructDeclaration` for validation.
//! The caller emits the complete header, including any parenthesized argument;
//! this helper emits `{ members }` and creates the container's node layout.
//! It does not validate members, emit a semicolon, or register a root declaration.
//!
//! ## Naming and composition
//!
//! `Container` follows Zig's `container_decl*` and `tagged_union*` AST families
//! for type members. A `Block` belongs to the separate `block*` family and holds
//! ordered statements and local declarations. Block-structured scoping does not
//! make these constructs interchangeable; their syntax and node layouts differ.
//!
//! A function declaration can be a container member, while its body is a block:
//!
//! ```text
//! Container -> FunctionDeclaration -> Block -> statements
//! ```
//!
//! An if or loop node owns its condition/inputs and branch/body expressions.
//! Such a body can be a block or a single expression, so it should not use this
//! member emitter. `Block` handles statements separately.
//!
//! `emit` accepts the field list below; `emitMembers` also accepts descriptions
//! such as `StructDeclaration.Member`, which compose fields and declarations.
//!
//! Share node-list allocation and range storage when duplication appears, but
//! keep each construct's AST tags, punctuation, and validation distinct. Use
//! `body` as a property name; a universal `Body` builder would still need those
//! separate rules. This is the project's design choice, not a naming standard.
//! See [namespaces](https://ziglang.org/documentation/0.17.0/#Namespace)
//! and [grammar](https://ziglang.org/documentation/0.17.0/#Grammar).
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
//! Import this struct with `const Container = @import("zast").Container;`.
//! Examples assume `AstContext = @import("zast").AstContext`, an `allocator`, and
//! `var context: AstContext = .{};` with node zero reserved as `.root`.
//! `AstContext` contains a complete example of finalizing and rendering it.
//!
//! ## Example
//!
//! ```zig
//! const enum_token = try context.token(allocator, .keyword_enum, null);
//! const enum_body: Container = .{
//!     .main_token = enum_token,
//!     .fields = &.{ .{ .name = "unknown" }, .{ .name = "ok" } },
//! };
//! const enum_node = try enum_body.emit(allocator, .plain, &context);
//! // Attach enum_node to an enclosing construct.
//! ```
//!
//! ## Expected output
//!
//! Formatted expression inside a completed AST (no semicolon):
//!
//! ```zig
//! enum {
//!     unknown,
//!     ok,
//! }
//! ```

const std = @import("std");
const AstContext = @import("AstContext.zig");
const ChildNodes = @import("ChildNodes.zig");
const Field = @import("Field.zig");
/// Standard AST node and token definitions used by this emitter.
const Ast = std.zig.Ast;
/// This file is the component struct; descriptions own no allocations.
const Self = @This();

/// Compile-time selection of the standard AST's container node family.
pub const Kind = enum {
    /// An enum, struct, untagged union, or union with a named enum tag.
    plain,
    /// A union whose header explicitly uses `enum` to generate its tag type.
    tagged_union,
};

/// Token of the container keyword (`enum`, `union`, or `struct`).
main_token: Ast.TokenIndex,
/// Node in this context for a header argument such as `u8` in `enum(u8)` or
/// `union(enum(u8))`, or `Tag` in `union(Tag)`. Null means no argument node.
argument_node: ?Ast.Node.Index = null,
/// Fields emitted by `emit`, in order. `emitMembers` uses its supplied list instead.
fields: []const Field = &.{},
/// Optional final field, commonly the non-exhaustive enum catch-all `_`.
trailing_field: ?Field = null,

/// Emit braces and fields, returning an unregistered container expression.
///
/// - `.plain` covers ordinary containers, including `enum(T)` and `union(Tag)`.
/// - `.tagged_union` covers `union(enum)` and `union(enum(T))`.
///
/// `kind` is comptime-known and must match the already emitted header.
/// Member slots are reserved before children can grow `extra_data`; node
/// layouts and trailing-comma variants are selected for the resulting body.
///
/// ### Errors
///
/// Uses the context's allocator; allocation and child type errors propagate
/// and may leave partial output.
pub fn emit(
    container: Self,
    allocator: std.mem.Allocator,
    comptime kind: Kind,
    context: *AstContext,
) anyerror!Ast.Node.Index {
    return container.emitMembers(allocator, kind, container.fields, true, context);
}

/// Emit a mixed member list using each description's `emit(allocator, context)`
/// method, which returns an unregistered node. No runtime type erasure is used.
///
/// The caller emits the header and validates membership/order before calling.
/// `members` must be an array, array pointer, or slice with elements implementing
/// `emit(allocator, context) !Ast.Node.Index`. Pass an `ArrayList`'s `.items` slice.
/// `container.fields` is ignored here; `container.trailing_field` is still appended.
///
/// - `trailing_separator` is true when the last member ends in a comma or
///   semicolon, and false for a function body ending in `}`.
/// - A `trailing_field` always ends with a comma.
/// - Empty lists select the empty container layout.
///
/// Slots are reserved before child emission, so nested `extra_data` stays out
/// of the member range.
///
/// ### Errors
///
/// Allocation and child errors propagate and may leave partial output.
///
/// ### Example
///
/// With the module's allocator and fresh-context setup, these members are valid
/// for a struct; this helper does not perform `StructDeclaration`'s validation:
///
/// ```zig
/// const StructDeclaration = @import("zast").StructDeclaration;
/// const members = [_]StructDeclaration.Member{
///     .{ .declaration = .{
///         .name = "default_count",
///         .declaration = .{ .value = .{ .integer_literal = "0" } },
///     } },
///     .{ .field = .{
///         .name = "count", .type_expression = .{ .identifier = "u32" },
///         .value = .{ .identifier = "default_count" },
///     } },
/// };
/// const struct_token = try context.token(allocator, .keyword_struct, null);
/// const container: Container = .{ .main_token = struct_token };
/// const struct_node = try container.emitMembers(allocator, .plain, &members, true, &context);
/// // Attach struct_node to an enclosing declaration or type expression.
/// ```
///
/// ### Expected output
///
/// Formatted type expression inside a completed AST, without a semicolon:
///
/// ```zig
/// struct {
///     const default_count = 0;
///     count: u32 = default_count,
/// }
/// ```
pub fn emitMembers(
    container: Self,
    allocator: std.mem.Allocator,
    comptime kind: Kind,
    members: anytype,
    trailing_separator: bool,
    context: *AstContext,
) !Ast.Node.Index {
    const base_tag: Ast.Node.Tag, const argument_tag: Ast.Node.Tag = comptime switch (kind) {
        .plain => .{ .container_decl, .container_decl_arg },
        .tagged_union => .{ .tagged_union, .tagged_union_enum_tag },
    };
    const member_count = members.len + @intFromBool(container.trailing_field != null);
    const ends_with_separator = container.trailing_field != null or (members.len != 0 and trailing_separator);
    var children = try ChildNodes.init(allocator, context, member_count, 0);

    _ = try context.token(allocator, .l_brace, null);
    for (members, 0..) |member_description, member_index| {
        children.set(context, member_index, try member_description.emit(allocator, context));
    }
    if (container.trailing_field) |field_description| {
        children.set(context, members.len, try field_description.emit(allocator, context));
    }
    _ = try context.token(allocator, .r_brace, null);

    if (container.argument_node == null and member_count == 0) {
        const two_tag: Ast.Node.Tag = comptime @field(Ast.Node.Tag, @tagName(base_tag) ++ "_two");
        return context.addNode(allocator, two_tag, container.main_token, .{
            .opt_node_and_opt_node = .{ .none, .none },
        });
    }

    if (container.argument_node) |argument_node| {
        const range_index = try children.appendRange(allocator, context);
        return context.addNode(allocator, trailingTag(argument_tag, ends_with_separator), container.main_token, .{
            .node_and_extra = .{ argument_node, range_index },
        });
    }
    return context.addNode(allocator, trailingTag(base_tag, ends_with_separator), container.main_token, .{
        .extra_range = children.range,
    });
}

/// Select a node family's trailing-separator variant using a compile-time tag name.
/// The base tag must have a corresponding `_trailing` variant in `std.zig.Ast`.
fn trailingTag(comptime base_tag: Ast.Node.Tag, trailing: bool) Ast.Node.Tag {
    return if (trailing)
        @field(Ast.Node.Tag, @tagName(base_tag) ++ "_trailing")
    else
        base_tag;
}
