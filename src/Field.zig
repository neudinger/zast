//! A borrowed container field shared by enum, union, and other emitters.
//!
//! - An enum tag uses `.name = "ok", .value = .{ .integer_literal = "1" }`.
//! - A union payload uses `.name = "count", .type_expression = .{ .identifier = "u32" }`.
//! - A struct field can use both a type and a default value.
//!
//! `null` omits that part: both null emits `name,`, a type emits `name: T,`,
//! and a value adds `= expression` before the comma. The enclosing generator
//! decides which forms are valid for its container; this struct does not
//! validate those combinations.
//!
//! Use `Declaration` for a `const`/`var` binding: a field has no binding keyword
//! or visibility and ends in a comma. A union field describes a payload's type;
//! leave `value` null and use `Expression.struct_init` to construct a payload value.
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
//! Import this struct with `const Field = @import("zast").Field;`.
//! The example also uses `EnumDeclaration`, `UnionDeclaration`, and
//! `StructDeclaration` from `@import("zast")`.
//! Examples assume `AstContext = @import("zast").AstContext`, an `allocator`, and
//! `var context: AstContext = .{};` with node zero reserved as `.root`.
//! `AstContext` contains a complete example of finalizing and rendering it.
//!
//! ## Example
//!
//! ```zig
//! const status_fields = [_]Field{
//!     .{ .name = "pending" },
//!     .{ .name = "ok", .value = .{ .integer_literal = "1" } },
//! };
//! const status: EnumDeclaration = .{
//!     .backing_type = "u8",
//!     .fields = &status_fields,
//! };
//! try status.emit(allocator, &context, "Status", .public);
//!
//! const payload_fields = [_]Field{
//!     .{ .name = "none" },
//!     .{ .name = "count", .type_expression = .{ .identifier = "u32" } },
//! };
//! const payload: UnionDeclaration = .{
//!     .tag_type = .inferred,
//!     .fields = &payload_fields,
//! };
//! try payload.emit(allocator, &context, "Payload", .public);
//!
//! const count: Field = .{
//!     .name = "count",
//!     .type_expression = .{ .identifier = "u32" },
//!     .value = .{ .integer_literal = "0" },
//! };
//! const counter: StructDeclaration = .{
//!     .members = &.{.{ .field = count }},
//! };
//! try counter.emit(allocator, &context, "Counter", .public);
//! ```
//!
//! ## Expected output
//!
//! Formatted declarations containing bare fields, an explicit enum tag value,
//! a union payload type, and a struct field with a default value:
//!
//! ```zig
//! pub const Status = enum(u8) {
//!     pending,
//!     ok = 1,
//! };
//! pub const Payload = union(enum) {
//!     none,
//!     count: u32,
//! };
//! pub const Counter = struct {
//!     count: u32 = 0,
//! };
//! ```

const std = @import("std");
const AstContext = @import("AstContext.zig");
const Expression = @import("Expression.zig").Expression;
/// This file is the component struct; descriptions own no allocations.
const Self = @This();

/// Complete Zig identifier spelling, borrowed until emission finishes.
name: []const u8,
/// Optional `: T`; enum fields should leave this `null`.
type_expression: ?Expression = null,
/// Optional `= expression`; enum tag value or a struct field's default value.
value: ?Expression = null,

/// Append a field's tokens and node, including its trailing comma.
///
/// The caller has already emitted the container header and opening `{`.
/// Returns a node for that container's member list; no root registration.
///
/// ### Errors
///
/// Uses the context's allocator; allocation and child type errors propagate
/// and may leave partial output on failure.
pub fn emit(field_description: Self, allocator: std.mem.Allocator, context: *AstContext) anyerror!std.zig.Ast.Node.Index {
    const field_token = try context.token(allocator, .identifier, field_description.name);
    const type_node = if (field_description.type_expression) |type_expression| field_type: {
        _ = try context.token(allocator, .colon, null);
        break :field_type try type_expression.emit(allocator, context);
    } else try context.addNode(allocator, .identifier, field_token, undefined);

    const value_node = try Expression.emitOptional(field_description.value, allocator, context, &.{.equal}, &.{});

    const field_node = try context.addNode(allocator, .container_field_init, field_token, .{
        .node_and_opt_node = .{ type_node, value_node },
    });
    _ = try context.token(allocator, .comma, null);
    return field_node;
}
