//! Call expressions compose through existing declarations, types, and fields.
//!
//! ## Coverage
//!
//! - Ordinary and builtin calls used in descriptors and type expressions.
//! - Zero through four arguments across inline and extra-data AST layouts.
//! - Main tokens, callee links, argument order, and independently parsed tokens.
//! - Callee precedence and composition with prefix and suffix expressions.
//! - Nested argument ranges under buffer relocation and allocation failures.
//!
//! ## Running
//!
//! Run `zig build test` from the `zast` directory via `test_all.zig`.
//! Source comparisons check parsing and rendering; arbitrary builtin argument
//! counts and unresolved callees exercise syntax without checking arity or types.
//! Compile generated examples separately to check their semantic validity;
//! these tests do not compile the generated snippets.

const std = @import("std");
const Ast = std.zig.Ast;
const zast = @import("zast");
const helpers = @import("helpers.zig");

test "ordinary and builtin calls render standard library calls and type expressions" {
    const allocator = std.testing.allocator;
    const standard_library: zast.Expression = .{ .identifier = "std" };
    const rotate_function: zast.Expression = .{ .field_access = .{
        .base = &.{ .field_access = .{ .base = &standard_library, .name = "math" } },
        .name = "rotl",
    } };
    const array_function: zast.Expression = .{ .field_access = .{ .base = &standard_library, .name = "EnumArray" } };
    const self_type: zast.Expression = .{ .builtin_call = .{ .name = "@This" } };
    const field_type: zast.Expression = .{ .builtin_call = .{
        .name = "@FieldType",
        .arguments = &.{ self_type, .{ .string_literal = "\"value\"" } },
    } };
    const examples = [_]helpers.ExpressionCase{
        .{
            .expression = .{ .call = .{
                .callee = &rotate_function,
                .arguments = &.{ .{ .identifier = "u8" }, .{ .integer_literal = "21" }, .{ .integer_literal = "1" } },
            } },
            .source = "pub const Generated = std.math.rotl(u8, 21, 1);",
        },
        .{
            .expression = .{ .call = .{
                .callee = &array_function,
                .arguments = &.{ .{ .identifier = "Tag" }, .{ .identifier = "u32" } },
            } },
            .source = "pub const Generated = std.EnumArray(Tag, u32);",
        },
        .{
            .expression = .{ .builtin_call = .{
                .name = "@import",
                .arguments = &.{.{ .string_literal = "\"std\"" }},
            } },
            .source = "pub const Generated = @import(\"std\");",
        },
        .{ .expression = self_type, .source = "pub const Generated = @This();" },
        .{ .expression = field_type, .source = "pub const Generated = @FieldType(@This(), \"value\");" },
        .{
            .expression = .{ .optional_type = &field_type },
            .source = "pub const Generated = ?@FieldType(@This(), \"value\");",
        },
    };
    for (examples) |example| try example.expect(allocator);
}

test "call layouts preserve tokens and ordered arguments across inline boundaries" {
    const allocator = std.testing.allocator;
    const callee: zast.Expression = .{ .identifier = "convert" };
    const arguments = [_]zast.Expression{
        .{ .identifier = "first" }, .{ .identifier = "second" },
        .{ .identifier = "third" }, .{ .identifier = "fourth" },
    };
    // Arbitrary argument counts test AST syntax, not builtin arity/type checking.
    for ([_]bool{ false, true }) |is_builtin| {
        for (0..arguments.len + 1) |argument_count| {
            var context: zast.AstContext = .{};
            defer context.deinit(allocator);
            _ = try context.addNode(allocator, .root, 0, undefined);
            const invocation: zast.Expression = if (is_builtin)
                .{ .builtin_call = .{ .name = "@TypeOf", .arguments = arguments[0..argument_count] } }
            else
                .{ .call = .{ .callee = &callee, .arguments = arguments[0..argument_count] } };
            try (zast.Declaration{ .value = invocation }).emit(allocator, &context, "Generated", .public);
            const uses_extra = argument_count > @as(usize, if (is_builtin) 2 else 1);
            try std.testing.expectEqual(
                if (uses_extra) argument_count + @as(usize, if (is_builtin) 0 else 2) else 0,
                context.extra_data.items.len,
            );
            var tree = try context.finish(allocator);
            const source = tree.source;
            defer allocator.free(source);
            defer tree.deinit(allocator);
            const call_node = tree.fullVarDecl(tree.rootDecls()[0]).?.ast.init_node.unwrap().?;
            const expected_tag: Ast.Node.Tag = if (is_builtin)
                (if (uses_extra) .builtin_call else .builtin_call_two)
            else
                (if (uses_extra) .call else .call_one);
            try std.testing.expectEqual(expected_tag, tree.nodeTag(call_node));
            const main_token = tree.nodeMainToken(call_node);
            try std.testing.expectEqual(@as(std.zig.Token.Tag, if (is_builtin) .builtin else .l_paren), tree.tokenTag(main_token));
            try std.testing.expectEqualStrings(if (is_builtin) "@TypeOf" else "(", tree.tokenSlice(main_token));
            var builtin_buffer: [2]Ast.Node.Index = undefined;
            var call_buffer: [1]Ast.Node.Index = undefined;
            const argument_nodes = if (is_builtin) tree.builtinCallParams(&builtin_buffer, call_node).? else arguments: {
                const call = tree.fullCall(&call_buffer, call_node).?;
                try std.testing.expectEqual(.identifier, tree.nodeTag(call.ast.fn_expr));
                try std.testing.expectEqualStrings("convert", tree.tokenSlice(tree.nodeMainToken(call.ast.fn_expr)));
                break :arguments call.ast.params;
            };
            try std.testing.expectEqual(argument_count, argument_nodes.len);
            for (argument_nodes, arguments[0..argument_count]) |argument_node, argument| {
                try std.testing.expectEqual(.identifier, tree.nodeTag(argument_node));
                try std.testing.expectEqualStrings(argument.identifier, tree.tokenSlice(tree.nodeMainToken(argument_node)));
            }
            // Re-tokenize raw source independently of the emitter's token tags.
            var parsed = try Ast.parse(allocator, source, .{});
            defer parsed.deinit(allocator);
            try std.testing.expectEqual(@as(usize, 0), parsed.errors.len);
            try std.testing.expectEqualSlices(std.zig.Token.Tag, parsed.tokens.items(.tag), tree.tokens.items(.tag));
            const rendered = try tree.renderAlloc(allocator);
            defer allocator.free(rendered);
            try helpers.expectFormattedSource(allocator, source, rendered);
        }
    }
}

