//! Borrowed struct description composing fields, functions, and `const`/`var` members.
//!
//! ## Ownership
//!
//! `init` allocates only the descriptor in a parent arena. Member slices, names,
//! expressions, and function descriptions remain borrowed until emission ends.
//! No per-struct `deinit` is needed. Emitters use the AST buffer allocator separately.
//! A value literal such as `const record: StructDeclaration = .{};` needs no
//! descriptor allocation. If `init` uses a non-arena allocator, release its
//! descriptor with that allocator's `destroy` after emission.
//!
//! ## Usage
//!
//! - `emitType` returns an anonymous type.
//! - `emit` registers a named `const` declaration.
//!
//! Fields must have explicit types and form one consecutive group. Declarations
//! may precede or follow that group. Function members reuse `FunctionDeclaration`;
//! their bodies reuse `Block`, not the container's member list.
//! Nested types use `Expression.fromType` in a field or namespace declaration.
//!
//! Tuple fields, `comptime`/aligned fields, explicit packed backing types, tests,
//! and `comptime` declarations are not provided yet.
//!
//! ## Validation and errors
//!
//! `emit` and `emitType` reject a missing field type with `MissingFieldType`, a
//! field after the first field group has ended with `NonContiguousFields`, and
//! an unnamed method parameter with `MissingParameterName`, before writing this
//! struct's header. Layout compatibility, duplicate names, and generated-code
//! semantics remain with Zig. Allocation and child emission errors can leave
//! partial output; the whole child graph is not validated in advance.
//!
//! ## Example
//!
//! Examples assume imports of `std`, `AstContext`, `StructDeclaration`, and
//! `FunctionDeclaration`, an `allocator`, and a fresh context whose root is reserved.
//! Import generator types through `@import("zast")`, for example
//! `const StructDeclaration = @import("zast").StructDeclaration;`.
//! Later examples assume `builder_allocator` from a parent arena. `AstContext`
//! shows rendering.
//! Emission examples are alternatives in fresh contexts; references to `struct_decl`
//! reuse its setup below before the first `emit` call.
//!
//! ```zig
//! var arena = std.heap.ArenaAllocator.init(allocator);
//! defer arena.deinit();
//! const builder_allocator = arena.allocator();
//! const method = try FunctionDeclaration.init(
//!     builder_allocator, &.{}, .{ .identifier = "u32" },
//!     .{ .statements = &.{.{ .return_value = .{ .integer_literal = "84" } }} },
//! );
//! const members = [_]StructDeclaration.Member{
//!     .{ .field = .{
//!         .name = "answer",
//!         .type_expression = .{ .identifier = "u32" },
//!         .value = .{ .integer_literal = "65" },
//!     } },
//!     .{ .function = .{
//!         .name = "answerFunc", .declaration = method, .visibility = .public,
//!     } },
//! };
//! const struct_decl = try StructDeclaration.init(
//!     builder_allocator, .automatic, &members,
//! );
//! try struct_decl.emit(allocator, &context, "Reading", .public);
//! ```
//!
//! ## Expected output
//!
//! ```zig
//! pub const Reading = struct {
//!     answer: u32 = 65,
//!     pub fn answerFunc() u32 {
//!         return 84;
//!     }
//! };
//! ```
//!
//! ## Nested types
//!
//! A nested type is a normal `const` member whose value wraps another descriptor.
//! With the same context setup in a fresh context:
//!
//! ```zig
//! const Expression = @import("zast").Expression;
//! const options: StructDeclaration = .{ .members = &.{.{ .field = .{
//!     .name = "force_defaults", .type_expression = .{ .identifier = "bool" },
//!     .value = .{ .identifier = "false" },
//! } }} };
//! const reading: StructDeclaration = .{ .members = &.{.{ .declaration = .{
//!     .name = "WriteOptions", .visibility = .public,
//!     .declaration = .{ .value = Expression.fromType(&options) },
//! } }} };
//! try reading.emit(allocator, &context, "Reading", .public);
//! ```
//!
//! ## Expected nested type output
//!
//! ```zig
//! pub const Reading = struct {
//!     pub const WriteOptions = struct {
//!         force_defaults: bool = false,
//!     };
//! };
//! ```
//!
//! Both descriptors stay alive until emission ends. The nested descriptor emits
//! only its type; the enclosing member supplies its name, visibility, and `;`.

