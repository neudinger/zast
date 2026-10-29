//! Borrowed function description with separate type, member, and root emission.
//!
//! ## Ownership
//!
//! `init` allocates only the descriptor; parameter and statement slices are not
//! copied or owned by it. Use a parent arena, then release the arena after
//! emission. Parameter names, expression spellings, statements, and recursive
//! children must remain valid until emission finishes. There is no per-function
//! `deinit`. The allocator passed to emitters owns the AST buffers and may differ
//! from the arena allocator used by `init`.
//! A value literal such as `const function: FunctionDeclaration = .{};` needs no
//! descriptor allocation. If `init` uses a non-arena allocator, release its
//! descriptor with that allocator's `destroy` after emission.
//!
//! ## Usage
//!
//! - `emit` registers a complete named function at the file root.
//! - `emitNode` returns a named function for a container to attach as a member.
//! - `emitType` returns an anonymous prototype, omitting the function body.
//!
//! All three build source tokens and AST nodes directly; they do not parse, render,
//! or compile.
//!
//! This version emits ordinary functions, `comptime` parameters, and function types.
//! `noalias`/`anytype`/variadic parameters, `extern`/`export`/`inline` modifiers, calling
//! conventions, and inferred error-set syntax are not provided by this API.
//!
//! ## Example
//!
//! Examples assume imports of `std`, `AstContext`, `Expression`, `Block`, and
//! `FunctionDeclaration`, an `allocator`, and a context with its root reserved.
//! Import generator types through `@import("zast")`, for example
//! `const FunctionDeclaration = @import("zast").FunctionDeclaration;`.
//! Import `Expression` as `@import("zast").Expression`; `Block` is
//! `@import("zast").Block` and exposes the `Statement` union as `Block.Statement`.
//! Later examples also assume a parent arena's `builder_allocator`. Emission
//! examples are alternatives in fresh contexts; references to `function_decl`
//! reuse the descriptor setup below, before its first emission. `AstContext`
//! shows the complete initialization, rendering, and cleanup.
//!
//! ```zig
//! var arena = std.heap.ArenaAllocator.init(allocator);
//! defer arena.deinit();
//! const builder_allocator = arena.allocator();
//! const parameters = [_]FunctionDeclaration.Parameter{
//!     .{ .name = "value", .type_expression = .{ .identifier = "u32" } },
//! };
//! const statements = [_]Block.Statement{
//!     .{ .return_value = .{ .identifier = "value" } },
//! };
//! const function_decl = try FunctionDeclaration.init(
//!     builder_allocator,
//!     &parameters,
//!     .{ .identifier = "u32" },
//!     .{ .statements = &statements },
//! );
//! try function_decl.emit(allocator, &context, "identity", .public);
//! ```
//!
//! ## Expected output
//!
//! ```zig
//! pub fn identity(value: u32) u32 {
//!     return value;
//! }
//! ```
//!
//! ## Function pointers
//!
//! `emitType` describes a bare function type. Wrap it in a const pointer type
//! for a callback stored in a runtime value. In a fresh context:
//!
//! ```zig
//! const Declaration = @import("zast").Declaration;
//! const signature: FunctionDeclaration = .{
//!     .parameters = &.{.{ .type_expression = .{ .identifier = "u32" } }},
//!     .return_type = .{ .identifier = "u32" },
//! };
//! const function_type = Expression.fromType(&signature);
//! const callback: Expression = .{ .pointer_type = .{
//!     .child_type = &function_type, .is_const = true,
//! } };
//! try (Declaration{ .value = callback }).emit(allocator, &context, "Callback", .public);
//! ```
//!
//! ### Expected output
//!
//! ```zig
//! pub const Callback = *const fn (u32) u32;
//! ```
//!
//! ## Type factories
//!
//! Type factories return borrowed type descriptions through `Expression.fromType`.
//! In a fresh context with the imports and allocator described above:
//!
//! ```zig
//! const StructDeclaration = @import("zast").StructDeclaration;
//! const capacity: Expression = .{ .identifier = "capacity" };
//! const byte_type: Expression = .{ .identifier = "u8" };
//! const storage_type: StructDeclaration = .{ .members = &.{.{ .field = .{
//!     .name = "buffer",
//!     .type_expression = .{ .array_type = .{ .length = &capacity, .child_type = &byte_type } },
//!     .value = .{ .identifier = "undefined" },
//! } }} };
//! const storage: FunctionDeclaration = .{
//!     .parameters = &.{.{ .name = "capacity", .is_comptime = true,
//!         .type_expression = .{ .identifier = "usize" } }},
//!     .return_type = .{ .identifier = "type" },
//!     .body = .{ .statements = &.{.{ .return_value = Expression.fromType(&storage_type) }} },
//! };
//! try storage.emit(allocator, &context, "Storage", .public);
//! ```
//!
//! ## Expected type factory output
//!
//! ```zig
//! pub fn Storage(comptime capacity: usize) type {
//!     return struct {
//!         buffer: [capacity]u8 = undefined,
//!     };
//! }
//! ```
//!
//! The generated `Storage(64)` is a type with a 64-byte buffer. The generator
//! only writes this definition; Zig evaluates the factory when output is compiled.
//!
//! ## Error propagation and mutation
//!
//! Error propagation and mutation compose through `Expression` and `Block.Statement`.
//! In a fresh context with the same imports and allocator:
//!
//! ```zig
//! const value_type: Expression = .{ .identifier = "Value" };
//! const error_type: Expression = .{ .identifier = "anyerror" };
//! const decode_function: Expression = .{ .identifier = "decode" };
//! const decode_call: Expression = .{ .call = .{
//!     .callee = &decode_function, .arguments = &.{value_type},
//! } };
//! const reader: FunctionDeclaration = .{
//!     .parameters = &.{.{ .name = "Value", .is_comptime = true,
//!         .type_expression = .{ .identifier = "type" } }},
//!     .return_type = .{ .error_union_type = .{
//!         .error_set = &error_type, .payload_type = &value_type,
//!     } },
//!     .body = .{ .statements = &.{
//!         .{ .declaration = .{ .name = "result", .declaration = .{
//!             .kind = .variable, .type_expression = value_type,
//!             .value = .{ .identifier = "undefined" },
//!         } } },
//!         .{ .assignment = .{ .target = .{ .identifier = "result" },
//!             .value = .{ .@"try" = &decode_call } } },
//!         .{ .return_value = .{ .identifier = "result" } },
//!     } },
//! };
//! try reader.emit(allocator, &context, "read", .public);
//! ```
//!
//! ## Expected error propagation output
//!
//! Provide `decode(comptime Value: type) anyerror!Value` in the generated file;
//! the generator does not call it.
//!
//! ```zig
//! pub fn read(comptime Value: type) anyerror!Value {
//!     var result: Value = undefined;
//!     result = try decode(Value);
//!     return result;
//! }
//! ```
//!
//! On failure, `try` returns the operand's error from the generated function.
//! Emission failures still propagate from `emit`. See `examples/rich_functions.zig`
//! for a standalone generic function combining a local variable, assignment, and `try`.

