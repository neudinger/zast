//! Type expressions and address-of expressions used by fields and declarations.
//!
//! ## Coverage
//!
//! - Optional and single-item pointer tokens, child links, and nested grouping.
//! - Array lengths, sentinels, computed lengths, and nested element types.
//! - Pointer and slice qualifiers, alignment, and independent sentinel links.
//! - Error-set spelling and storage, error-union operands, and precedence.
//! - Allocation-failure cleanup during expression emission and rendering.
//!
//! ## Running
//!
//! Run `zig build test` from the `zast` directory via `test_all.zig`.
//! Assertions inspect AST storage and compare rendered source with parsed
//! expectations. Some inputs are deliberately unresolved or semantically
//! invalid to isolate syntax and grouping.
//! Compile generated examples separately to check their semantic validity;
//! parser and renderer checks here do not type-check generated source.

const std = @import("std");
const zast = @import("zast");
const helpers = @import("helpers.zig");

fn expectRenderedFields(fields: []const zast.Field, expected_source: [:0]const u8) !void {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const union_decl = try zast.UnionDeclaration.init(arena.allocator(), .inferred, fields);
    const rendered = try helpers.renderDescription(allocator, union_decl);
    defer allocator.free(rendered);
    try helpers.expectFormattedSource(allocator, expected_source, rendered);
}

test "optional type links its question-mark token to the child type node" {
    const allocator = std.testing.allocator;
    var context: zast.AstContext = .{};
    defer context.deinit(allocator);
    _ = try context.addNode(allocator, .root, 0, undefined);

    const integer_type: zast.Expression = .{ .identifier = "u32" };
    const optional_integer: zast.Expression = .{ .optional_type = &integer_type };
    const optional_node = try optional_integer.emit(allocator, &context);
    const optional_index = @backingInt(optional_node);
    try std.testing.expectEqual(.optional_type, context.nodes.items(.tag)[optional_index]);

    const question_token = context.nodes.items(.main_token)[optional_index];
    try std.testing.expectEqual(.question_mark, context.tokens.items(.tag)[question_token]);
    const child_node = context.nodes.items(.data)[optional_index].node;
    try std.testing.expectEqual(.identifier, context.nodes.items(.tag)[@backingInt(child_node)]);
}

test "optional types compose with identifiers, qualified types, grouping, and other optionals" {
    const integer_type: zast.Expression = .{ .identifier = "u32" };
    const optional_integer: zast.Expression = .{ .optional_type = &integer_type };
    const namespace_expression: zast.Expression = .{ .identifier = "schema" };
    const qualified_type: zast.Expression = .{
        .field_access = .{ .base = &namespace_expression, .name = "Reading" },
    };
    const grouped_type: zast.Expression = .{ .grouped = &integer_type };
    const fields = [_]zast.Field{
        .{ .name = "number", .type_expression = optional_integer },
        .{ .name = "reading", .type_expression = .{ .optional_type = &qualified_type } },
        .{ .name = "nested", .type_expression = .{ .optional_type = &optional_integer } },
        .{ .name = "grouped", .type_expression = .{ .optional_type = &grouped_type } },
    };
    try expectRenderedFields(&fields,
        \\pub const Generated = union(enum) {
        \\    number: ?u32,
        \\    reading: ?schema.Reading,
        \\    nested: ??u32,
        \\    grouped: ?(u32),
        \\};
    );
}

fn optionalAllocationScenario(allocator: std.mem.Allocator) !void {
    var context: zast.AstContext = .{};
    defer context.deinit(allocator);
    _ = try context.addNode(allocator, .root, 0, undefined);
    const integer_type: zast.Expression = .{ .identifier = "u32" };
    const optional_integer: zast.Expression = .{ .optional_type = &integer_type };
    _ = try optional_integer.emit(allocator, &context);
}

test "optional type emission cleans up allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, optionalAllocationScenario, .{});
}

