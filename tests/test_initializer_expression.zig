//! Value initializers and enum literals, including recursive AST storage.
//!
//! ## Coverage
//!
//! - Enum-literal token spelling and boundaries, including escaped identifiers.
//! - Named and positional initializers, empty values, and explicit types.
//! - Inline storage boundaries, trailing commas, and layouts compared to parsing.
//! - Initializer grouping with type expressions, operators, calls, and members.
//! - Nested child ranges under buffer relocation and allocation failures.
//!
//! ## Running
//!
//! Run `zig build test` from the `zast` directory via `test_all.zig`.
//! Assertions inspect AST layout and compare rendered source with parsed
//! expectations. Unresolved types and deliberately ill-typed operands isolate
//! grammar and grouping.
//! Compile generated examples separately to check their semantic validity;
//! parser and renderer checks here do not type-check generated source.

const std = @import("std");
const Ast = std.zig.Ast;
const zast = @import("zast");
const helpers = @import("helpers.zig");

test "enum literals use a period followed by an identifier main token" {
    const allocator = std.testing.allocator;
    for ([_][]const u8{ "unknown", "string", "@\"error\"" }) |name| {
        var context: zast.AstContext = .{};
        defer context.deinit(allocator);
        _ = try context.addNode(allocator, .root, 0, undefined);
        try (zast.Declaration{ .value = .{ .enum_literal = name } }).emit(allocator, &context, "Generated", .public);
        var tree = try context.finish(allocator);
        const source = tree.source;
        defer allocator.free(source);
        defer tree.deinit(allocator);
        const literal_node = tree.fullVarDecl(tree.rootDecls()[0]).?.ast.init_node.unwrap().?;
        const main_token = tree.nodeMainToken(literal_node);
        try std.testing.expectEqual(.enum_literal, tree.nodeTag(literal_node));
        try std.testing.expectEqual(.identifier, tree.tokenTag(main_token));
        try std.testing.expectEqual(.period, tree.tokenTag(main_token - 1));
        try std.testing.expectEqual(main_token - 1, tree.firstToken(literal_node));
        try std.testing.expectEqual(main_token, tree.lastToken(literal_node));
        try std.testing.expectEqualStrings(name, tree.tokenSlice(main_token));
        const expected = try std.fmt.allocPrintSentinel(allocator, "pub const Generated = .{s};", .{name}, 0);
        defer allocator.free(expected);
        const rendered = try tree.renderAlloc(allocator);
        defer allocator.free(rendered);
        try helpers.expectFormattedSource(allocator, expected, rendered);
    }
}

test "initializers render descriptors, empty values, positional elements and explicit types" {
    const allocator = std.testing.allocator;
    const options_type: zast.Expression = .{ .identifier = "Options" };
    const byte_type: zast.Expression = .{ .identifier = "u8" };
    const length: zast.Expression = .{ .integer_literal = "2" };
    const array_type: zast.Expression = .{ .array_type = .{ .length = &length, .child_type = &byte_type } };
    const schema_function: zast.Expression = .{ .identifier = "Schema" };
    const fields = [_]zast.Expression.InitializerField{
        .{ .name = "required", .value = .{ .identifier = "true" } },
        .{ .name = "kind", .value = .{ .enum_literal = "string" } },
        .{ .name = "@\"error\"", .value = .{ .enum_literal = "unknown" } },
    };
    const elements = [_]zast.Expression{ .{ .integer_literal = "1" }, .{ .integer_literal = "2" } };
    const examples = [_]helpers.ExpressionCase{
        .{ .expression = .{ .struct_init = .{} }, .source = "pub const Generated = .{};" },
        .{ .expression = .{ .array_init = .{} }, .source = "pub const Generated = .{};" },
        .{
            .expression = .{ .struct_init = .{ .fields = fields[0..1] } },
            .source = "pub const Generated = .{ .required = true };",
        },
        .{
            .expression = .{ .struct_init = .{ .fields = &fields, .trailing_comma = true } },
            .source = "pub const Generated = .{ .required = true, .kind = .string, .@\"error\" = .unknown, };",
        },
        .{
            .expression = .{ .struct_init = .{ .type_expression = &options_type, .fields = fields[0..1] } },
            .source = "pub const Generated = Options{ .required = true };",
        },
        .{
            .expression = .{ .array_init = .{ .elements = &elements } },
            .source = "pub const Generated = .{ 1, 2 };",
        },
        .{
            .expression = .{ .array_init = .{ .type_expression = &array_type, .elements = &elements } },
            .source = "pub const Generated = [2]u8{ 1, 2 };",
        },
        .{
            .expression = .{ .call = .{ .callee = &schema_function, .arguments = &.{
                .{ .builtin_call = .{ .name = "@This" } },
                .{ .struct_init = .{ .fields = &fields } },
            } } },
            .source = "pub const Generated = Schema(@This(), .{ .required = true, .kind = .string, .@\"error\" = .unknown });",
        },
    };
    for (examples) |example| try example.expect(allocator);
}

