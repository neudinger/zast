//! Borrowed union description with separate anonymous and named emission.
//!
//! ## Ownership
//!
//! `init` allocates only the descriptor; its fields are a borrowed slice, not a
//! copied or growable list. Use a parent arena for the descriptor, then release
//! the arena after emission. Fields, names, tag/payload type expressions, and
//! recursive children must remain valid until emission finishes. There is no
//! per-union `deinit`. The allocator passed to `emit`/`emitType` owns the AST
//! buffers and may differ from the arena allocator used by `init`.
//! A value literal such as `const payload: UnionDeclaration = .{ .tag_type = .inferred };`
//! needs no descriptor allocation. If `init` uses a non-arena allocator, release
//! its descriptor with that allocator's `destroy` after emission.
//!
//! ## Usage
//!
//! Examples assume imports of `std`, `AstContext`, `Field`, and `UnionDeclaration`,
//! plus an `allocator` and a context whose root node has already been reserved.
//! Import generator types through `@import("zast")`, for example
//! `const UnionDeclaration = @import("zast").UnionDeclaration;`.
//! Examples after this one also assume a parent arena's `builder_allocator`.
//! Emission examples are alternatives in fresh contexts; references to `union_decl`
//! reuse its setup below before the first `emit` call.
//! `AstContext` shows the complete initialization, rendering, and cleanup.
//!
//! ## Example
//!
//! ```zig
//! var arena = std.heap.ArenaAllocator.init(allocator);
//! defer arena.deinit();
//! const builder_allocator = arena.allocator();
//! const payload_fields = [_]Field{
//!     .{ .name = "none" },
//!     .{ .name = "number", .type_expression = .{ .identifier = "u32" } },
//!     .{ .name = "boolean", .type_expression = .{ .identifier = "bool" } },
//! };
//! const union_decl = try UnionDeclaration.init(
//!     builder_allocator, .inferred, &payload_fields,
//! );
//! try union_decl.emit(allocator, &context, "Payload", .public);
//! ```
//!
//! ## Expected output
//!
//! ```zig
//! pub const Payload = union(enum) {
//!     none,
//!     number: u32,
//!     boolean: bool,
//! };
//! ```

const std = @import("std");
const AstContext = @import("AstContext.zig");
const InitResult = @import("InitResult.zig").InitResult;
const Container = @import("Container.zig");
const Declaration = @import("Declaration.zig");

/// Reusable expressions describing the union's tag type and payload types.
const Expression = @import("Expression.zig").Expression;
/// Shared named-declaration visibility; `.public` emits the `pub` keyword.
const Visibility = Declaration.Visibility;
/// Shared field description; union payload types use `type_expression`.
const Field = @import("Field.zig");
/// This file's struct type; allocated descriptors are returned by `init`.
const Self = @This();

