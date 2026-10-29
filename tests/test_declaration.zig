//! Named declarations combining a binding, an optional type, and a value.
//!
//! ## Coverage
//!
//! - Primitive and composed type expressions used as type aliases.
//! - Inferred and annotated `const`/`var` bindings with public/private visibility.
//! - Slice element constness, pointer mutability, and address-of initializers.
//! - String, optional, and boolean values paired with explicit types.
//! - Allocation-failure cleanup during declaration and slice emission.
//!
//! Expected source is parsed and formatted with `std.zig.Ast`, then compared
//! with generated output. These are syntax/render checks, not compilation tests.
//!
//! Run the component tests with the full suite from `zast/`:
//!
//! ```sh
//! zig build test
//! ```

const std = @import("std");
const zast = @import("zast");
const helpers = @import("helpers.zig");

fn expectDeclaration(
    declaration: anytype,
    name: []const u8,
    visibility: zast.Declaration.Visibility,
    expected_source: [:0]const u8,
) !void {
    const allocator = std.testing.allocator;
    const rendered = try helpers.renderNamedDescription(allocator, declaration, name, visibility);
    defer allocator.free(rendered);
    try helpers.expectFormattedSource(allocator, expected_source, rendered);
}

test "type aliases name primitive and composed type expressions" {
    const integer_type: zast.Expression = .{ .identifier = "u32" };
    const byte_type: zast.Expression = .{ .identifier = "u8" };
    const const_byte_pointer: zast.Expression = .{
        .pointer_type = .{ .child_type = &byte_type, .is_const = true },
    };
    const readonly_bytes: zast.Expression = .{
        .slice_type = .{ .child_type = &byte_type, .is_const = true },
    };
    const examples = [_]struct {
        name: []const u8,
        type_expression: zast.Expression,
        expected_source: [:0]const u8,
    }{
        .{
            .name = "Count",
            .type_expression = integer_type,
            .expected_source = "pub const Count = u32;",
        },
        .{
            .name = "MaybeCount",
            .type_expression = .{ .optional_type = &integer_type },
            .expected_source = "pub const MaybeCount = ?u32;",
        },
        .{
            .name = "BytePointer",
            .type_expression = const_byte_pointer,
            .expected_source = "pub const BytePointer = *const u8;",
        },
        .{
            .name = "Bytes",
            .type_expression = .{ .slice_type = .{ .child_type = &byte_type } },
            .expected_source = "pub const Bytes = []u8;",
        },
        .{
            .name = "ReadOnlyBytes",
            .type_expression = readonly_bytes,
            .expected_source = "pub const ReadOnlyBytes = []const u8;",
        },
        .{
            .name = "MaybeBytes",
            .type_expression = .{ .optional_type = &readonly_bytes },
            .expected_source = "pub const MaybeBytes = ?[]const u8;",
        },
        .{
            .name = "BytePointers",
            .type_expression = .{ .slice_type = .{ .child_type = &const_byte_pointer } },
            .expected_source = "pub const BytePointers = []*const u8;",
        },
    };
    for (examples) |example| {
        // The initializer is a type expression, so the const names a type.
        const declaration: zast.Declaration = .{ .value = example.type_expression };
        try expectDeclaration(declaration, example.name, .public, example.expected_source);
    }
}

test "a const can infer its type from a value expression" {
    const declaration: zast.Declaration = .{
        .value = .{ .integer_literal = "42" },
    };
    try expectDeclaration(declaration, "answer", .private, "const answer = 42;");
}

test "a const can have an explicit type annotation" {
    const declaration: zast.Declaration = .{
        .type_expression = .{ .identifier = "u32" },
        .value = .{ .integer_literal = "42" },
    };
    try expectDeclaration(declaration, "answer", .public, "pub const answer: u32 = 42;");
}

test "var creates a mutable binding with an explicit type" {
    const declaration: zast.Declaration = .{
        .kind = .variable,
        .type_expression = .{ .identifier = "u32" },
        .value = .{ .integer_literal = "0" },
    };
    try expectDeclaration(declaration, "counter", .private, "var counter: u32 = 0;");
}

test "a byte slice type and string value form a const declaration" {
    const byte_type: zast.Expression = .{ .identifier = "u8" };
    const declaration: zast.Declaration = .{
        .type_expression = .{ .slice_type = .{ .child_type = &byte_type, .is_const = true } },
        .value = .{ .string_literal = "\"hello\"" },
    };
    try expectDeclaration(declaration, "message", .private, "const message: []const u8 = \"hello\";");
}