const std = @import("std");
const AstContext = @import("AstContext.zig");
const ChildNodes = @import("ChildNodes.zig");
const InitResult = @import("InitResult.zig").InitResult;
const Expression = @import("Expression.zig").Expression;
const Block = @import("Block.zig");
const Declaration = @import("Declaration.zig");
/// Standard AST node layouts used for function prototypes and declarations.
const Ast = std.zig.Ast;
/// This file's struct type; descriptors may be arena-allocated with `init`.
const Self = @This();

/// A borrowed typed parameter, reusable in a named definition or function type.
///
/// Names and colons are token syntax; Zig's AST stores a node for the parameter
/// type rather than a separate parameter declaration node. The enclosing function
/// collects those type node indexes in parameter order.
///
/// Use a name for function definitions, `_` for an unused argument, or `null` for
/// an unnamed parameter in a function type. Referenced type expressions and name
/// spellings remain borrowed until emission finishes. No allocator is stored.
pub const Parameter = struct {
    /// Complete Zig identifier spelling, including `_` for an unused argument.
    /// `null` omits `name:` for `emitType`; named definitions report
    /// `MissingParameterName`. Names are copied without escaping or validation.
    name: ?[]const u8 = null,
    /// Required type expression after `name:`, or alone for an unnamed argument.
    /// Primitive identifiers, aliases, and composed pointer/slice types work.
    /// This is a borrowed description, not a previously emitted AST node index.
    type_expression: Expression,
    /// Require this argument at compile time, e.g. `comptime capacity: usize`.
    /// Allows a type-returning factory to use the value in array lengths or types.
    /// Later parameter types can depend on it, e.g. `comptime field: Field`
    /// followed by `value: @FieldType(Self, @tagName(field))`.
    /// False preserves ordinary runtime parameters. Zig checks how it is used.
    is_comptime: bool = false,

    /// Emit optional `comptime`, `name:`, and the type, returning its node index.
    ///
    /// ### Usage
    ///
    /// The prototype emitter supplies commas and parentheses and attaches that
    /// index. This does not register a root declaration or require a name itself.
    /// Pass the context's buffer allocator.
    ///
    /// ### Errors
    ///
    /// Allocation and child type errors may leave partial output.
    /// Names and type semantics are left to the caller and Zig.
    ///
    /// ### Example
    ///
    /// ```zig
    /// const byte_type: Expression = .{ .identifier = "u8" };
    /// const parameter: FunctionDeclaration.Parameter = .{
    ///     .name = "bytes",
    ///     .type_expression = .{ .slice_type = .{
    ///         .child_type = &byte_type,
    ///         .is_const = true,
    ///     } },
    /// };
    /// const parameter_type_node = try parameter.emit(allocator, &context);
    /// // Attach parameter_type_node to the surrounding function prototype.
    /// ```
    ///
    /// ### Expected output
    ///
    /// Formatted parameter inside a completed prototype, without a comma:
    ///
    /// ```zig
    /// bytes: []const u8
    /// ```
    pub fn emit(parameter: Parameter, allocator: std.mem.Allocator, context: *AstContext) anyerror!Ast.Node.Index {
        if (parameter.is_comptime) _ = try context.token(allocator, .keyword_comptime, null);
        if (parameter.name) |name| {
            _ = try context.token(allocator, .identifier, name);
            _ = try context.token(allocator, .colon, null);
        }
        return parameter.type_expression.emit(allocator, context);
    }
};