test "initializer layouts match parsed ASTs at every inline boundary and trailing comma form" {
    const allocator = std.testing.allocator;
    const type_expression: zast.Expression = .{ .identifier = "Values" };
    const elements = [_]zast.Expression{
        .{ .integer_literal = "10" }, .{ .integer_literal = "20" },
        .{ .integer_literal = "30" }, .{ .integer_literal = "40" },
    };
    const fields = [_]zast.Expression.InitializerField{
        .{ .name = "first", .value = elements[0] }, .{ .name = "second", .value = elements[1] },
        .{ .name = "third", .value = elements[2] }, .{ .name = "fourth", .value = elements[3] },
    };
    // Values is deliberately unresolved: this matrix checks all parser layouts.
    for ([_]bool{ false, true }) |named| {
        for ([_]bool{ false, true }) |explicit_type| {
            for ([_]bool{ false, true }) |trailing_comma| {
                for (0..elements.len + 1) |entry_count| {
                    var context: zast.AstContext = .{};
                    defer context.deinit(allocator);
                    _ = try context.addNode(allocator, .root, 0, undefined);
                    const initializer: zast.Expression = if (named)
                        .{ .struct_init = .{
                            .type_expression = if (explicit_type) &type_expression else null,
                            .fields = fields[0..entry_count],
                            .trailing_comma = trailing_comma,
                        } }
                    else
                        .{ .array_init = .{
                            .type_expression = if (explicit_type) &type_expression else null,
                            .elements = elements[0..entry_count],
                            .trailing_comma = trailing_comma,
                        } };
                    try (zast.Declaration{ .value = initializer }).emit(allocator, &context, "Generated", .public);
                    const uses_extra = entry_count > @as(usize, if (explicit_type) 1 else 2);
                    try std.testing.expectEqual(
                        if (uses_extra) entry_count + @as(usize, if (explicit_type) 2 else 0) else 0,
                        context.extra_data.items.len,
                    );
                    var tree = try context.finish(allocator);
                    const source = tree.source;
                    defer allocator.free(source);
                    defer tree.deinit(allocator);
                    var parsed = try Ast.parse(allocator, source, .{});
                    defer parsed.deinit(allocator);
                    try std.testing.expectEqual(@as(usize, 0), parsed.errors.len);
                    try std.testing.expectEqualSlices(std.zig.Token.Tag, parsed.tokens.items(.tag), tree.tokens.items(.tag));
                    const initializer_node = tree.fullVarDecl(tree.rootDecls()[0]).?.ast.init_node.unwrap().?;
                    const parsed_node = parsed.fullVarDecl(parsed.rootDecls()[0]).?.ast.init_node.unwrap().?;
                    try std.testing.expectEqual(parsed.nodeTag(parsed_node), tree.nodeTag(initializer_node));
                    try std.testing.expectEqual(parsed.firstToken(parsed_node), tree.firstToken(initializer_node));
                    try std.testing.expectEqual(parsed.lastToken(parsed_node), tree.lastToken(initializer_node));
                    const opening_token = tree.nodeMainToken(initializer_node);
                    try std.testing.expectEqual(.l_brace, tree.tokenTag(opening_token));
                    try std.testing.expectEqual(trailing_comma and entry_count != 0, tree.tokenTag(tree.lastToken(initializer_node) - 1) == .comma);
                    var entry_buffer: [2]Ast.Node.Index = undefined;
                    const child_nodes, const type_node = if (named or entry_count == 0) children: {
                        const full = tree.fullStructInit(&entry_buffer, initializer_node).?.ast;
                        break :children .{ full.fields, full.type_expr };
                    } else children: {
                        const full = tree.fullArrayInit(&entry_buffer, initializer_node).?.ast;
                        break :children .{ full.elements, full.type_expr };
                    };
                    try std.testing.expectEqual(explicit_type, type_node != .none);
                    if (type_node.unwrap()) |child_type| {
                        try std.testing.expectEqualStrings("Values", tree.tokenSlice(tree.nodeMainToken(child_type)));
                    } else {
                        try std.testing.expectEqual(.period, tree.tokenTag(opening_token - 1));
                    }
                    try std.testing.expectEqual(entry_count, child_nodes.len);
                    for (child_nodes, 0..) |child_node, child_index| {
                        try std.testing.expectEqual(.number_literal, tree.nodeTag(child_node));
                        try std.testing.expectEqualStrings(elements[child_index].integer_literal, tree.tokenSlice(tree.nodeMainToken(child_node)));
                        if (named) {
                            const first_token = tree.firstToken(child_node);
                            try std.testing.expectEqual(.period, tree.tokenTag(first_token - 3));
                            try std.testing.expectEqualStrings(fields[child_index].name, tree.tokenSlice(first_token - 2));
                            try std.testing.expectEqual(.equal, tree.tokenTag(first_token - 1));
                        }
                    }
                    const rendered = try tree.renderAlloc(allocator);
                    defer allocator.free(rendered);
                    try helpers.expectFormattedSource(allocator, source, rendered);
                }
            }
        }
    }
}

