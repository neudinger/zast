//! Union declarations built from borrowed fields and explicit tag descriptions.
//!
//! ## Coverage
//!
//! - List and array fields remain borrowed, including mutations through aliases.
//! - Pointer constness, deferred field assignment, and empty declarations.
//! - Untagged, inferred, integer-backed, and named-enum tag syntax.
//! - Missing untagged field types rejected before any AST storage is changed.
//!
//! Expected Zig is parsed and formatted with `std.zig.Ast`, then compared
//! with the generated AST's rendering. This does not type-check the unions.
//!
//! Run the component tests with the full suite from `zast/`:
//!
//! ```sh
//! zig build test
//! ```

const std = @import("std");
const zast = @import("zast");
const helpers = @import("helpers.zig");

fn expectRenderedUnion(declaration: *const zast.UnionDeclaration, expected_source: [:0]const u8) !void {
    const allocator = std.testing.allocator;
    const rendered = try helpers.renderDescription(allocator, declaration);
    defer allocator.free(rendered);
    try helpers.expectFormattedSource(allocator, expected_source, rendered);
}

test "union initializer borrows ArrayList fields through a const pointer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const builder_allocator = arena.allocator();
    var union_fields: std.ArrayList(zast.Field) = .empty;
    try union_fields.append(builder_allocator, .{ .name = "none" });
    try union_fields.append(builder_allocator, .{
        .name = "number",
        .type_expression = .{ .identifier = "u32" },
    });
    const union_decl = try zast.UnionDeclaration.init(builder_allocator, .inferred, union_fields.items);
    try std.testing.expect(@TypeOf(union_decl) == *const zast.UnionDeclaration);
    try std.testing.expect(union_decl.fields.ptr == union_fields.items.ptr);

    union_fields.items[0].name = "changed";
    try expectRenderedUnion(union_decl, "pub const Generated = union(enum) { changed, number: u32, };");
}

test "union initializer borrows a fixed field array through a const pointer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const union_fields = [_]zast.Field{
        .{ .name = "none" },
        .{ .name = "number", .type_expression = .{ .identifier = "u32" } },
        .{ .name = "boolean", .type_expression = .{ .identifier = "bool" } },
    };
    const union_decl = try zast.UnionDeclaration.init(arena.allocator(), .inferred, &union_fields);
    try std.testing.expect(@TypeOf(union_decl) == *const zast.UnionDeclaration);
    try std.testing.expect(union_decl.fields.ptr == union_fields[0..].ptr);
    try expectRenderedUnion(union_decl,
        \\pub const Generated = union(enum) {
        \\    none,
        \\    number: u32,
        \\    boolean: bool,
        \\};
    );
}

test "null union fields return a mutable pointer for deferred assignment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const union_decl = try zast.UnionDeclaration.init(arena.allocator(), .inferred, null);
    try std.testing.expect(@TypeOf(union_decl) == *zast.UnionDeclaration);
    union_decl.fields = &.{
        .{ .name = "none" },
        .{ .name = "number", .type_expression = .{ .identifier = "u32" } },
    };
    try expectRenderedUnion(union_decl, "pub const Generated = union(enum) { none, number: u32, };");
}

test "empty union descriptions accept null and an empty field slice" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const mutable_union = try zast.UnionDeclaration.init(arena.allocator(), .inferred, null);
    try std.testing.expect(@TypeOf(mutable_union) == *zast.UnionDeclaration);
    try expectRenderedUnion(mutable_union, "pub const Generated = union(enum) {};");

    const fixed_union = try zast.UnionDeclaration.init(arena.allocator(), .inferred, &.{});
    try std.testing.expect(@TypeOf(fixed_union) == *const zast.UnionDeclaration);
    try expectRenderedUnion(fixed_union, "pub const Generated = union(enum) {};");
}

test "borrowed fields preserve all four union tag syntaxes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const namespace_expression: zast.Expression = .{ .identifier = "tags" };
    const union_fields = [_]zast.Field{
        .{ .name = "none", .type_expression = .{ .identifier = "void" } },
        .{ .name = "number", .type_expression = .{ .identifier = "u32" } },
    };
    const tag_types = [_]zast.UnionDeclaration.TagType{
        .untagged,
        .inferred,
        .{ .backing_type = .{ .identifier = "u8" } },
        .{ .enum_type = .{ .field_access = .{ .base = &namespace_expression, .name = "Kind" } } },
    };
    const expected_sources = [_][:0]const u8{
        "pub const Generated = union { none: void, number: u32, };",
        "pub const Generated = union(enum) { none: void, number: u32, };",
        "pub const Generated = union(enum(u8)) { none: void, number: u32, };",
        "pub const Generated = union(tags.Kind) { none: void, number: u32, };",
    };
    for (tag_types, expected_sources) |tag_type, expected_source| {
        const union_decl = try zast.UnionDeclaration.init(arena.allocator(), tag_type, &union_fields);
        try expectRenderedUnion(union_decl, expected_source);
    }
}

test "untagged unions validate current borrowed fields before emitting any syntax" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var union_fields = [_]zast.Field{
        .{ .name = "number", .type_expression = .{ .identifier = "u32" } },
    };
    const union_decl = try zast.UnionDeclaration.init(arena.allocator(), .untagged, &union_fields);
    try expectRenderedUnion(union_decl, "pub const Generated = union { number: u32, };");

    // A const declaration still borrows fields that another reference can change.
    union_fields[0].type_expression = null;
    var context: zast.AstContext = .{};
    defer context.deinit(allocator);
    _ = try context.addNode(allocator, .root, 0, undefined);
    try std.testing.expectError(error.MissingFieldType, union_decl.emitType(allocator, &context));
    try std.testing.expectError(error.MissingFieldType, union_decl.emit(allocator, &context, "Invalid", .public));
    try std.testing.expectEqual(@as(usize, 0), context.source.items.len);
    try std.testing.expectEqual(@as(usize, 0), context.tokens.len);
    try std.testing.expectEqual(@as(usize, 1), context.nodes.len);
    try std.testing.expectEqual(@as(usize, 0), context.extra_data.items.len);
    try std.testing.expectEqual(@as(usize, 0), context.declarations.items.len);
}
