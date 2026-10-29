//! Borrowed enum description with separate anonymous and named emission.
//!
//! ## Ownership
//!
//! `init` allocates only the descriptor; its fields are a borrowed slice, not a
//! copied or growable list. Use a parent arena for the descriptor, then release
//! the arena after emission. Fields, names, backing-type spelling, and recursive
//! expressions must remain valid until emission finishes. There is no per-enum
//! `deinit`. The allocator passed to `emit`/`emitType` owns the AST buffers and
//! may differ from the arena allocator used by `init`.
//! A value literal such as `const status: EnumDeclaration = .{ .backing_type = null };`
//! needs no descriptor allocation. If `init` uses a non-arena allocator, release
//! its descriptor with that allocator's `destroy` after emission.
//!
//! ## Usage
//!
//! Examples assume imports of `std`, `AstContext`, `Field`, and `EnumDeclaration`,
//! plus an `allocator` and a context whose root node has already been reserved.
//! Import generator types through `@import("zast")`, for example
//! `const EnumDeclaration = @import("zast").EnumDeclaration;`.
//! Later constructor examples assume a parent arena's `builder_allocator`.
//! Emission examples are alternatives in fresh contexts; references to `enum_decl`
//! reuse its setup below before the first `emit` call.
//! `AstContext` shows the complete initialization, rendering, and cleanup.
//!
//! ## Example
//!
//! ```zig
//! var arena = std.heap.ArenaAllocator.init(allocator);
//! defer arena.deinit();
//! const builder_allocator = arena.allocator();
//! const status_fields = [_]Field{
//!     .{ .name = "unknown", .value = .{ .integer_literal = "0" } },
//!     .{ .name = "ok", .value = .{ .integer_literal = "1" } },
//!     .{ .name = "warning", .value = .{ .integer_literal = "2" } },
//! };
//! const enum_decl = try EnumDeclaration.init(
//!     builder_allocator, "u8", true, &status_fields,
//! );
//! try enum_decl.emit(allocator, &context, "Status", .public);
//! ```
//!
//! ## Expected output
//!
//! ```zig
//! pub const Status = enum(u8) {
//!     unknown = 0,
//!     ok = 1,
//!     warning = 2,
//!     _,
//! };
//! ```

const std = @import("std");
const AstContext = @import("AstContext.zig");
const InitResult = @import("InitResult.zig").InitResult;

const Container = @import("Container.zig");
const Declaration = @import("Declaration.zig");
/// Shared named-declaration visibility; `.public` emits the `pub` keyword.
const Visibility = Declaration.Visibility;
/// Shared field description; enums use its name and optional value only.
const Field = @import("Field.zig");
/// Reusable value expressions accepted by an enum field's `value` member.
const Expression = @import("Expression.zig").Expression;

/// This file's struct type; allocated descriptors are returned by `init`.
const Self = @This();

/// Null emits `enum { ... }`; otherwise emit `enum(T) { ... }` using this single
/// identifier spelling, such as `u8` or `i16`. Compound type syntax is unsupported.
backing_type: ?[]const u8,
/// Borrowed fields in source order. Leave each field's `type_expression` null.
/// Reassignable through a mutable descriptor; not copied or owned by `init`.
fields: []const Field = &.{},
/// Append a final `_,` catch-all. Requires an explicit backing type; do not also
/// supply `_` in `fields`. Zig still checks whether unnamed backing values remain.
non_exhaustive: bool = false,

/// Allocate an enum descriptor without emitting or validating any Zig syntax.
///
/// ### Ownership
///
/// Supply a parent arena's allocator; only the descriptor is allocated here.
/// `fields` accepts literal `null` or a value coercible to `[]const Field`,
/// such as `&field_array`, `field_slice`, or `field_list.items`. No copy is made:
/// do not free or reallocate the backing field storage before emission finishes.
/// Declare supplied arrays as `[_]Field`; `anytype` does not infer that
/// element type for a nonempty anonymous `&.{ ... }` argument.
///
/// - Literal `null` creates an empty mutable `*EnumDeclaration`; assign `.fields` later.
/// - A field slice or array pointer, even empty, returns a `*const EnumDeclaration`.
///
/// This is shallow constness: another alias can still change the borrowed data.
///
/// ### Errors
///
/// A `null` `backing_type` selects an inferred enum, which requires implicit values
/// and no catch-all. `emit`/`emitType` report `MissingBackingType` for violations;
/// `init` itself reports only allocation failure. Other Zig validity checks, such
/// as duplicate names or values outside the backing type, remain with Zig.
/// Field type annotations are not validated here; leave them null for enums.
///
/// ### Example
///
/// ```zig
/// const inferred_fields = [_]Field{
///     .{ .name = "unknown" },
///     .{ .name = "ok" },
/// };
/// const inferred_enum = try EnumDeclaration.init(
///     builder_allocator, null, false, &inferred_fields,
/// ); // *const EnumDeclaration
/// try inferred_enum.emit(allocator, &context, "InferredStatus", .public);
///
/// const deferred_enum = try EnumDeclaration.init(
///     builder_allocator, null, false, null,
/// ); // *EnumDeclaration, even though the pointer binding is const
/// deferred_enum.fields = &.{ .{ .name = "first" }, .{ .name = "second" } };
/// try deferred_enum.emit(allocator, &context, "DeferredStatus", .private);
/// ```
///
/// ### Expected output
///
/// ```zig
/// pub const InferredStatus = enum {
///     unknown,
///     ok,
/// };
/// const DeferredStatus = enum {
///     first,
///     second,
/// };
/// ```
pub fn init(
    allocator: std.mem.Allocator,
    backing_type: ?[]const u8,
    non_exhaustive: bool,
    fields: anytype,
) !InitResult(Self, @TypeOf(fields)) {
    const declaration = try allocator.create(Self);
    declaration.* = .{
        .backing_type = backing_type,
        .non_exhaustive = non_exhaustive,
        .fields = if (@TypeOf(fields) == @TypeOf(null)) &.{} else fields,
    };
    return declaration;
}