test "initializers compose with type expressions, operators, calls and member access" {
    const allocator = std.testing.allocator;
    const options_type: zast.Expression = .{ .identifier = "Options" };
    const initializer: zast.Expression = .{ .struct_init = .{ .type_expression = &options_type } };
    const inferred: zast.Expression = .{ .struct_init = .{ .fields = &.{
        .{ .name = "required", .value = .{ .identifier = "true" } },
    } } };
    const type_factory: zast.Expression = .{ .call = .{ .callee = &options_type } };
    const shift_amount: zast.Expression = .{ .integer_literal = "1" };
    const shifted_type: zast.Expression = .{ .shift_left = .{ .left = &options_type, .right = &shift_amount } };
    const examples = [_]helpers.ExpressionCase{
        .{
            .expression = .{ .field_access = .{ .base = &initializer, .name = "required" } },
            .source = "pub const Generated = (Options{}).required;",
        },
        .{
            .expression = .{ .field_access = .{ .base = &inferred, .name = "required" } },
            .source = "pub const Generated = .{ .required = true }.required;",
        },
        .{ .expression = .{ .address_of = &initializer }, .source = "pub const Generated = &(Options{});" },
        .{ .expression = .{ .optional_type = &initializer }, .source = "pub const Generated = ?(Options{});" },
        .{ .expression = .{ .call = .{ .callee = &initializer } }, .source = "pub const Generated = (Options{})();" },
        .{
            .expression = .{ .struct_init = .{ .type_expression = &type_factory } },
            .source = "pub const Generated = Options(){};",
        },
        .{
            .expression = .{ .struct_init = .{ .type_expression = &shifted_type } },
            .source = "pub const Generated = (Options << 1){};",
        },
    };
    // Some operands are intentionally ill-typed; this checks grammar and grouping.
    for (examples) |example| try example.expect(allocator);
}

fn nestedInitializerAllocationScenario(backing_allocator: std.mem.Allocator) !void {
    // Force growing buffers to relocate while parent entry ranges are live.
    var allocator_state = std.testing.FailingAllocator.init(backing_allocator, .{ .resize_fail_index = 0 });
    const allocator = allocator_state.allocator();
    const type_expression: zast.Expression = .{ .identifier = "Values" };
    const elements = [_]zast.Expression{
        .{ .enum_literal = "unknown" }, .{ .enum_literal = "string" }, .{ .struct_init = .{} },
    };
    const positional: zast.Expression = .{ .array_init = .{
        .type_expression = &type_expression,
        .elements = &elements,
    } };
    const fields = [_]zast.Expression.InitializerField{
        .{ .name = "first", .value = positional },
        .{ .name = "second", .value = .{ .array_init = .{ .elements = &elements } } },
        .{ .name = "third", .value = .{ .call = .{ .callee = &type_expression, .arguments = &elements } } },
    };
    const nested: zast.Expression = .{ .struct_init = .{
        .type_expression = &type_expression,
        .fields = &fields,
        .trailing_comma = true,
    } };
    const outer: zast.Expression = .{ .struct_init = .{ .fields = &.{
        .{ .name = "nested", .value = nested },
        .{ .name = "positional", .value = positional },
        .{ .name = "empty", .value = .{ .struct_init = .{} } },
    }, .trailing_comma = true } };
    const rendered = try helpers.renderDescription(allocator, zast.Declaration{ .value = outer });
    defer allocator.free(rendered);
    try helpers.expectFormattedSource(allocator,
        \\pub const Generated = .{
        \\    .nested = Values{
        \\        .first = Values{ .unknown, .string, .{} },
        \\        .second = .{ .unknown, .string, .{} },
        \\        .third = Values(.unknown, .string, .{}),
        \\    },
        \\    .positional = Values{ .unknown, .string, .{} },
        \\    .empty = .{},
        \\};
    , rendered);
}

test "nested initializers preserve contiguous child ranges and clean up allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, nestedInitializerAllocationScenario, .{});
}