test "single-item pointer types link their asterisk token to the child type node" {
    const allocator = std.testing.allocator;
    for ([_]bool{ false, true }) |is_const| {
        var context: zast.AstContext = .{};
        defer context.deinit(allocator);
        _ = try context.addNode(allocator, .root, 0, undefined);
        const integer_type: zast.Expression = .{ .identifier = "u32" };
        const pointer_type: zast.Expression = .{
            .pointer_type = .{ .child_type = &integer_type, .is_const = is_const },
        };
        const pointer_node = try pointer_type.emit(allocator, &context);
        const pointer_index = @backingInt(pointer_node);
        try std.testing.expectEqual(.ptr_type_aligned, context.nodes.items(.tag)[pointer_index]);

        const pointer_token = context.nodes.items(.main_token)[pointer_index];
        try std.testing.expectEqual(.asterisk, context.tokens.items(.tag)[pointer_token]);
        if (is_const) try std.testing.expectEqual(.keyword_const, context.tokens.items(.tag)[pointer_token + 1]);
        const alignment_node, const child_node = context.nodes.items(.data)[pointer_index].opt_node_and_node;
        try std.testing.expectEqual(.none, alignment_node);
        try std.testing.expectEqual(.identifier, context.nodes.items(.tag)[@backingInt(child_node)]);
    }
}

test "single-item pointer types compose with const qualifiers, optionals, and other types" {
    const integer_type: zast.Expression = .{ .identifier = "u32" };
    const mutable_pointer: zast.Expression = .{ .pointer_type = .{ .child_type = &integer_type } };
    const const_pointer: zast.Expression = .{
        .pointer_type = .{ .child_type = &integer_type, .is_const = true },
    };
    const optional_integer: zast.Expression = .{ .optional_type = &integer_type };
    const namespace_expression: zast.Expression = .{ .identifier = "schema" };
    const qualified_type: zast.Expression = .{
        .field_access = .{ .base = &namespace_expression, .name = "Reading" },
    };
    const grouped_type: zast.Expression = .{ .grouped = &integer_type };
    const fields = [_]zast.Field{
        .{ .name = "mutable", .type_expression = mutable_pointer },
        .{ .name = "immutable", .type_expression = const_pointer },
        .{ .name = "optional_pointer", .type_expression = .{ .optional_type = &mutable_pointer } },
        .{ .name = "optional_const_pointer", .type_expression = .{ .optional_type = &const_pointer } },
        .{ .name = "pointer_to_optional", .type_expression = .{ .pointer_type = .{ .child_type = &optional_integer } } },
        .{ .name = "nested", .type_expression = .{ .pointer_type = .{ .child_type = &mutable_pointer } } },
        .{ .name = "nested_const", .type_expression = .{ .pointer_type = .{ .child_type = &const_pointer } } },
        .{ .name = "const_nested", .type_expression = .{ .pointer_type = .{ .child_type = &mutable_pointer, .is_const = true } } },
        .{ .name = "qualified", .type_expression = .{ .pointer_type = .{ .child_type = &qualified_type, .is_const = true } } },
        .{ .name = "grouped", .type_expression = .{ .pointer_type = .{ .child_type = &grouped_type } } },
    };
    try expectRenderedFields(&fields,
        \\pub const Generated = union(enum) {
        \\    mutable: *u32,
        \\    immutable: *const u32,
        \\    optional_pointer: ?*u32,
        \\    optional_const_pointer: ?*const u32,
        \\    pointer_to_optional: *?u32,
        \\    nested: **u32,
        \\    nested_const: **const u32,
        \\    const_nested: *const *u32,
        \\    qualified: *const schema.Reading,
        \\    grouped: *(u32),
        \\};
    );
}

test "address-of links the ampersand token to the referenced field expression" {
    const allocator = std.testing.allocator;
    var context: zast.AstContext = .{};
    defer context.deinit(allocator);
    _ = try context.addNode(allocator, .root, 0, undefined);
    const object_reference: zast.Expression = .{ .identifier = "reading" };
    const field_reference: zast.Expression = .{
        .field_access = .{ .base = &object_reference, .name = "count" },
    };
    const field_address: zast.Expression = .{ .address_of = &field_reference };
    const address_node = try field_address.emit(allocator, &context);
    const address_index = @backingInt(address_node);
    try std.testing.expectEqual(.address_of, context.nodes.items(.tag)[address_index]);
    const operator_token = context.nodes.items(.main_token)[address_index];
    try std.testing.expectEqual(.ampersand, context.tokens.items(.tag)[operator_token]);
    const child_node = context.nodes.items(.data)[address_index].node;
    try std.testing.expectEqual(.field_access, context.nodes.items(.tag)[@backingInt(child_node)]);
}