/// Borrowed parameters in source order, defaulting to an empty list.
/// Reassignable through a mutable descriptor; `init` neither copies nor owns the
/// slice. Every named definition parameter needs a name, including unused `_`.
parameters: []const Parameter = &.{},
/// Return type description, defaulting to `void`; not inferred from the body.
/// Child expressions and spellings are borrowed. Zig checks return compatibility.
return_type: Expression = .{ .identifier = "void" },
/// Borrowed statement block for named definitions, defaulting to `{}`.
/// No return is inserted automatically. `emitType` ignores this entire body.
body: Block = .{},

/// Allocate a function descriptor without emitting or validating any Zig syntax.
///
/// ### Ownership
///
/// Supply a parent arena's allocator; only the descriptor is allocated here.
/// `parameters` accepts literal `null` or a value coercible to `[]const Parameter`,
/// such as `&parameter_array`, `parameter_slice`, or `parameter_list.items`.
/// Declare supplied arrays as `[_]FunctionDeclaration.Parameter`; `anytype` does
/// not infer that element type for a nonempty anonymous `&.{ ... }` argument.
///
/// - Literal `null` creates an empty mutable `*FunctionDeclaration`; assign
///   `.parameters`, `.return_type`, or `.body` later.
/// - A parameter slice or array pointer, even empty, returns `*const FunctionDeclaration`.
///
/// Constness is shallow: another alias can still change the borrowed data. Do not
/// free or reallocate borrowed storage before emission finishes. No `deinit` is
/// needed on the descriptor; release its parent arena when the descriptions are finished.
///
/// `return_type` and `body` are descriptions copied by value; their slices,
/// string spellings, and recursive children remain borrowed.
///
/// ### Errors
///
/// A body must contain the statements required by its return type; this API does
/// not infer a return. `init` reports only allocation failure. Named emitters report
/// `MissingParameterName` before any AST writes when a current parameter is unnamed.
/// Other validity checks, including return types and unused arguments, remain
/// with Zig.
///
/// ### Example
///
/// ```zig
/// const statements = [_]Block.Statement{
///     .{ .return_value = .{ .identifier = "value" } },
/// };
/// const deferred_function = try FunctionDeclaration.init(
///     builder_allocator,
///     null,
///     .{ .identifier = "u32" },
///     .{ .statements = &statements },
/// ); // *FunctionDeclaration, even though the pointer binding is const
/// deferred_function.parameters = &.{
///     .{ .name = "value", .type_expression = .{ .identifier = "u32" } },
/// };
/// try deferred_function.emit(allocator, &context, "deferredIdentity", .private);
/// ```
///
/// ### Expected output
///
/// ```zig
/// fn deferredIdentity(value: u32) u32 {
///     return value;
/// }
/// ```
pub fn init(
    allocator: std.mem.Allocator,
    parameters: anytype,
    return_type: Expression,
    body: Block,
) !InitResult(Self, @TypeOf(parameters)) {
    const declaration = try allocator.create(Self);
    declaration.* = .{
        .return_type = return_type,
        .body = body,
        .parameters = if (@TypeOf(parameters) == @TypeOf(null)) &.{} else parameters,
    };
    return declaration;
}