/// Reject explicit values or `_` when the integer backing type is inferred.
/// This check is deliberately repeated at emission because fields may be changed
/// after init, either through a mutable descriptor or through a borrowed alias.
/// It does not validate field type annotations, names, duplicates, or value ranges.
fn validateBackingType(self: *const Self) error{MissingBackingType}!void {
    if (self.backing_type != null) return;
    if (self.non_exhaustive) return error.MissingBackingType;
    for (self.fields) |enum_field| {
        if (enum_field.value != null or std.mem.eql(u8, enum_field.name, "_"))
            return error.MissingBackingType;
    }
}

/// Emit `enum(backing_type) { ... }` or `enum { ... }` and return its node.
///
/// ### Usage
///
/// This is the anonymous type expression: no `pub const Name =`, semicolon,
/// or root declaration is emitted. The caller attaches the returned node in an
/// enclosing construct, with that construct's surrounding tokens in source order.
/// Use `emit` instead when a complete named declaration is wanted.
///
/// `allocator` must match the context's buffer allocator.
///
/// ### Errors
///
/// `MissingBackingType` from this enum's settings is reported before any writes.
/// Allocation or child type errors may leave partial output; no rollback occurs.
/// All identifier spellings and remaining Zig semantics are caller-supplied.
///
/// ### Example
///
/// Uses `enum_decl` from the module example.
///
/// ```zig
/// const enum_type_node = try enum_decl.emitType(allocator, &context);
/// // A surrounding AST node can now reference enum_type_node as its type/value.
/// // It is not automatically added to context.declarations.
/// ```
///
/// ### Expected output
///
/// Formatted expression inside a completed AST, without a semicolon:
///
/// ```zig
/// enum(u8) {
///     unknown = 0,
///     ok = 1,
///     warning = 2,
///     _,
/// }
/// ```
pub fn emitType(
    self: *const Self,
    allocator: std.mem.Allocator,
    context: *AstContext,
) !std.zig.Ast.Node.Index {
    try self.validateBackingType();

    const enum_token = try context.token(allocator, .keyword_enum, null);
    var backing_type_node: ?std.zig.Ast.Node.Index = null;
    if (self.backing_type) |type_spelling| {
        _ = try context.token(allocator, .l_paren, null);
        backing_type_node = try context.identifierExpression(allocator, type_spelling);
        _ = try context.token(allocator, .r_paren, null);
    }
    return (Container{
        .main_token = enum_token,
        .argument_node = backing_type_node,
        .fields = self.fields,
        .trailing_field = if (self.non_exhaustive) .{ .name = "_" } else null,
    }).emit(allocator, .plain, context);
}

/// Emit `[pub] const name = enum[(T)] { ... };` and register its root declaration.
///
/// ### Usage
///
/// `.public` includes `pub`; `.private` omits it. `name` must be a complete Zig
/// identifier spelling; no escaping is performed. Reserve the root before use.
///
/// Uses the context's allocator. Finalize and render the context; this method
/// does not compile it.
///
/// ### Errors
///
/// This enum's backing-type validation occurs before any AST writes.
/// Allocation or child type errors can leave partial output.
///
/// ### Example
///
/// Uses `enum_decl` from the module example.
///
/// ```zig
/// try enum_decl.emit(allocator, &context, "Status", .public);
/// ```
///
/// ### Expected output
///
/// ```zig
/// pub const Status = enum(u8) {
///     unknown = 0,
///     ok = 1,
///     warning = 2,
///     _,
/// };
/// ```
pub fn emit(
    self: *const Self,
    allocator: std.mem.Allocator,
    context: *AstContext,
    name: []const u8,
    visibility: Visibility,
) !void {
    try self.validateBackingType();

    return Declaration.emitTypeDeclaration(allocator, context, self, name, visibility);
}