fn pointerAllocationScenario(allocator: std.mem.Allocator) !void {
    var context: zast.AstContext = .{};
    defer context.deinit(allocator);
    _ = try context.addNode(allocator, .root, 0, undefined);
    const integer_type: zast.Expression = .{ .identifier = "u32" };
    const pointer_type: zast.Expression = .{
        .pointer_type = .{ .child_type = &integer_type, .is_const = true },
    };
    const optional_pointer: zast.Expression = .{ .optional_type = &pointer_type };
    _ = try optional_pointer.emit(allocator, &context);
    const counter_reference: zast.Expression = .{ .identifier = "counter" };
    const counter_address: zast.Expression = .{ .address_of = &counter_reference };
    _ = try counter_address.emit(allocator, &context);
}

test "pointer type and address-of emission clean up allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, pointerAllocationScenario, .{});
}

fn expectRenderedType(type_expression: zast.Expression, expected_source: [:0]const u8) !void {
    const allocator = std.testing.allocator;
    const declaration: zast.Declaration = .{ .value = type_expression };
    const rendered = try helpers.renderDescription(allocator, declaration);
    defer allocator.free(rendered);
    try helpers.expectFormattedSource(allocator, expected_source, rendered);
}

test "arrays support lengths, sentinels, nested types, and computed lengths" {
    const byte_type: zast.Expression = .{ .identifier = "u8" };
    const length: zast.Expression = .{ .integer_literal = "4" };
    const zero: zast.Expression = .{ .integer_literal = "0" };
    const single: zast.Expression = .{ .integer_literal = "1" };
    const computed_length: zast.Expression = .{ .shift_left = .{ .left = &single, .right = &length } };
    const terminated_array: zast.Expression = .{
        .array_type = .{ .length = &length, .child_type = &byte_type, .sentinel = &zero },
    };
    const examples = [_]struct {
        expression: zast.Expression,
        source: [:0]const u8,
    }{
        .{
            .expression = .{ .array_type = .{ .length = &length, .child_type = &byte_type } },
            .source = "pub const Generated = [4]u8;",
        },
        .{ .expression = terminated_array, .source = "pub const Generated = [4:0]u8;" },
        .{
            .expression = .{ .array_type = .{ .length = &zero, .child_type = &byte_type } },
            .source = "pub const Generated = [0]u8;",
        },
        .{
            .expression = .{ .array_type = .{ .length = &computed_length, .child_type = &terminated_array } },
            .source = "pub const Generated = [1 << 4][4:0]u8;",
        },
        .{
            .expression = .{ .pointer_type = .{ .child_type = &terminated_array, .is_const = true } },
            .source = "pub const Generated = *const [4:0]u8;",
        },
    };
    for (examples) |example| try expectRenderedType(example.expression, example.source);
}

test "pointer and slice forms support every const volatile allowzero combination" {
    // This matrix checks syntax and rendering. Zig rejects explicit allowzero
    // on C pointers during semantic analysis because they already allow zero.
    const allocator = std.testing.allocator;
    const byte_type: zast.Expression = .{ .identifier = "u8" };
    const sentinel: zast.Expression = .{ .integer_literal = "0" };
    const alignment: zast.Expression = .{ .integer_literal = "8" };
    const prefixes = [_][]const u8{ "*", "[*]", "[*:0]", "[*c]", "[]", "[:0]" };
    for (prefixes, 0..) |prefix, form_index| {
        for (0..8) |qualifier_flags| {
            for ([_]bool{ false, true }) |has_alignment| {
                const is_const = qualifier_flags & 1 != 0;
                const is_volatile = qualifier_flags & 2 != 0;
                const is_allowzero = qualifier_flags & 4 != 0;
                const type_expression: zast.Expression = if (form_index < 4) .{
                    .pointer_type = .{
                        .child_type = &byte_type,
                        .kind = switch (form_index) {
                            0 => .single,
                            1 => .{ .many = null },
                            2 => .{ .many = &sentinel },
                            3 => .c,
                            else => unreachable,
                        },
                        .is_const = is_const,
                        .is_volatile = is_volatile,
                        .is_allowzero = is_allowzero,
                        .alignment = if (has_alignment) &alignment else null,
                    },
                } else .{
                    .slice_type = .{
                        .child_type = &byte_type,
                        .sentinel = if (form_index == 5) &sentinel else null,
                        .is_const = is_const,
                        .is_volatile = is_volatile,
                        .is_allowzero = is_allowzero,
                        .alignment = if (has_alignment) &alignment else null,
                    },
                };
                const expected_source = try std.fmt.allocPrintSentinel(
                    allocator,
                    "pub const Generated = {s}{s}{s}{s}{s}u8;",
                    .{
                        prefix,
                        if (has_alignment) "align(8) " else "",
                        if (is_const) "const " else "",
                        if (is_volatile) "volatile " else "",
                        if (is_allowzero) "allowzero " else "",
                    },
                    0,
                );
                defer allocator.free(expected_source);
                try expectRenderedType(type_expression, expected_source);
            }
        }
    }
}