test "var can rebind a slice whose elements are const" {
    const byte_type: zast.Expression = .{ .identifier = "u8" };
    const declaration: zast.Declaration = .{
        .kind = .variable,
        .type_expression = .{ .slice_type = .{ .child_type = &byte_type, .is_const = true } },
        .value = .{ .string_literal = "\"hello\"" },
    };
    // var applies to message; the inner const applies to its bytes.
    try expectDeclaration(declaration, "message", .public, "pub var message: []const u8 = \"hello\";");
}

test "an optional type and null value form a var declaration" {
    const integer_type: zast.Expression = .{ .identifier = "u32" };
    const declaration: zast.Declaration = .{
        .kind = .variable,
        .type_expression = .{ .optional_type = &integer_type },
        .value = .{ .identifier = "null" },
    };
    try expectDeclaration(declaration, "maybe_count", .private, "var maybe_count: ?u32 = null;");
}

test "a bool type and false value form a var declaration" {
    const declaration: zast.Declaration = .{
        .kind = .variable,
        .type_expression = .{ .identifier = "bool" },
        .value = .{ .identifier = "false" },
    };
    try expectDeclaration(declaration, "enabled", .private, "var enabled: bool = false;");
}

/// Emit the referenced variable before the pointer declaration in the same AST.
const CounterPointer = struct {
    pointer_declaration: zast.Declaration,

    pub fn emit(
        example: CounterPointer,
        allocator: std.mem.Allocator,
        context: *zast.AstContext,
        name: []const u8,
        visibility: zast.Declaration.Visibility,
    ) !void {
        const counter: zast.Declaration = .{
            .kind = .variable,
            .type_expression = .{ .identifier = "u32" },
            .value = .{ .integer_literal = "0" },
        };
        try counter.emit(allocator, context, "counter", .private);
        try example.pointer_declaration.emit(allocator, context, name, visibility);
    }
};

test "address-of creates inferred, typed, const, reassignable, and optional pointers" {
    const integer_type: zast.Expression = .{ .identifier = "u32" };
    const pointer_type: zast.Expression = .{ .pointer_type = .{ .child_type = &integer_type } };
    const counter_reference: zast.Expression = .{ .identifier = "counter" };
    const counter_address: zast.Expression = .{ .address_of = &counter_reference };
    const examples = [_]struct {
        name: []const u8,
        declaration: zast.Declaration,
        expected_source: [:0]const u8,
    }{
        .{
            .name = "inferred_ptr",
            .declaration = .{ .value = counter_address },
            .expected_source = "var counter: u32 = 0; const inferred_ptr = &counter;",
        },
        .{
            .name = "counter_ptr",
            .declaration = .{ .type_expression = pointer_type, .value = counter_address },
            .expected_source = "var counter: u32 = 0; const counter_ptr: *u32 = &counter;",
        },
        .{
            .name = "readonly_ptr",
            .declaration = .{
                .type_expression = .{ .pointer_type = .{ .child_type = &integer_type, .is_const = true } },
                .value = counter_address,
            },
            .expected_source = "var counter: u32 = 0; const readonly_ptr: *const u32 = &counter;",
        },
        .{
            .name = "reassignable_ptr",
            .declaration = .{ .kind = .variable, .type_expression = pointer_type, .value = counter_address },
            .expected_source = "var counter: u32 = 0; var reassignable_ptr: *u32 = &counter;",
        },
        .{
            .name = "maybe_ptr",
            .declaration = .{ .type_expression = .{ .optional_type = &pointer_type }, .value = counter_address },
            .expected_source = "var counter: u32 = 0; const maybe_ptr: ?*u32 = &counter;",
        },
    };
    for (examples) |example| {
        try expectDeclaration(
            CounterPointer{ .pointer_declaration = example.declaration },
            example.name,
            .private,
            example.expected_source,
        );
    }
}

fn declarationAllocationScenario(allocator: std.mem.Allocator) !void {
    const byte_type: zast.Expression = .{ .identifier = "u8" };
    const declaration: zast.Declaration = .{
        .kind = .variable,
        .type_expression = .{ .slice_type = .{ .child_type = &byte_type, .is_const = true } },
        .value = .{ .string_literal = "\"hello\"" },
    };
    const rendered = try helpers.renderNamedDescription(allocator, declaration, "message", .public);
    defer allocator.free(rendered);
}

test "declaration and slice emission clean up allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, declarationAllocationScenario, .{});
}