/// Ensure every parameter in a named definition has a name before writing tokens.
/// Repeat this check at emission because a mutable descriptor or borrowed alias
/// can change parameters after init. Unnamed parameters remain valid for emitType.
/// Does not check identifier spelling, duplicates, type validity, or body semantics.
/// Enclosing containers call this to reject invalid methods before writing headers.
pub fn validateParameters(self: *const Self) error{MissingParameterName}!void {
    for (self.parameters) |parameter| {
        if (parameter.name == null) return error.MissingParameterName;
    }
}

/// Emit `fn (parameters) ReturnType` and return its prototype node index.
///
/// ### Usage
///
/// Parameter names may be `null`; supplied names are preserved as prototype syntax.
/// This emits no function name, `pub`, body, semicolon, or root declaration.
/// The caller attaches the node in the same context and supplies surrounding
/// tokens in source order. Use `emit` for a named definition with a body.
///
/// Pass the context's buffer allocator. This method does not run named-parameter
/// validation.
///
/// ### Errors
///
/// Allocation and child type errors propagate and may leave partial output.
/// Zig checks type validity when the generated source is compiled.
///
/// ### Example
///
/// ```zig
/// const parameters = [_]FunctionDeclaration.Parameter{
///     .{ .type_expression = .{ .identifier = "u32" } },
/// };
/// const function_type: FunctionDeclaration = .{
///     .parameters = &parameters,
///     .return_type = .{ .identifier = "u32" },
/// };
/// const type_node = try function_type.emitType(allocator, &context);
/// // Attach type_node as a declaration's initializer or another type's child.
/// ```
///
/// ### Expected output
///
/// Formatted type expression inside a completed AST, without a semicolon:
///
/// ```zig
/// fn (u32) u32
/// ```
pub fn emitType(self: *const Self, allocator: std.mem.Allocator, context: *AstContext) !Ast.Node.Index {
    return self.emitPrototype(allocator, context, null, .private);
}