test "array nodes preserve length sentinel and nested child links" {
    const allocator = std.testing.allocator;
    var context: zast.AstContext = .{};
    defer context.deinit(allocator);
    _ = try context.addNode(allocator, .root, 0, undefined);
    const byte_type: zast.Expression = .{ .identifier = "u8" };
    const length: zast.Expression = .{ .integer_literal = "4" };
    const sentinel: zast.Expression = .{ .integer_literal = "0" };
    const inner_array: zast.Expression = .{
        .array_type = .{ .length = &length, .child_type = &byte_type },
    };
    const outer_array: zast.Expression = .{
        .array_type = .{ .length = &length, .sentinel = &sentinel, .child_type = &inner_array },
    };
    const outer_node = try outer_array.emit(allocator, &context);
    const outer_index = @backingInt(outer_node);
    try std.testing.expectEqual(.array_type_sentinel, context.nodes.items(.tag)[outer_index]);
    try std.testing.expectEqual(.l_bracket, context.tokens.items(.tag)[context.nodes.items(.main_token)[outer_index]]);
    const length_node, const extra_index = context.nodes.items(.data)[outer_index].node_and_extra;
    try std.testing.expectEqual(.number_literal, context.nodes.items(.tag)[@backingInt(length_node)]);
    const sentinel_index = context.extra_data.items[@backingInt(extra_index)];
    const inner_index = context.extra_data.items[@backingInt(extra_index) + 1];
    try std.testing.expectEqual(.number_literal, context.nodes.items(.tag)[sentinel_index]);
    try std.testing.expect(length_node != @as(std.zig.Ast.Node.Index, @fromBackingInt(sentinel_index)));
    const length_start = context.tokens.items(.start)[context.nodes.items(.main_token)[@backingInt(length_node)]];
    const sentinel_start = context.tokens.items(.start)[context.nodes.items(.main_token)[sentinel_index]];
    try std.testing.expectEqualStrings("4", context.source.items[length_start .. length_start + 1]);
    try std.testing.expectEqualStrings("0", context.source.items[sentinel_start .. sentinel_start + 1]);
    try std.testing.expectEqual(.array_type, context.nodes.items(.tag)[inner_index]);
    const inner_length, const child_type = context.nodes.items(.data)[inner_index].node_and_node;
    try std.testing.expectEqual(.number_literal, context.nodes.items(.tag)[@backingInt(inner_length)]);
    try std.testing.expectEqual(.identifier, context.nodes.items(.tag)[@backingInt(child_type)]);
}

