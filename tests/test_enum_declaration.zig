//! Enum declarations.
//!
//! ## Coverage
//!
//! - Borrowed list and array fields, pointer constness, and deferred assignment.
//! - Empty and inferred enums, explicit backing types, and computed values.
//! - Missing backing types rejected before any AST storage is changed.
//! - Rendered output matched with parsed expectations and reparsed token source.
//!
//! These assertions check builder behavior, syntax, and formatting; they do
//! not compile or type-check the generated enum declarations.
//!
//! Run the component tests with the full suite from `zast/`:
//!
//! ```sh
//! zig build test
//! ```

const std = @import("std");
const zast = @import("zast");
const helpers = @import("helpers.zig");

/// Compare formatted output with parsed expectations, then reparse emitted tokens.
/// Require the reparsed source to render identically to the manually built AST.
fn expectRenderedEnum(
    declaration: *const zast.EnumDeclaration,
    name: []const u8,
    expected_source: []const u8,
) !void {
    const allocator = std.testing.allocator;
    var context: zast.AstContext = .{};
    defer context.deinit(allocator);
    _ = try context.addNode(allocator, .root, 0, undefined);
    try declaration.emit(allocator, &context, name, .public);

    var generated_tree = try context.finish(allocator);
    const generated_source = generated_tree.source;
    defer allocator.free(generated_source);
    defer generated_tree.deinit(allocator);
    const generated_rendered = try generated_tree.renderAlloc(allocator);
    defer allocator.free(generated_rendered);

    const expected_terminated = try allocator.dupeSentinel(u8, expected_source, 0);
    defer allocator.free(expected_terminated);
    try helpers.expectFormattedSource(allocator, expected_terminated, generated_rendered);

    // Reparse the emitted token source to verify that it agrees with the hand-built tree.
    var reparsed_tree = try std.zig.Ast.parse(allocator, generated_source, .{ .mode = .zig });
    defer reparsed_tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), reparsed_tree.errors.len);
    const reparsed_rendered = try reparsed_tree.renderAlloc(allocator);
    defer allocator.free(reparsed_rendered);
    try std.testing.expectEqualStrings(generated_rendered, reparsed_rendered);
}

test "ArrayList fields create an inferred enum through a const pointer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const builder_allocator = arena.allocator();
    var enum_fields: std.ArrayList(zast.Field) = .empty;
    try enum_fields.append(builder_allocator, .{ .name = "unknown" });
    try enum_fields.append(builder_allocator, .{ .name = "ok" });

    const enum_decl = try zast.EnumDeclaration.init(builder_allocator, null, false, enum_fields.items);
    try std.testing.expect(@TypeOf(enum_decl) == *const zast.EnumDeclaration);
    try std.testing.expect(enum_decl.fields.ptr == enum_fields.items.ptr);
    try expectRenderedEnum(enum_decl, "Status", "pub const Status = enum { unknown, ok, };");
}

test "fixed-array fields create an inferred enum through a const pointer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const enum_fields = [_]zast.Field{
        .{ .name = "unknown" },
        .{ .name = "ok" },
    };

    const enum_decl = try zast.EnumDeclaration.init(arena.allocator(), null, false, &enum_fields);
    try std.testing.expect(@TypeOf(enum_decl) == *const zast.EnumDeclaration);
    try std.testing.expect(enum_decl.fields.ptr == enum_fields[0..].ptr);
    try expectRenderedEnum(enum_decl, "enumName0", "pub const enumName0 = enum { unknown, ok, };");
}

test "fields assigned after init support negative values and shifts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const literal_one: zast.Expression = .{ .integer_literal = "1" };
    const shift_amount: zast.Expression = .{ .integer_literal = "4" };
    const shifted_value: zast.Expression = .{
        .shift_left = .{ .left = &literal_one, .right = &shift_amount },
    };

    const enum_decl = try zast.EnumDeclaration.init(arena.allocator(), "i16", false, null);
    try std.testing.expect(@TypeOf(enum_decl) == *zast.EnumDeclaration);
    enum_decl.fields = &.{
        .{ .name = "negative", .value = .{ .negate = &literal_one } },
        .{ .name = "flag", .value = shifted_value },
        .{ .name = "negative_flag", .value = .{ .negate = &shifted_value } },
    };
    try expectRenderedEnum(enum_decl, "ComputedStatus",
        \\pub const ComputedStatus = enum(i16) {
        \\    negative = -1,
        \\    flag = 1 << 4,
        \\    negative_flag = -(1 << 4),
        \\};
    );
}