/// Select one of the four supported union headers.
///
/// Type-expression payloads are borrowed descriptions, not AST node indexes.
/// Zig must resolve them to an integer backing type or an existing enum as
/// appropriate; this generator does not check those types or their tag values.
///
/// ### Example
///
/// ```zig
/// const typed_fields = [_]Field{
///     .{ .name = "none", .type_expression = .{ .identifier = "void" } },
///     .{ .name = "number", .type_expression = .{ .identifier = "u32" } },
/// };
/// const sized_union = try UnionDeclaration.init(
///     builder_allocator,
///     .{ .backing_type = .{ .identifier = "u8" } },
///     &typed_fields,
/// );
/// try sized_union.emit(allocator, &context, "SizedPayload", .public);
///
/// // Assumes generated Zig already declares: const Kind = enum { none, number };
/// const named_tag_union = try UnionDeclaration.init(
///     builder_allocator,
///     .{ .enum_type = .{ .identifier = "Kind" } },
///     &typed_fields,
/// );
/// try named_tag_union.emit(allocator, &context, "NamedPayload", .public);
/// ```
///
/// ### Expected output
///
/// Formatted declarations; the existing `Kind` is not emitted here.
///
/// ```zig
/// pub const SizedPayload = union(enum(u8)) {
///     none: void,
///     number: u32,
/// };
/// pub const NamedPayload = union(Kind) {
///     none: void,
///     number: u32,
/// };
/// ```
pub const TagType = union(enum) {
    /// `union { ... }`, without a generated tag enum. Every field must provide
    /// `type_expression`, including `.identifier = "void"` for a void payload.
    untagged,
    /// `union(enum) { ... }`, generating an enum tag with an inferred backing
    /// integer type. A field without a payload type represents `void`.
    inferred,
    /// `union(enum(T)) { ... }`, generating an enum tag with integer backing `T`,
    /// e.g. `.backing_type = .{ .identifier = "u8" }`. Payload types may be absent.
    backing_type: Expression,
    /// `union(Tag) { ... }` using an existing enum, whose tag names must match the
    /// fields as required by Zig. Use `.field_access` for a qualified enum type.
    /// `Expression.fromType` can supply an anonymous enum; it is grouped to keep
    /// `union((enum(u8) { ... }))` distinct from the generated-tag header syntax.
    enum_type: Expression,
};

/// Header syntax and optional tag type expression used by both emitters.
tag_type: TagType,
/// Borrowed fields in source order. `type_expression` is the payload type;
/// null emits a bare field, which means void in a tagged union. Reassignable
/// through a mutable descriptor. Leave `value` null: these fields declare payload
/// types, not payload values. Other field combinations are left to Zig.
fields: []const Field = &.{},

/// Allocate a union descriptor without emitting or validating any Zig syntax.
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
/// - Literal `null` creates an empty mutable `*UnionDeclaration`; assign `.fields` later.
/// - A field slice or array pointer, even empty, returns a `*const UnionDeclaration`.
///
/// This is shallow constness: another alias can still change the borrowed data.
/// The descriptor has no per-declaration `deinit`.
///
/// ### Errors
///
/// Untagged union fields require explicit payload types. `emit`/`emitType` report
/// `MissingFieldType` for violations; `init` itself reports only allocation
/// failure. Other validity checks, such as tag compatibility, remain with Zig.
///
/// ### Example
///
/// ```zig
/// const raw_union = try UnionDeclaration.init(
///     builder_allocator, .untagged, null,
/// ); // *UnionDeclaration, even though the pointer binding is const
/// raw_union.fields = &.{
///     .{ .name = "number", .type_expression = .{ .identifier = "u32" } },
///     .{ .name = "boolean", .type_expression = .{ .identifier = "bool" } },
/// };
/// try raw_union.emit(allocator, &context, "RawPayload", .private);
/// ```
///
/// ### Expected output
///
/// ```zig
/// const RawPayload = union {
///     number: u32,
///     boolean: bool,
/// };
/// ```
pub fn init(
    allocator: std.mem.Allocator,
    tag_type: TagType,
    fields: anytype,
) !InitResult(Self, @TypeOf(fields)) {
    const declaration = try allocator.create(Self);
    declaration.* = .{
        .tag_type = tag_type,
        .fields = if (@TypeOf(fields) == @TypeOf(null)) &.{} else fields,
    };
    return declaration;
}

/// Reject untagged union fields without an explicit payload type.
/// Tagged unions allow implicit void fields. Check again at emission because
/// fields may change through a mutable descriptor or through a borrowed alias.
/// Does not check names, duplicate fields, value expressions, or tag-type validity.
fn validateFields(self: *const Self) error{MissingFieldType}!void {
    if (self.tag_type != .untagged) return;
    for (self.fields) |union_field| {
        if (union_field.type_expression == null) return error.MissingFieldType;
    }
}