/// Emit `[pub] fn name(parameters) ReturnType { ... }` and return its node.
///
/// ### Usage
///
/// This emits the complete definition, including its body, without registering
/// a root member. Use it when an enclosing declaration attaches the function
/// as a member. The caller supplies the container header and closing syntax.
/// Reserve that container's member range before emitting children, since a
/// prototype or body can append its own data to `context.extra_data`.
/// `StructDeclaration.Member` and `Container.emitMembers` perform this
/// attachment; `Container.fields` remains a list of fields only.
///
/// `name` must be a complete Zig identifier spelling; no escaping is performed.
/// `.public` includes `pub`; `.private` omits it. Pass the context's buffer
/// allocator.
///
/// ### Errors
///
/// This function's parameter names are checked before AST writes;
/// allocation or child type errors may leave partial output, with no rollback.
///
/// ### Example
///
/// Uses the descriptor setup from the module example.
///
/// ```zig
/// const member_node = try function_decl.emitNode(
///     allocator, &context, "identity", .public,
/// );
/// // Store member_node in the surrounding container's member range.
/// // It is not automatically added to context.declarations.
/// ```
///
/// ### Expected output
///
/// Formatted member, shown without its container's indentation:
///
/// ```zig
/// pub fn identity(value: u32) u32 {
///     return value;
/// }
/// ```
pub fn emitNode(
    self: *const Self,
    allocator: std.mem.Allocator,
    context: *AstContext,
    name: []const u8,
    visibility: Declaration.Visibility,
) !Ast.Node.Index {
    try self.validateParameters();
    const prototype_node = try self.emitPrototype(allocator, context, name, visibility);
    const body_node = try self.body.emit(allocator, context);
    return context.addNode(allocator, .fn_decl, context.nodes.items(.main_token)[@backingInt(prototype_node)], .{
        .node_and_node = .{ prototype_node, body_node },
    });
}

/// Emit `[pub] fn name(parameters) ReturnType { ... }` and register it at root.
///
/// ### Usage
///
/// `.public` includes `pub`; `.private` omits it. `name` must be a complete Zig
/// identifier spelling; no escaping is performed. Reserve the root before use.
/// This appends the definition's index to `context.declarations`; finalization
/// must still connect that list to the root and terminate the source.
///
/// Pass the context's buffer allocator. Finalize and render the context; this
/// method does not compile it.
///
/// ### Errors
///
/// This function's parameter names are checked before AST writes.
/// Allocation or child type errors may leave partial output.
///
/// ### Example
///
/// Uses the descriptor setup from the module example.
///
/// ```zig
/// try function_decl.emit(allocator, &context, "identity", .public);
/// ```
///
/// ### Expected output
///
/// ```zig
/// pub fn identity(value: u32) u32 {
///     return value;
/// }
/// ```
pub fn emit(
    self: *const Self,
    allocator: std.mem.Allocator,
    context: *AstContext,
    name: []const u8,
    visibility: Declaration.Visibility,
) !void {
    const declaration_node = try self.emitNode(allocator, context, name, visibility);
    try context.declarations.append(allocator, @backingInt(declaration_node));
}

/// Share prototype construction between anonymous types and named definitions.
/// Reserve parameter slots before child emission to keep their range contiguous.
/// Zero/one typed parameter uses fn_proto_simple; longer lists use fn_proto_multi
/// with a SubRange in extra_data. Names, colons, and commas remain token syntax.
fn emitPrototype(
    self: *const Self,
    allocator: std.mem.Allocator,
    context: *AstContext,
    name: ?[]const u8,
    visibility: Declaration.Visibility,
) !Ast.Node.Index {
    var children = try ChildNodes.init(allocator, context, self.parameters.len, 1);

    if (visibility == .public) _ = try context.token(allocator, .keyword_pub, null);
    const function_token = try context.token(allocator, .keyword_fn, null);
    if (name) |function_name| _ = try context.token(allocator, .identifier, function_name);
    _ = try context.token(allocator, .l_paren, null);
    for (self.parameters, 0..) |parameter, parameter_index| {
        if (parameter_index != 0) _ = try context.token(allocator, .comma, null);
        children.set(context, parameter_index, try parameter.emit(allocator, context));
    }
    _ = try context.token(allocator, .r_paren, null);
    const return_node = try self.return_type.emit(allocator, context);
    if (!children.uses_extra) {
        return context.addNode(allocator, .fn_proto_simple, function_token, .{
            .opt_node_and_opt_node = .{ children.inline_nodes[0], return_node.toOptional() },
        });
    }
    const range_index = try children.appendRange(allocator, context);
    return context.addNode(allocator, .fn_proto_multi, function_token, .{
        .extra_and_opt_node = .{ range_index, return_node.toOptional() },
    });
}
