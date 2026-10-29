//! Composable descriptions for Zig values and types.
//!
//! See `Expression` for ownership rules, context setup, and examples covering
//! precedence, compound types, calls, builtins, and initializers.

const std = @import("std");
const AstContext = @import("AstContext.zig");
const ChildNodes = @import("ChildNodes.zig");

/// A borrowed, acyclic description of a Zig value expression or type expression.
///
/// ## Usage
///
/// Use `const Expression = @import("zast").Expression;`.
///
/// ## Ownership and errors
///
/// This is a generator description, not an `std.zig.Ast.Node` or a generated
/// runtime value. Recursive variants point to other `Expression` values and
/// must form an acyclic graph. Children can be shared, but each occurrence emits
/// fresh syntax. Descriptions borrow their strings and children until `emit`
/// returns; no copying occurs before emission.
/// Emission copies spellings into an `AstContext` and allocates its nodes with the
/// supplied allocator. No description here needs its own `deinit`.
///
/// Allocating emitters may leave partial syntax on failure; discard that output.
/// Spellings and semantic validity remain the caller's responsibility; Zig
/// performs name resolution and type checking on the generated code.
///
/// ## Example setup
///
/// Examples assume the import above and:
///
/// - `AstContext = @import("zast").AstContext`.
/// - An `allocator` and `var context: AstContext = .{};`.
/// - Node zero reserved as `.root` before emitting any child nodes.
///
/// `AstContext` contains a complete example of finalizing and rendering a tree.
///
/// ## Precedence example
///
/// Compose expressions from stable child descriptions; precedence adds the
/// parentheses needed to preserve their meaning:
///
/// ```zig
/// const literal_one: Expression = .{ .integer_literal = "1" };
/// const shift_amount: Expression = .{ .integer_literal = "4" };
/// const shifted_value: Expression = .{
///     .shift_left = .{ .left = &literal_one, .right = &shift_amount },
/// };
/// const negative_flag: Expression = .{ .negate = &shifted_value };
/// const expression_node = try negative_flag.emit(allocator, &context);
/// // Attach expression_node to an enclosing construct.
/// ```
///
/// ### Expected output
///
/// Expression inside a completed AST, without a semicolon:
///
/// ```zig
/// -(1 << 4)
/// ```
///
/// ## Compound types
///
/// Compound descriptions also work as named aliases through `Declaration`. With
/// the context setup above, the following emits six complete declarations:
///
/// ```zig
/// const Declaration = @import("zast").Declaration;
/// const byte_type: Expression = .{ .identifier = "u8" };
/// const length: Expression = .{ .integer_literal = "4" };
/// const zero: Expression = .{ .integer_literal = "0" };
/// const alignment: Expression = .{ .integer_literal = "1" };
/// const buffer: Expression = .{ .array_type = .{
///     .length = &length, .child_type = &byte_type, .sentinel = &zero,
/// } };
/// const raw_bytes: Expression = .{ .pointer_type = .{
///     .child_type = &byte_type, .kind = .{ .many = &zero },
///     .is_allowzero = true, .alignment = &alignment,
///     .is_const = true, .is_volatile = true,
/// } };
/// const c_bytes: Expression = .{ .pointer_type = .{
///     .child_type = &byte_type, .kind = .c,
/// } };
/// const text: Expression = .{ .slice_type = .{
///     .child_type = &byte_type, .sentinel = &zero, .is_const = true,
/// } };
/// const failures: Expression = .{ .error_set_type = &.{"Invalid"} };
/// const result: Expression = .{ .error_union_type = .{
///     .error_set = &failures, .payload_type = &text,
/// } };
/// try (Declaration{ .value = buffer }).emit(allocator, &context, "Buffer", .public);
/// try (Declaration{ .value = raw_bytes }).emit(allocator, &context, "RawBytes", .public);
/// try (Declaration{ .value = c_bytes }).emit(allocator, &context, "CBytes", .public);
/// try (Declaration{ .value = text }).emit(allocator, &context, "Text", .public);
/// try (Declaration{ .value = failures }).emit(allocator, &context, "Failure", .public);
/// try (Declaration{ .value = result }).emit(allocator, &context, "Result", .public);
/// ```
///
/// ### Expected output
///
/// After finalizing and rendering the context:
///
/// ```zig
/// pub const Buffer = [4:0]u8;
/// pub const RawBytes = [*:0]allowzero align(1) const volatile u8;
/// pub const CBytes = [*c]u8;
/// pub const Text = [:0]const u8;
/// pub const Failure = error{Invalid};
/// pub const Result = error{Invalid}![:0]const u8;
/// ```
///
/// ## Calls and builtins
///
/// Calls compose with member access and other calls. With `Declaration` and the
/// context setup above, this builds a call through an imported namespace:
///
/// ```zig
/// const standard_library: Expression = .{ .builtin_call = .{
///     .name = "@import", .arguments = &.{.{ .string_literal = "\"std\"" }},
/// } };
/// const math_namespace: Expression = .{ .field_access = .{
///     .base = &standard_library, .name = "math",
/// } };
/// const rotate_function: Expression = .{ .field_access = .{
///     .base = &math_namespace, .name = "rotl",
/// } };
/// const rotation: Expression = .{ .call = .{
///     .callee = &rotate_function,
///     .arguments = &.{
///         .{ .identifier = "u8" },
///         .{ .integer_literal = "21" },
///         .{ .integer_literal = "1" },
///     },
/// } };
/// try (Declaration{ .value = rotation }).emit(allocator, &context, "answer", .public);
/// ```
///
/// ### Expected output
///
/// The generated declaration evaluates to 42:
///
/// ```zig
/// pub const answer = @import("std").math.rotl(u8, 21, 1);
/// ```
///
/// Emission writes the invocation; it does not call the function. Zig checks
/// names, argument counts, and types when the generated code is compiled.
///
/// ## Initializers and enum literals
///
/// Initializers compose values without declaring new types. With `Declaration`
/// and the context setup above:
///
/// ```zig
/// const options: Expression = .{ .struct_init = .{ .fields = &.{
///     .{ .name = "required", .value = .{ .identifier = "true" } },
/// } } };
/// const empty: Expression = .{ .struct_init = .{} };
/// const status: Expression = .{ .enum_literal = "unknown" };
/// const values: Expression = .{ .array_init = .{ .elements = &.{
///     status, .{ .enum_literal = "string" },
/// } } };
/// try (Declaration{ .value = options }).emit(allocator, &context, "options", .public);
/// try (Declaration{ .value = empty }).emit(allocator, &context, "empty", .public);
/// try (Declaration{ .value = status }).emit(allocator, &context, "status", .public);
/// try (Declaration{ .value = values }).emit(allocator, &context, "values", .public);
/// ```
///
/// ### Expected output
///
/// ```zig
/// pub const options = .{ .required = true };
/// pub const empty = .{};
/// pub const status = .unknown;
/// pub const values = .{ .unknown, .string };
/// ```
///
/// Set an initializer's `type_expression` to emit `Options{ ... }` or `[2]u8{ ... }`.
/// Named fields and positional elements cannot be mixed in one initializer.
/// Field names are syntax tokens; their values supply the child AST nodes.
///
/// ## Typed initializers
///
/// With `Declaration` and a fresh context, an explicit type selects a named
/// struct initializer or a typed array initializer. The generated file must
/// separately declare `Options`, for example `const Options = struct { required: bool };`.
///
/// ```zig
/// const options_type: Expression = .{ .identifier = "Options" };
/// const options: Expression = .{ .struct_init = .{
///     .type_expression = &options_type,
///     .fields = &.{.{ .name = "required", .value = .{ .identifier = "true" } }},
///     .trailing_comma = true,
/// } };
/// const byte_type: Expression = .{ .identifier = "u8" };
/// const length: Expression = .{ .integer_literal = "2" };
/// const pair_type: Expression = .{ .array_type = .{
///     .length = &length, .child_type = &byte_type,
/// } };
/// const bytes: Expression = .{ .array_init = .{
///     .type_expression = &pair_type,
///     .elements = &.{ .{ .integer_literal = "1" }, .{ .integer_literal = "2" } },
/// } };
/// try (Declaration{ .value = options }).emit(allocator, &context, "options", .public);
/// try (Declaration{ .value = bytes }).emit(allocator, &context, "bytes", .public);
/// ```
///
/// ### Expected output
///
/// ```zig
/// pub const options = Options{
///     .required = true,
/// };
/// pub const bytes = [2]u8{ 1, 2 };
/// ```
pub const Expression = union(enum) {
    /// One nonnegative Zig integer numeral, such as `42` or `0xff`.
    /// For `-1`, use `.negate` around `.integer_literal = "1"`.
    integer_literal: []const u8,
    /// Complete quoted Zig string spelling, e.g. `.string_literal = "\"hello\""`.
    /// Contents are copied verbatim; this does not quote or escape raw text.
    string_literal: []const u8,
    /// Complete Zig character spelling, e.g. `.char_literal = "'x'"`.
    char_literal: []const u8,
    /// A variable/type identifier such as `counter` or `u32`, or an identifier
    /// AST literal such as `true`, `false`, or `null`. No name lookup is done.
    identifier: []const u8,
    /// Enum literal `.unknown` or `.string`; supply the name without its period.
    /// Escaped identifiers include their full spelling, e.g. `@"error"`.
    /// Zig resolves the target enum or tagged union from the surrounding context.
    enum_literal: []const u8,
    /// A borrowed generator's anonymous type expression. Use `fromType` to bind
    /// a descriptor to its `emitType` method without importing concrete generators.
    /// The method runs during emission in the same context; no root is registered.
    type_description: struct {
        /// Borrowed descriptor address, retained until emission finishes.
        descriptor: *const anyopaque,
        /// Typed adapter installed by `fromType`; propagates the generator's errors.
        emit_type: *const fn (*const anyopaque, std.mem.Allocator, *AstContext) anyerror!std.zig.Ast.Node.Index,
    },

    /// `-operand`; the child is grouped automatically when needed.
    negate: *const Expression,
    /// Pointer value `&value`; the child must be addressable in generated Zig.
    /// Use `.pointer_type` to describe the type `*T` instead.
    address_of: *const Expression,
    /// `try operand`: unwrap success or return its error from the enclosing function.
    /// The child must resolve to an error union; Zig checks the surrounding return
    /// type when compiling the output. This does not handle errors during emission.
    ///
    /// Example: `.{ .@"try" = &read_call }` emits `try read(bytes)` when `read_call`
    /// describes that call. A member access on this expression emits
    /// `(try read(bytes)).value`, preserving which result is unwrapped.
    @"try": *const Expression,
    /// `?T`, where the borrowed child expression must resolve to a type.
    optional_type: *const Expression,
    /// `[length]T` or `[length:sentinel]T`; all children are borrowed expressions.
    /// The length must resolve to a comptime integer and the sentinel to a value
    /// of the element type. Zig checks those semantics when compiling the output.
    /// For example, length `4`, sentinel `0`, and child type `u8` emit `[4:0]u8`.
    array_type: struct {
        /// Element count expression, without brackets.
        length: *const Expression,
        /// Expression resolving to the array element type.
        child_type: *const Expression,
        /// Null omits `:sentinel`; the sentinel is excluded from the length.
        sentinel: ?*const Expression = null,
    },
    /// Pointer type `*T`, `[*]T`, `[*:sentinel]T`, or `[*c]T`.
    /// Defaults preserve the single-item pointer API. This does not take an address.
    /// Address spaces and packed-field bit ranges are not supported.
    pointer_type: struct {
        /// Borrowed expression resolving to the pointed-to type.
        child_type: *const Expression,
        /// Select the pointer syntax. Only `.many` accepts a sentinel expression.
        /// `.single` emits `*T`; `.{ .many = null }` emits `[*]T`;
        /// `.{ .many = &zero }` emits `[*:0]T`; `.c` emits `[*c]T`.
        kind: union(enum) {
            /// One pointed-to value; no sentinel.
            single,
            /// Unknown-length sequence, optionally terminated by a sentinel.
            many: ?*const Expression,
            /// C-interoperability pointer; no sentinel.
            c,
        } = .single,
        /// Qualify the pointee as const; independent of `const`/`var` bindings.
        is_const: bool = false,
        /// Emit `volatile`, preserving observable accesses through the pointer.
        is_volatile: bool = false,
        /// Emit `allowzero`; zero becomes an allowed address, not an optional.
        /// Leave false for `.c`: C pointers already allow zero, and Zig rejects
        /// an explicit `allowzero` qualifier on them.
        is_allowzero: bool = false,
        /// Borrowed byte-alignment expression; null omits `align(...)`.
        alignment: ?*const Expression = null,
    },
    /// Slice type `[]T` or `[:sentinel]T`, with optional pointer qualifiers.
    /// For example, sentinel `0` and is_const emit `[:0]const T`.
    slice_type: struct {
        /// Borrowed expression resolving to the slice element type.
        child_type: *const Expression,
        /// Borrowed terminator expression; null emits an ordinary `[]T` slice.
        sentinel: ?*const Expression = null,
        /// Qualify the elements as const; independent of the binding's kind.
        is_const: bool = false,
        /// Emit `volatile` for accesses through the slice's pointer.
        is_volatile: bool = false,
        /// Emit `allowzero` for the slice's pointer.
        is_allowzero: bool = false,
        /// Borrowed byte-alignment expression; null omits `align(...)`.
        alignment: ?*const Expression = null,
    },
    /// Borrowed complete identifier spellings, such as `&.{"Invalid", "Missing"}`.
    /// Emits `error{ Invalid, Missing }`; an empty slice emits `error{}`.
    /// Supply escaped identifiers yourself. Names are tokens, not container field nodes.
    error_set_type: []const []const u8,
    /// Explicit error union `Error!T`. Use an identifier or inline error set on
    /// the left; the payload may be any composed type. This does not emit the
    /// function-specific inferred form `!T`. Nested unions associate to the right.
    error_union_type: struct {
        /// Borrowed expression resolving to an error set.
        error_set: *const Expression,
        /// Borrowed expression resolving to the success payload type.
        payload_type: *const Expression,
    },
    /// `left << right`, with automatic grouping of nested operands.
    shift_left: struct {
        /// Value expression to shift.
        left: *const Expression,
        /// Shift amount expression.
        right: *const Expression,
    },
    /// Qualified access such as `limits.maximum` or `schema.Reading`.
    field_access: struct {
        /// Expression before the period, grouped when its precedence requires it.
        base: *const Expression,
        /// Complete identifier spelling after the period; no leading `.`.
        name: []const u8,
    },
    /// Named initializer `.{ .required = true }` or `Options{ .required = true }`.
    /// This constructs a value, including a tagged-union payload, not a type.
    struct_init: struct {
        /// Borrowed explicit type; null emits the inferred form `.{ ... }`.
        type_expression: ?*const Expression = null,
        /// Borrowed ordered field assignments; empty emits `.{}` or `Type{}`.
        fields: []const InitializerField = &.{},
        /// Append a comma after the final field, making Zig render one per line.
        /// Ignored for empty initializers; false keeps compact formatting.
        trailing_comma: bool = false,
    },
    /// Positional initializer `.{ 1, 2 }` or `[2]u8{ 1, 2 }` for tuples/arrays.
    /// An empty list uses the same AST form as an empty named initializer.
    array_init: struct {
        /// Borrowed explicit type; null emits the inferred form `.{ ... }`.
        type_expression: ?*const Expression = null,
        /// Borrowed ordered element expressions; no field names are emitted.
        elements: []const Expression = &.{},
        /// Append a comma after the final element; Zig controls line wrapping.
        /// Ignored for empty initializers.
        trailing_comma: bool = false,
    },
    /// Ordinary invocation `callee(arguments)`, including methods and functions
    /// returning types. Compose qualified callees with `.field_access`.
    ///
    /// The callee is grouped when required; arguments are complete expressions.
    /// For example, `.call = .{ .callee = &read_function }` emits `read()`.
    call: struct {
        /// Borrowed expression resolving to a function, such as `std.EnumArray`.
        callee: *const Expression,
        /// Borrowed arguments in source order; empty emits `()`. No trailing comma.
        arguments: []const Expression = &.{},
    },
    /// Compiler invocation such as `@import("std")`, `@This()`, or
    /// `@FieldType(Reading, "value")`. The builtin name is a token, not a callee
    /// expression.
    ///
    /// For example, `.builtin_call = .{ .name = "@This" }` emits `@This()`.
    builtin_call: struct {
        /// Complete builtin spelling including `@`; copied without validation.
        name: []const u8,
        /// Borrowed arguments in source order; empty emits `()`. No trailing comma.
        arguments: []const Expression = &.{},
    },
    /// Explicit `(expression)` even when precedence would not require grouping.
    grouped: *const Expression,

    /// A borrowed `.name = value` assignment inside a struct/union initializer.
    ///
    /// Unlike a container field, this has no type or default value: `value` is
    /// required. The description `.{ .name = "kind", .value = .{ .enum_literal = "string" } }`
    /// emits `.kind = .string`.
    ///
    /// The enclosing initializer supplies separators and owns no description data.
    pub const InitializerField = struct {
        /// Complete identifier spelling without a leading period; not escaped.
        name: []const u8,
        /// Expression assigned to this field; all nested descriptions are borrowed.
        value: Expression,
    };

    /// Borrow a descriptor implementing `emitType(allocator, context) !Ast.Node.Index`.
    ///
    /// ### Descriptor contract
    ///
    /// - Accepts a single-item pointer, including pointers returned by generator `init`.
    /// - Enum, union, struct, and function descriptions work without special cases.
    /// - The descriptor's method must accept a const receiver and emit a complete
    ///   type expression, without a declaration prefix, semicolon, or root registration.
    ///
    /// ### Ownership and errors
    ///
    /// No allocation, copying, validation, or emission happens here. Keep the
    /// descriptor and its borrowed children alive until `emit` returns; the graph
    /// must be acyclic. Later edits through a mutable alias are observed at emission.
    /// Each occurrence emits fresh syntax; use an identifier to refer to one named type.
    /// A function pointer restores the descriptor's checked pointer type and calls
    /// `emitType`. Its validation/allocation errors propagate without translation.
    ///
    /// ### Example
    ///
    /// With the type's context setup and `Declaration` import:
    ///
    /// ```zig
    /// const EnumDeclaration = @import("zast").EnumDeclaration;
    /// const tags: EnumDeclaration = .{ .backing_type = "u8", .fields = &.{
    ///     .{ .name = "none", .value = .{ .integer_literal = "0" } },
    ///     .{ .name = "text", .value = .{ .integer_literal = "1" } },
    /// } };
    /// const standard_library: Expression = .{ .builtin_call = .{
    ///     .name = "@import",
    ///     .arguments = &.{.{ .string_literal = "\"std\"" }},
    /// } };
    /// const array_function: Expression = .{ .field_access = .{
    ///     .base = &standard_library, .name = "EnumArray",
    /// } };
    /// const counts: Expression = .{ .call = .{
    ///     .callee = &array_function,
    ///     .arguments = &.{ Expression.fromType(&tags), .{ .identifier = "u32" } },
    /// } };
    /// try (Declaration{ .value = counts }).emit(allocator, &context, "Counts", .public);
    /// ```
    ///
    /// ### Expected output
    ///
    /// ```zig
    /// pub const Counts = @import("std").EnumArray(enum(u8) {
    ///     none = 0,
    ///     text = 1,
    /// }, u32);
    /// ```
    pub fn fromType(description: anytype) Expression {
        const pointer_info = @typeInfo(@TypeOf(description));
        if (pointer_info != .pointer or pointer_info.pointer.size != .one)
            @compileError("fromType expects a single-item pointer to a type descriptor");
        const Descriptor = pointer_info.pointer.child;
        const borrowed: *const Descriptor = description;
        const Adapter = struct {
            fn emitType(erased: *const anyopaque, allocator: std.mem.Allocator, context: *AstContext) anyerror!std.zig.Ast.Node.Index {
                const typed: *const Descriptor = @ptrCast(@alignCast(erased));
                return typed.emitType(allocator, context);
            }
        };
        return .{ .type_description = .{ .descriptor = borrowed, .emit_type = Adapter.emitType } };
    }

    /// Binding strength of the supported expression forms, weakest to strongest.
    /// Used internally for grouping; ordinary callers can just use `emit`.
    pub const Precedence = enum(u8) {
        /// Binary left shift, `left << right`.
        shift,
        /// Typed `T{ ... }`; group in prefix/type and suffix operands so its
        /// braces cannot attach to a different type or escape a suffix chain.
        initializer,
        /// Prefix operators and type constructors, including explicit error unions.
        /// Borrowed type emitters use this conservatively: e.g. a function type's
        /// return type must not consume a following member access or call.
        prefix,
        /// Ordinary calls and member access, such as `read().value`.
        suffix,
        /// Literals, identifiers, inferred initializers, builtins, and grouped expressions.
        primary,
    };

    /// Return the binding strength used when placing this expression in a parent.
    /// This is grouping metadata, not a check of the expression's Zig type or validity.
    pub fn precedence(expression: Expression) Precedence {
        return switch (expression) {
            .shift_left => .shift,
            .negate, .address_of, .@"try", .optional_type, .array_type, .pointer_type, .slice_type, .error_union_type, .type_description => .prefix,
            .field_access, .call => .suffix,
            inline .struct_init, .array_init => |initializer| if (initializer.type_expression != null) .initializer else .primary,
            .integer_literal, .string_literal, .char_literal, .identifier, .enum_literal, .error_set_type, .builtin_call, .grouped => .primary,
        };
    }

    /// Append tokens and nodes, returning this expression's node index.
    ///
    /// Adds grouping when needed but no `;`, field comma, or named declaration.
    /// The enclosing construct must attach the returned node in the same context.
    /// Pass the context's buffer allocator; descriptions can expire afterward.
    ///
    /// ### Errors
    ///
    /// Propagates allocation errors and borrowed type emitters' validation errors.
    /// No partial-output rollback; discard the context after an emission failure.
    pub fn emit(
        expression: Expression,
        allocator: std.mem.Allocator,
        context: *AstContext,
    ) anyerror!std.zig.Ast.Node.Index {
        return emitAtPrecedence(expression, allocator, context, .shift);
    }

    /// Emit a present optional expression between fixed prefix and suffix tokens.
    ///
    /// Accepts `?Expression` or an optional pointer to one; typed `null` emits no
    /// syntax. Pass an explicitly typed optional, rather than untyped `null`.
    /// Prefix and suffix tags must have fixed lexemes, such as `.colon` or `.r_paren`.
    /// Uses ordinary expression precedence. Errors retain partial output.
    /// Borrows the description until emission ends; context owns the result.
    ///
    /// ### Example
    ///
    /// With the type's allocator and context setup, an annotation can be emitted
    /// after its name token (the caller still attaches the returned node):
    ///
    /// ```zig
    /// const annotation: ?Expression = .{ .identifier = "u32" };
    /// const type_node = try Expression.emitOptional(
    ///     annotation, allocator, &context, &.{.colon}, &.{},
    /// );
    /// // type_node contains the identifier node; no declaration is created.
    /// ```
    ///
    /// ### Expected output
    ///
    /// Appended source bytes: `": u32 "`. A `null` annotation returns
    /// `.none` and leaves source, tokens, and nodes unchanged.
    pub fn emitOptional(
        expression: anytype,
        allocator: std.mem.Allocator,
        context: *AstContext,
        comptime prefix: []const std.zig.Token.Tag,
        comptime suffix: []const std.zig.Token.Tag,
    ) anyerror!std.zig.Ast.Node.OptionalIndex {
        const value = expression orelse return .none;
        inline for (prefix) |tag| _ = try context.token(allocator, tag, null);
        const value_node = try value.emit(allocator, context);
        inline for (suffix) |tag| _ = try context.token(allocator, tag, null);
        return value_node.toOptional();
    }

    /// Select a fixed struct_init/array_init layout and its optional comma variant.
    fn initializerTag(comptime kind: std.meta.Tag(Expression), comptime suffix: []const u8, trailing: bool) std.zig.Ast.Node.Tag {
        const tag_name = @tagName(kind) ++ suffix;
        return if (trailing) @field(std.zig.Ast.Node.Tag, tag_name ++ "_comma") else @field(std.zig.Ast.Node.Tag, tag_name);
    }

    /// Emit an operand, inserting parentheses below its parent's binding strength.
    /// An explicit `.grouped` always emits its own pair of parentheses.
    fn emitAtPrecedence(
        expression: Expression,
        allocator: std.mem.Allocator,
        context: *AstContext,
        minimum_precedence: Precedence,
    ) anyerror!std.zig.Ast.Node.Index {
        const grouped_operand: ?Expression = switch (expression) {
            .grouped => |operand| operand.*,
            else => if (@backingInt(expression.precedence()) < @backingInt(minimum_precedence))
                expression
            else
                null,
        };
        if (grouped_operand) |operand| {
            const opening_token = try context.token(allocator, .l_paren, null);
            const operand_node = try emitAtPrecedence(operand, allocator, context, .shift);
            const closing_token = try context.token(allocator, .r_paren, null);
            return context.addNode(allocator, .grouped_expression, opening_token, .{
                .node_and_token = .{ operand_node, closing_token },
            });
        }

        switch (expression) {
            .type_description => |description| return description.emit_type(description.descriptor, allocator, context),
            inline .identifier, .enum_literal, .integer_literal, .string_literal, .char_literal => |spelling, kind| {
                const syntax_name = switch (kind) {
                    .integer_literal => "number_literal",
                    .enum_literal => "identifier",
                    else => @tagName(kind),
                };
                const token_tag = @field(std.zig.Token.Tag, syntax_name);
                const node_tag = if (kind == .enum_literal) .enum_literal else @field(std.zig.Ast.Node.Tag, syntax_name);
                if (kind == .enum_literal) _ = try context.token(allocator, .period, null);
                const main_token = try context.token(allocator, token_tag, spelling);
                return context.addNode(allocator, node_tag, main_token, undefined);
            },
            inline .negate, .address_of, .@"try", .optional_type => |operand, kind| {
                const token_tag: std.zig.Token.Tag, const node_tag: std.zig.Ast.Node.Tag = comptime switch (kind) {
                    .negate => .{ .minus, .negation },
                    .address_of => .{ .ampersand, .address_of },
                    .@"try" => .{ .keyword_try, .@"try" },
                    .optional_type => .{ .question_mark, .optional_type },
                    else => unreachable,
                };
                const operator_token = try context.token(allocator, token_tag, null);
                const operand_node = try emitAtPrecedence(operand.*, allocator, context, .prefix);
                return context.addNode(allocator, node_tag, operator_token, .{ .node = operand_node });
            },
            .array_type => |array| {
                const opening_token = try context.token(allocator, .l_bracket, null);
                const length_node = try array.length.emit(allocator, context);
                const sentinel_node = try emitOptional(array.sentinel, allocator, context, &.{.colon}, &.{});
                _ = try context.token(allocator, .r_bracket, null);
                const child_node = try emitAtPrecedence(array.child_type.*, allocator, context, .prefix);
                if (sentinel_node.unwrap()) |sentinel| {
                    // ArrayTypeSentinel stores the sentinel and element type, in order.
                    const extra_index = try context.addExtra(allocator, &.{ @backingInt(sentinel), @backingInt(child_node) });
                    return context.addNode(allocator, .array_type_sentinel, opening_token, .{
                        .node_and_extra = .{ length_node, extra_index },
                    });
                }
                return context.addNode(allocator, .array_type, opening_token, .{
                    .node_and_node = .{ length_node, child_node },
                });
            },
            inline .pointer_type, .slice_type => |type_description, kind| {
                const is_single = if (kind == .pointer_type) type_description.kind == .single else false;
                const type_token = try context.token(allocator, if (is_single) .asterisk else .l_bracket, null);
                const sentinel_expression = if (kind == .slice_type) type_description.sentinel else switch (type_description.kind) {
                    .many => |sentinel| sentinel,
                    .single, .c => null,
                };
                var sentinel_node: std.zig.Ast.Node.OptionalIndex = .none;
                if (!is_single) {
                    if (kind == .pointer_type) {
                        _ = try context.token(allocator, .asterisk, null);
                        if (type_description.kind == .c) _ = try context.token(allocator, .identifier, "c");
                    }
                    sentinel_node = try emitOptional(sentinel_expression, allocator, context, &.{.colon}, &.{});
                    _ = try context.token(allocator, .r_bracket, null);
                }
                if (type_description.is_allowzero) _ = try context.token(allocator, .keyword_allowzero, null);
                const alignment_node = try emitOptional(type_description.alignment, allocator, context, &.{ .keyword_align, .l_paren }, &.{.r_paren});
                if (type_description.is_const) _ = try context.token(allocator, .keyword_const, null);
                if (type_description.is_volatile) _ = try context.token(allocator, .keyword_volatile, null);
                const child_node = try emitAtPrecedence(type_description.child_type.*, allocator, context, .prefix);
                if (sentinel_node != .none and alignment_node != .none) {
                    // PtrType needs three slots: sentinel, alignment, and absent address space.
                    const extra_index = try context.addExtra(allocator, &.{
                        @backingInt(sentinel_node), @backingInt(alignment_node), @backingInt(std.zig.Ast.Node.OptionalIndex.none),
                    });
                    return context.addNode(allocator, .ptr_type, type_token, .{
                        .extra_and_node = .{ extra_index, child_node },
                    });
                }
                // The simple layouts store either alignment or sentinel inline.
                return context.addNode(allocator, if (sentinel_node == .none) .ptr_type_aligned else .ptr_type_sentinel, type_token, .{
                    .opt_node_and_node = .{ if (sentinel_node == .none) alignment_node else sentinel_node, child_node },
                });
            },
            .error_set_type => |names| {
                const error_token = try context.token(allocator, .keyword_error, null);
                const opening_token = try context.token(allocator, .l_brace, null);
                for (names, 0..) |name, name_index| {
                    if (name_index != 0) _ = try context.token(allocator, .comma, null);
                    _ = try context.token(allocator, .identifier, name);
                }
                const closing_token = try context.token(allocator, .r_brace, null);
                return context.addNode(allocator, .error_set_decl, error_token, .{
                    .token_and_token = .{ opening_token, closing_token },
                });
            },
            inline .shift_left, .error_union_type => |operands, kind| {
                const is_shift = kind == .shift_left;
                const left_operand = if (is_shift) operands.left else operands.error_set;
                const right_operand = if (is_shift) operands.right else operands.payload_type;
                const left_node = try emitAtPrecedence(left_operand.*, allocator, context, if (is_shift) .shift else .suffix);
                const operator_token = try context.token(allocator, if (is_shift) .angle_bracket_angle_bracket_left else .bang, null);
                // Shifts group a right-hand shift; error unions require a suffix expression on the left.
                const right_node = try emitAtPrecedence(right_operand.*, allocator, context, .prefix);
                return context.addNode(allocator, if (is_shift) .shl else .error_union, operator_token, .{
                    .node_and_node = .{ left_node, right_node },
                });
            },
            .field_access => |access| {
                const base_node = try emitAtPrecedence(access.base.*, allocator, context, .suffix);
                const period_token = try context.token(allocator, .period, null);
                const member_token = try context.token(allocator, .identifier, access.name);
                return context.addNode(allocator, .field_access, period_token, .{
                    .node_and_token = .{ base_node, member_token },
                });
            },
            inline .struct_init, .array_init => |initializer, kind| {
                const type_node: ?std.zig.Ast.Node.Index = if (initializer.type_expression) |type_expression|
                    try emitAtPrecedence(type_expression.*, allocator, context, .prefix)
                else
                    null;
                if (type_node == null) _ = try context.token(allocator, .period, null);
                const opening_token = try context.token(allocator, .l_brace, null);
                const entries = if (kind == .struct_init) initializer.fields else initializer.elements;
                // Reserve before recursion; children may append or reallocate extra_data.
                var children = try ChildNodes.init(allocator, context, entries.len, if (type_node != null) 1 else 2);
                for (entries, 0..) |entry, entry_index| {
                    if (entry_index != 0) _ = try context.token(allocator, .comma, null);
                    if (kind == .struct_init) {
                        _ = try context.token(allocator, .period, null);
                        _ = try context.token(allocator, .identifier, entry.name);
                        _ = try context.token(allocator, .equal, null);
                    }
                    const value = if (kind == .struct_init) entry.value else entry;
                    children.set(context, entry_index, try value.emit(allocator, context));
                }
                const trailing = initializer.trailing_comma and entries.len != 0;
                if (trailing) _ = try context.token(allocator, .comma, null);
                _ = try context.token(allocator, .r_brace, null);
                const node_tag: std.zig.Ast.Node.Tag = if (entries.len == 0)
                    (if (type_node != null) .struct_init_one else .struct_init_dot_two)
                else if (type_node != null)
                    (if (children.uses_extra) initializerTag(kind, "", trailing) else initializerTag(kind, "_one", trailing))
                else if (children.uses_extra)
                    initializerTag(kind, "_dot", trailing)
                else
                    initializerTag(kind, "_dot_two", trailing);
                if (!children.uses_extra) return context.addNode(allocator, node_tag, opening_token, if (type_node) |explicit_type|
                    (if (kind == .array_init and entries.len != 0)
                        .{ .node_and_node = .{ explicit_type, children.inline_nodes[0].unwrap().? } }
                    else
                        .{ .node_and_opt_node = .{ explicit_type, children.inline_nodes[0] } })
                else
                    .{ .opt_node_and_opt_node = .{ children.inline_nodes[0], children.inline_nodes[1] } });
                if (type_node) |explicit_type| {
                    const range_index = try children.appendRange(allocator, context);
                    return context.addNode(allocator, node_tag, opening_token, .{ .node_and_extra = .{ explicit_type, range_index } });
                }
                return context.addNode(allocator, node_tag, opening_token, .{
                    .extra_range = children.range,
                });
            },
            inline .call, .builtin_call => |invocation, kind| {
                const is_builtin = kind == .builtin_call;
                const callee_node: ?std.zig.Ast.Node.Index = if (is_builtin) null else try emitAtPrecedence(invocation.callee.*, allocator, context, .suffix);
                const builtin_token: ?std.zig.Ast.TokenIndex = if (is_builtin) try context.token(allocator, .builtin, invocation.name) else null;
                const opening_token = try context.token(allocator, .l_paren, null);
                const main_token = builtin_token orelse opening_token;
                // Reserve first: nested arguments may append extra data or reallocate.
                var children = try ChildNodes.init(allocator, context, invocation.arguments.len, if (is_builtin) 2 else 1);
                for (invocation.arguments, 0..) |argument, argument_index| {
                    if (argument_index != 0) _ = try context.token(allocator, .comma, null);
                    children.set(context, argument_index, try argument.emit(allocator, context));
                }
                _ = try context.token(allocator, .r_paren, null);
                if (!children.uses_extra) return context.addNode(allocator, if (is_builtin) .builtin_call_two else .call_one, main_token, if (is_builtin)
                    .{ .opt_node_and_opt_node = .{ children.inline_nodes[0], children.inline_nodes[1] } }
                else
                    .{ .node_and_opt_node = .{ callee_node.?, children.inline_nodes[0] } });
                if (is_builtin) return context.addNode(allocator, .builtin_call, main_token, .{
                    .extra_range = children.range,
                });
                // Ordinary calls need a SubRange because the callee occupies one slot.
                const range_index = try children.appendRange(allocator, context);
                return context.addNode(allocator, .call, main_token, .{
                    .node_and_extra = .{ callee_node.?, range_index },
                });
            },
            .grouped => unreachable, // Handled before the switch.
        }
    }
};