test "calls preserve callee precedence and compose with suffix and prefix expressions" {
    const allocator = std.testing.allocator;
    const read_function: zast.Expression = .{ .identifier = "read" };
    const byte_arguments = [_]zast.Expression{.{ .identifier = "bytes" }};
    const empty_call: zast.Expression = .{ .call = .{ .callee = &read_function } };
    const read_call: zast.Expression = .{ .call = .{ .callee = &read_function, .arguments = &byte_arguments } };
    const shift_amount: zast.Expression = .{ .integer_literal = "1" };
    const shifted_callee: zast.Expression = .{ .shift_left = .{ .left = &read_function, .right = &shift_amount } };
    const method: zast.Expression = .{ .field_access = .{ .base = &empty_call, .name = "decode" } };
    const imported_namespace: zast.Expression = .{ .builtin_call = .{
        .name = "@import",
        .arguments = &.{.{ .string_literal = "\"std\"" }},
    } };
    const examples = [_]helpers.ExpressionCase{
        .{ .expression = empty_call, .source = "pub const Generated = read();" },
        .{ .expression = read_call, .source = "pub const Generated = read(bytes);" },
        .{
            .expression = .{ .call = .{ .callee = &empty_call, .arguments = &byte_arguments } },
            .source = "pub const Generated = read()(bytes);",
        },
        .{
            .expression = .{ .call = .{ .callee = &method, .arguments = &byte_arguments } },
            .source = "pub const Generated = read().decode(bytes);",
        },
        .{
            .expression = .{ .call = .{ .callee = &shifted_callee, .arguments = &byte_arguments } },
            .source = "pub const Generated = (read << 1)(bytes);",
        },
        .{ .expression = .{ .negate = &read_call }, .source = "pub const Generated = -read(bytes);" },
        .{
            .expression = .{ .field_access = .{ .base = &read_call, .name = "value" } },
            .source = "pub const Generated = read(bytes).value;",
        },
        .{
            .expression = .{ .field_access = .{ .base = &imported_namespace, .name = "math" } },
            .source = "pub const Generated = @import(\"std\").math;",
        },
    };
    // Some callees are deliberately unresolved: these assertions check grouping.
    for (examples) |example| try example.expect(allocator);
}

fn nestedCallAllocationScenario(backing_allocator: std.mem.Allocator) !void {
    // Force growing buffers to relocate while parent argument ranges are live.
    var allocator_state = std.testing.FailingAllocator.init(backing_allocator, .{ .resize_fail_index = 0 });
    const allocator = allocator_state.allocator();
    const callee: zast.Expression = .{ .identifier = "build" };
    const nested_call: zast.Expression = .{ .call = .{
        .callee = &callee,
        .arguments = &.{ .{ .integer_literal = "1" }, .{ .integer_literal = "2" }, .{ .integer_literal = "3" } },
    } };
    const nested_builtin: zast.Expression = .{ .builtin_call = .{
        .name = "@TypeOf",
        .arguments = &.{ nested_call, nested_call, nested_call },
    } };
    const expression: zast.Expression = .{ .call = .{
        .callee = &nested_call,
        .arguments = &.{ nested_builtin, nested_call, .{ .builtin_call = .{ .name = "@This" } } },
    } };
    const rendered = try helpers.renderDescription(allocator, zast.Declaration{ .value = expression });
    defer allocator.free(rendered);
    try helpers.expectFormattedSource(allocator,
        \\pub const Generated = build(1, 2, 3)(
        \\    @TypeOf(build(1, 2, 3), build(1, 2, 3), build(1, 2, 3)), build(1, 2, 3), @This()
        \\);
    , rendered);
}

test "nested calls preserve contiguous argument ranges and clean up allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, nestedCallAllocationScenario, .{});
}