test "null initial fields can be used as an empty enum through a const pointer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const enum_decl: *const zast.EnumDeclaration = try zast.EnumDeclaration.init(arena.allocator(), null, false, null);

    try expectRenderedEnum(enum_decl, "enumName1", "pub const enumName1 = enum {};");
}

test "null initial fields allow assigning inferred fields before emission" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const enum_decl = try zast.EnumDeclaration.init(arena.allocator(), null, false, null);
    try std.testing.expect(@TypeOf(enum_decl) == *zast.EnumDeclaration);
    enum_decl.fields = &.{
        .{ .name = "unknown" },
        .{ .name = "ok" },
    };

    try expectRenderedEnum(enum_decl, "enumName", "pub const enumName = enum { unknown, ok, };");
}

test "enum validation rejects invalid inferred types before emitting any syntax" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const builder_allocator = arena.allocator();
    for (0..3) |invalid_case| {
        const invalid_fields = [_]zast.Field{.{
            .name = if (invalid_case == 2) "_" else "value",
            .value = if (invalid_case == 1) .{ .integer_literal = "0" } else null,
        }};
        const description = try zast.EnumDeclaration.init(builder_allocator, null, invalid_case == 0, &invalid_fields);
        var context: zast.AstContext = .{};
        defer context.deinit(allocator);
        _ = try context.addNode(allocator, .root, 0, undefined);

        try std.testing.expectError(error.MissingBackingType, description.emitType(allocator, &context));
        try std.testing.expectError(error.MissingBackingType, description.emit(allocator, &context, "Invalid", .public));
        try std.testing.expectEqual(@as(usize, 0), context.source.items.len);
        try std.testing.expectEqual(@as(usize, 0), context.tokens.len);
        try std.testing.expectEqual(@as(usize, 1), context.nodes.len);
        try std.testing.expectEqual(@as(usize, 0), context.extra_data.items.len);
        try std.testing.expectEqual(@as(usize, 0), context.declarations.items.len);
    }
}

test "enum initializer selects pointer mutability and borrows predefined fields" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const builder_allocator = arena.allocator();
    const mutable_enum = try zast.EnumDeclaration.init(builder_allocator, null, false, null);
    try std.testing.expect(@TypeOf(mutable_enum) == *zast.EnumDeclaration);
    mutable_enum.fields = &.{.{ .name = "unknown" }};
    try std.testing.expectEqualStrings("unknown", mutable_enum.fields[0].name);

    var initial_fields: std.ArrayList(zast.Field) = .empty;
    try initial_fields.append(builder_allocator, .{ .name = "unknown" });
    const fixed_enum = try zast.EnumDeclaration.init(builder_allocator, null, false, initial_fields.items);
    try std.testing.expect(@TypeOf(fixed_enum) == *const zast.EnumDeclaration);
    initial_fields.items[0].name = "changed";
    try expectRenderedEnum(fixed_enum, "Generated", "pub const Generated = enum { changed, };");

    const array_fields = [_]zast.Field{.{ .name = "ok" }};
    const array_enum = try zast.EnumDeclaration.init(builder_allocator, null, false, &array_fields);
    try std.testing.expect(@TypeOf(array_enum) == *const zast.EnumDeclaration);
    try std.testing.expectEqualStrings("ok", array_enum.fields[0].name);
    const empty_enum = try zast.EnumDeclaration.init(builder_allocator, null, false, &.{});
    try std.testing.expect(@TypeOf(empty_enum) == *const zast.EnumDeclaration);
    try std.testing.expectEqual(@as(usize, 0), empty_enum.fields.len);
}