test "pointer layouts preserve independent sentinel alignment and element links" {
    const allocator = std.testing.allocator;
    const byte_type: zast.Expression = .{ .identifier = "u8" };
    const sentinel: zast.Expression = .{ .integer_literal = "0" };
    const alignment: zast.Expression = .{ .integer_literal = "8" };
    for ([_]bool{ false, true }) |has_sentinel| {
        for ([_]bool{ false, true }) |has_alignment| {
            var context: zast.AstContext = .{};
            defer context.deinit(allocator);
            _ = try context.addNode(allocator, .root, 0, undefined);
            const pointer_type: zast.Expression = .{
                .pointer_type = .{
                    .kind = .{ .many = if (has_sentinel) &sentinel else null },
                    .child_type = &byte_type,
                    .alignment = if (has_alignment) &alignment else null,
                },
            };
            const pointer_node = try pointer_type.emit(allocator, &context);
            const pointer_index = @backingInt(pointer_node);
            const expected_tag: std.zig.Ast.Node.Tag = if (has_sentinel and has_alignment)
                .ptr_type
            else if (has_sentinel)
                .ptr_type_sentinel
            else
                .ptr_type_aligned;
            try std.testing.expectEqual(expected_tag, context.nodes.items(.tag)[pointer_index]);
            try std.testing.expectEqual(.l_bracket, context.tokens.items(.tag)[context.nodes.items(.main_token)[pointer_index]]);
            if (has_sentinel and has_alignment) {
                const extra_index, const child_node = context.nodes.items(.data)[pointer_index].extra_and_node;
                const sentinel_node: std.zig.Ast.Node.OptionalIndex = @fromBackingInt(context.extra_data.items[@backingInt(extra_index)]);
                const alignment_node: std.zig.Ast.Node.OptionalIndex = @fromBackingInt(context.extra_data.items[@backingInt(extra_index) + 1]);
                const address_space_node: std.zig.Ast.Node.OptionalIndex = @fromBackingInt(context.extra_data.items[@backingInt(extra_index) + 2]);
                try std.testing.expect(sentinel_node != alignment_node);
                try std.testing.expectEqual(.number_literal, context.nodes.items(.tag)[@backingInt(sentinel_node.unwrap().?)]);
                try std.testing.expectEqual(.number_literal, context.nodes.items(.tag)[@backingInt(alignment_node.unwrap().?)]);
                const sentinel_start = context.tokens.items(.start)[context.nodes.items(.main_token)[@backingInt(sentinel_node.unwrap().?)]];
                const alignment_start = context.tokens.items(.start)[context.nodes.items(.main_token)[@backingInt(alignment_node.unwrap().?)]];
                try std.testing.expectEqualStrings("0", context.source.items[sentinel_start .. sentinel_start + 1]);
                try std.testing.expectEqualStrings("8", context.source.items[alignment_start .. alignment_start + 1]);
                try std.testing.expectEqual(.none, address_space_node);
                try std.testing.expectEqual(.identifier, context.nodes.items(.tag)[@backingInt(child_node)]);
            } else {
                const optional_node, const child_node = context.nodes.items(.data)[pointer_index].opt_node_and_node;
                try std.testing.expectEqual(has_sentinel or has_alignment, optional_node != .none);
                if (optional_node.unwrap()) |present_node| {
                    try std.testing.expectEqual(.number_literal, context.nodes.items(.tag)[@backingInt(present_node)]);
                }
                try std.testing.expectEqual(.identifier, context.nodes.items(.tag)[@backingInt(child_node)]);
                try std.testing.expectEqual(@as(usize, 0), context.extra_data.items.len);
            }
        }
    }
}

test "error sets support empty sets and complete escaped identifier spellings" {
    try expectRenderedType(.{ .error_set_type = &.{} }, "pub const Generated = error{};");
    try expectRenderedType(
        .{ .error_set_type = &.{ "InvalidData", "Truncated", "@\"error\"", "@\"not-found\"" } },
        "pub const Generated = error{ InvalidData, Truncated, @\"error\", @\"not-found\" };",
    );
}

test "error unions preserve prefix payload and left operand grouping" {
    const byte_type: zast.Expression = .{ .identifier = "u8" };
    const errors: zast.Expression = .{ .identifier = "ReadError" };
    const inline_errors: zast.Expression = .{ .error_set_type = &.{ "InvalidData", "Truncated" } };
    const empty_errors: zast.Expression = .{ .error_set_type = &.{} };
    const byte_slice: zast.Expression = .{ .slice_type = .{ .child_type = &byte_type, .is_const = true } };
    const optional_slice: zast.Expression = .{ .optional_type = &byte_slice };
    const result_type: zast.Expression = .{ .error_union_type = .{ .error_set = &errors, .payload_type = &byte_slice } };
    const optional_errors: zast.Expression = .{ .optional_type = &errors };
    const shift_amount: zast.Expression = .{ .integer_literal = "4" };
    const shifted_payload: zast.Expression = .{ .shift_left = .{ .left = &byte_type, .right = &shift_amount } };
    const examples = [_]struct {
        expression: zast.Expression,
        source: [:0]const u8,
    }{
        .{ .expression = result_type, .source = "pub const Generated = ReadError![]const u8;" },
        .{
            .expression = .{ .error_union_type = .{ .error_set = &inline_errors, .payload_type = &optional_slice } },
            .source = "pub const Generated = error{ InvalidData, Truncated }!?[]const u8;",
        },
        .{
            .expression = .{ .error_union_type = .{ .error_set = &empty_errors, .payload_type = &byte_type } },
            .source = "pub const Generated = error{}!u8;",
        },
        .{
            .expression = .{ .optional_type = &result_type },
            .source = "pub const Generated = ?ReadError![]const u8;",
        },
        .{
            .expression = .{ .error_union_type = .{ .error_set = &errors, .payload_type = &result_type } },
            .source = "pub const Generated = ReadError!ReadError![]const u8;",
        },
        .{
            .expression = .{ .error_union_type = .{ .error_set = &result_type, .payload_type = &byte_type } },
            .source = "pub const Generated = (ReadError![]const u8)!u8;",
        },
        .{
            .expression = .{ .error_union_type = .{ .error_set = &optional_errors, .payload_type = &shifted_payload } },
            .source = "pub const Generated = (?ReadError)!(u8 << 4);",
        },
        .{
            .expression = .{ .field_access = .{ .base = &result_type, .name = "Member" } },
            .source = "pub const Generated = (ReadError![]const u8).Member;",
        },
    };
    // These cases check syntax and precedence, including deliberately unresolved
    // or semantically invalid types; Zig's compiler remains the semantic checker.
    for (examples) |example| try expectRenderedType(example.expression, example.source);
}