const std = @import("std");
const AstContext = @import("AstContext.zig");
const InitResult = @import("InitResult.zig").InitResult;
const Field = @import("Field.zig");
const Declaration = @import("Declaration.zig");
const Container = @import("Container.zig");
const FunctionDeclaration = @import("FunctionDeclaration.zig");
/// The file itself is the struct descriptor type.
const Self = @This();

/// Header layout. Zig checks whether the selected layout permits each field type.
pub const Layout = enum {
    /// `struct { ... }`, using Zig's automatic layout.
    automatic,
    /// `extern struct { ... }`, using the target's C ABI layout rules.
    @"extern",
    /// `packed struct { ... }`, inferring the backing integer from the fields.
    @"packed",
};

/// One borrowed member of a struct namespace, emitted in source order.
///
/// Fields reuse `Field`; named bindings reuse `Declaration`. Function
/// descriptions are borrowed through pointers and may include an explicit self
/// parameter. No member is registered at the file root by its own emitter.
pub const Member = union(enum) {
    /// A named instance field with a required type and an optional default value.
    field: Field,
    /// A function in this namespace; an explicit self parameter makes a method.
    function: struct {
        /// Complete identifier spelling; not escaped by the emitter.
        name: []const u8,
        /// Borrowed function descriptor, including parameters and body.
        declaration: *const FunctionDeclaration,
        /// Whether to prefix this member with `pub`, independently of the struct.
        visibility: Declaration.Visibility = .private,
    },
    /// A namespace `const`/`var`, including a type alias, rather than an instance field.
    declaration: struct {
        /// Complete identifier spelling; not escaped by the emitter.
        name: []const u8,
        /// Borrowed binding description, with type and initializer expressions.
        declaration: Declaration,
        /// Whether to prefix this member with `pub`, independently of the struct.
        visibility: Declaration.Visibility = .private,
    },

    /// Emit a member and return its node without root registration.
    /// The enclosing struct validates the complete member list before emission.
    /// Fields supply commas; functions and bindings supply their own terminators.
    /// Pass the context's buffer allocator; child errors can leave partial output.
    pub fn emit(member: Member, allocator: std.mem.Allocator, context: *AstContext) !std.zig.Ast.Node.Index {
        return switch (member) {
            .field => |field| field.emit(allocator, context),
            inline .function, .declaration => |binding| binding.declaration.emitNode(allocator, context, binding.name, binding.visibility),
        };
    }
};

/// Struct header layout, defaulting to automatic.
layout: Layout = .automatic,
/// Borrowed ordered members. All fields must form one consecutive group.
members: []const Member = &.{},

/// Allocate a descriptor in a parent arena without emitting or validating syntax.
///
/// ### Ownership
///
/// `members` accepts literal `null` or a value coercible to `[]const Member`, including
/// `&member_array`, `member_slice`, or `member_list.items`. Use explicitly typed arrays:
/// `[_]StructDeclaration.Member`; `anytype` does not infer nonempty anonymous arrays.
///
/// - `null` returns `*StructDeclaration` so `members`/`layout` can be assigned later.
/// - A supplied slice or array pointer, even empty, returns `*const StructDeclaration`.
///
/// Constness is shallow. Borrowed storage must survive emission without being
/// freed or reallocated; `init` does not copy it. Only allocation can fail here.
///
/// ### Example
///
/// ```zig
/// const struct_decl = try StructDeclaration.init(
///     builder_allocator, .automatic, null,
/// ); // *StructDeclaration, despite the const pointer binding
/// struct_decl.members = &.{.{ .field = .{
///     .name = "count", .type_expression = .{ .identifier = "u32" },
/// } }};
/// try struct_decl.emit(allocator, &context, "Counter", .private);
/// ```
///
/// ### Expected output
///
/// ```zig
/// const Counter = struct {
///     count: u32,
/// };
/// ```
pub fn init(allocator: std.mem.Allocator, layout: Layout, members: anytype) !InitResult(Self, @TypeOf(members)) {
    const declaration = try allocator.create(Self);
    declaration.* = .{
        .layout = layout,
        .members = if (@TypeOf(members) == @TypeOf(null)) &.{} else members,
    };
    return declaration;
}