/// Emit the anonymous union type expression and return its node index.
///
/// ### Usage
///
/// The header follows `tag_type`: `union`, `union(enum)`, `union(enum(T))`, or
/// `union(Tag)`. No `pub const Name =`, semicolon, or root declaration is emitted.
/// The caller attaches the returned node in an enclosing construct, supplying
/// that construct's surrounding tokens in source order. Use `emit` for a
/// complete named declaration.
///
/// `allocator` must match the context's buffer allocator.
///
/// ### Errors
///
/// `MissingFieldType` is reported before writes for this union's untagged fields
/// without payload types.
/// Allocation or child type errors may leave partial output; no rollback occurs.
/// All identifier spellings and remaining Zig semantics are caller-supplied.
///
/// ### Example
///
/// Uses `union_decl` from the module example.
///
/// ```zig
/// const union_type_node = try union_decl.emitType(allocator, &context);
/// // A surrounding AST node can reference union_type_node as its type/value.
/// // It is not automatically added to context.declarations.
/// ```
///
/// ### Expected output
///
/// Formatted expression inside a completed AST, without a semicolon:
///
/// ```zig
/// union(enum) {
///     none,
///     number: u32,
///     boolean: bool,
/// }
/// ```
pub fn emitType(self: *const Self, allocator: std.mem.Allocator, context: *AstContext) !std.zig.Ast.Node.Index {
    try self.validateFields();

    const union_token = try context.token(allocator, .keyword_union, null);
    var argument_node: ?std.zig.Ast.Node.Index = null;
    if (self.tag_type != .untagged) _ = try context.token(allocator, .l_paren, null);
    switch (self.tag_type) {
        .untagged => {},
        .inferred => _ = try context.token(allocator, .keyword_enum, null),
        inline .backing_type, .enum_type => |type_expression, tag_kind| {
            if (tag_kind == .backing_type) {
                _ = try context.token(allocator, .keyword_enum, null);
                _ = try context.token(allocator, .l_paren, null);
            }
            // A bare enum keyword means union(enum), not an enum type literal.
            // Group borrowed tag emitters; named tag expressions keep their spelling.
            const argument = if (tag_kind == .enum_type and type_expression == .type_description)
                Expression{ .grouped = &type_expression }
            else
                type_expression;
            argument_node = try argument.emit(allocator, context);
            if (tag_kind == .backing_type) _ = try context.token(allocator, .r_paren, null);
        },
    }
    if (self.tag_type != .untagged) _ = try context.token(allocator, .r_paren, null);
    const container: Container = .{
        .main_token = union_token,
        .argument_node = argument_node,
        .fields = self.fields,
    };
    return switch (self.tag_type) {
        .untagged, .enum_type => container.emit(allocator, .plain, context),
        .inferred, .backing_type => container.emit(allocator, .tagged_union, context),
    };
}

/// Emit `[pub] const name = union... { ... };` and register its root declaration.
///
/// ### Usage
///
/// `.public` includes `pub`; `.private` omits it. `name` must be a complete Zig
/// identifier spelling; no escaping is performed. Reserve the root before use.
///
/// Uses the context's buffer allocator. Finalize and render the context; this
/// method does not compile it.
///
/// ### Errors
///
/// This union's field validation occurs before AST writes.
/// Allocation or child type errors can leave partial output.
///
/// ### Example
///
/// Uses `union_decl` from the module example.
///
/// ```zig
/// try union_decl.emit(allocator, &context, "Payload", .public);
/// ```
///
/// ### Expected output
///
/// ```zig
/// pub const Payload = union(enum) {
///     none,
///     number: u32,
///     boolean: bool,
/// };
/// ```
pub fn emit(
    self: *const Self,
    allocator: std.mem.Allocator,
    context: *AstContext,
    name: []const u8,
    visibility: Visibility,
) !void {
    // Validate before writing the declaration prefix.
    try self.validateFields();

    return Declaration.emitTypeDeclaration(allocator, context, self, name, visibility);
}