test "error set braces and error union operands are linked without member nodes" {
    const allocator = std.testing.allocator;
    var context: zast.AstContext = .{};
    defer context.deinit(allocator);
    _ = try context.addNode(allocator, .root, 0, undefined);
    const errors: zast.Expression = .{ .error_set_type = &.{ "InvalidData", "Truncated" } };
    const byte_type: zast.Expression = .{ .identifier = "u8" };
    const result_type: zast.Expression = .{ .error_union_type = .{ .error_set = &errors, .payload_type = &byte_type } };
    const result_node = try result_type.emit(allocator, &context);
    const result_index = @backingInt(result_node);
    try std.testing.expectEqual(.error_union, context.nodes.items(.tag)[result_index]);
    try std.testing.expectEqual(.bang, context.tokens.items(.tag)[context.nodes.items(.main_token)[result_index]]);
    const errors_node, const payload_node = context.nodes.items(.data)[result_index].node_and_node;
    try std.testing.expectEqual(.identifier, context.nodes.items(.tag)[@backingInt(payload_node)]);
    const errors_index = @backingInt(errors_node);
    try std.testing.expectEqual(.error_set_decl, context.nodes.items(.tag)[errors_index]);
    try std.testing.expectEqual(.keyword_error, context.tokens.items(.tag)[context.nodes.items(.main_token)[errors_index]]);
    const opening_token, const closing_token = context.nodes.items(.data)[errors_index].token_and_token;
    try std.testing.expectEqual(.l_brace, context.tokens.items(.tag)[opening_token]);
    try std.testing.expectEqual(.r_brace, context.tokens.items(.tag)[closing_token]);
    try std.testing.expectEqual(.identifier, context.tokens.items(.tag)[opening_token + 1]);
    try std.testing.expectEqual(.comma, context.tokens.items(.tag)[opening_token + 2]);
    try std.testing.expectEqual(.identifier, context.tokens.items(.tag)[opening_token + 3]);
    try std.testing.expectEqual(@as(usize, 4), context.nodes.len);
    try std.testing.expectEqual(@as(usize, 0), context.extra_data.items.len);
}

fn compoundTypeAllocationScenario(allocator: std.mem.Allocator) !void {
    const byte_type: zast.Expression = .{ .identifier = "u8" };
    const zero: zast.Expression = .{ .integer_literal = "0" };
    const length: zast.Expression = .{ .integer_literal = "4" };
    const byte_array: zast.Expression = .{
        .array_type = .{ .length = &length, .child_type = &byte_type, .sentinel = &zero },
    };
    const pointer_type: zast.Expression = .{
        .pointer_type = .{
            .kind = .{ .many = &zero },
            .child_type = &byte_array,
            .alignment = &length,
            .is_const = true,
            .is_volatile = true,
            .is_allowzero = true,
        },
    };
    const pointer_slice: zast.Expression = .{
        .slice_type = .{ .child_type = &pointer_type, .sentinel = &zero, .alignment = &length },
    };
    const errors: zast.Expression = .{ .error_set_type = &.{ "InvalidData", "@\"error\"" } };
    const declaration: zast.Declaration = .{
        .value = .{ .error_union_type = .{ .error_set = &errors, .payload_type = &pointer_slice } },
    };
    const rendered = try helpers.renderDescription(allocator, declaration);
    defer allocator.free(rendered);
}

test "compound type emission and rendering clean up every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, compoundTypeAllocationScenario, .{});
}