/// Check field types, field grouping, and named method parameters without writes.
/// Recheck borrowed members at emission because aliases may have changed them.
/// Layout/type compatibility, duplicate names, and expression semantics remain
/// with Zig. MissingFieldType, NonContiguousFields, or MissingParameterName can fail.
fn validateMembers(self: *const Self) error{ MissingFieldType, NonContiguousFields, MissingParameterName }!void {
    var fields_seen = false;
    var fields_ended = false;
    for (self.members) |member| {
        switch (member) {
            .field => |field| {
                if (field.type_expression == null) return error.MissingFieldType;
                if (fields_ended) return error.NonContiguousFields;
                fields_seen = true;
            },
            else => {
                if (fields_seen) fields_ended = true;
                if (member == .function) try member.function.declaration.validateParameters();
            },
        }
    }
}

/// Emit `[extern|packed] struct { ... }` and return its type node.
///
/// ### Usage
///
/// No named `const`, semicolon, or root registration is emitted. The enclosing
/// construct attaches the returned node and supplies its surrounding tokens.
/// Pass the context's buffer allocator.
///
/// ### Errors
///
/// This struct's member validation occurs before writes. Allocation or child type
/// errors can leave partial output.
///
/// ### Example
///
/// ```zig
/// const struct_decl: StructDeclaration = .{ .members = &.{.{ .field = .{
///     .name = "count", .type_expression = .{ .identifier = "u32" },
/// } }} };
/// const type_node = try struct_decl.emitType(allocator, &context);
/// // Attach type_node to an enclosing declaration or type expression.
/// ```
///
/// ### Expected output
///
/// Formatted type expression inside a completed AST, without a semicolon:
///
/// ```zig
/// struct {
///     count: u32,
/// }
/// ```
pub fn emitType(self: *const Self, allocator: std.mem.Allocator, context: *AstContext) !std.zig.Ast.Node.Index {
    try self.validateMembers();
    switch (self.layout) {
        .automatic => {},
        inline .@"extern", .@"packed" => |layout| _ = try context.token(allocator, @field(std.zig.Token.Tag, "keyword_" ++ @tagName(layout)), null),
    }
    const struct_token = try context.token(allocator, .keyword_struct, null);
    const trailing_separator = self.members.len != 0 and switch (self.members[self.members.len - 1]) {
        .field, .declaration => true,
        .function => false,
    };
    return (Container{ .main_token = struct_token }).emitMembers(allocator, .plain, self.members, trailing_separator, context);
}

/// Emit `[pub] const name = [extern|packed] struct { ... };` and register at root.
///
/// ### Usage
///
/// Reserve the root first. `name` must be a complete identifier spelling;
/// `visibility` controls only the struct declaration. Member visibility is
/// configured separately. Pass the context's buffer allocator.
/// Finalize and render to obtain source.
///
/// ### Errors
///
/// This struct's member validation occurs before writes. Allocation or child type
/// errors can leave partial output.
///
/// ### Example
///
/// Uses the descriptor setup from the module example in a fresh context.
///
/// ```zig
/// try struct_decl.emit(allocator, &context, "Reading", .public);
/// ```
///
/// ### Expected output
///
/// ```zig
/// pub const Reading = struct {
///     answer: u32 = 65,
///     pub fn answerFunc() u32 {
///         return 84;
///     }
/// };
/// ```
pub fn emit(self: *const Self, allocator: std.mem.Allocator, context: *AstContext, name: []const u8, visibility: Declaration.Visibility) !void {
    try self.validateMembers();
    return Declaration.emitTypeDeclaration(allocator, context, self, name, visibility);
}
