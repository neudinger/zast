//! Shared container rendering and allocation-failure checks through enum and union declarations.
//!
//! ## Coverage
//!
//! - Empty bodies and bodies with one, two, or three members.
//! - Exact expected source for inferred enums and inferred tagged unions.
//! - Reparsing the rendered file without syntax errors.
//! - Cleanup when shared container or named-declaration emission cannot allocate.
//!
//! These tests exercise member-storage boundaries through the public generators.
//! Generator-specific behavior belongs in its own test module. Reparsing checks
//! syntax, not semantic validity.
//!
//! Run `zig build test` from the `zast` directory.

const std = @import("std");
const zast = @import("zast");
const helpers = @import("helpers.zig");

test "enum and union bodies preserve source across zero through three members" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const builder_allocator = arena.allocator();
    const field_descriptions = [_]zast.Field{
        .{ .name = "first" },
        .{ .name = "second" },
        .{ .name = "third" },
    };
    const expected_bodies = [_][]const u8{
        "{};\n",
        "{\n    first,\n};\n",
        "{\n    first,\n    second,\n};\n",
        "{\n    first,\n    second,\n    third,\n};\n",
    };
    inline for (.{ zast.EnumDeclaration, zast.UnionDeclaration }) |Description| {
        for (expected_bodies, 0..) |expected_body, member_count| {
            const description = if (Description == zast.EnumDeclaration)
                try zast.EnumDeclaration.init(builder_allocator, null, false, field_descriptions[0..member_count])
            else
                try zast.UnionDeclaration.init(builder_allocator, .inferred, field_descriptions[0..member_count]);

            const rendered = try helpers.renderDescription(allocator, description);
            defer allocator.free(rendered);
            const keyword = if (Description == zast.EnumDeclaration) "enum" else "union(enum)";
            const expected = try std.fmt.allocPrint(allocator, "pub const Generated = {s} {s}", .{
                keyword, expected_body,
            });
            defer allocator.free(expected);
            try std.testing.expectEqualStrings(expected, rendered);

            const parsed_source = try allocator.dupeSentinel(u8, rendered, 0);
            defer allocator.free(parsed_source);
            var parsed_tree = try std.zig.Ast.parse(allocator, parsed_source, .{ .mode = .zig });
            defer parsed_tree.deinit(allocator);
            try std.testing.expectEqual(@as(usize, 0), parsed_tree.errors.len);
        }
    }
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const builder_allocator = arena.allocator();
    const field_descriptions = [_]zast.Field{
        .{ .name = "first" },
        .{ .name = "second" },
        .{ .name = "third" },
    };
    inline for (.{ zast.EnumDeclaration, zast.UnionDeclaration }) |Description| {
        const description = if (Description == zast.EnumDeclaration)
            try zast.EnumDeclaration.init(builder_allocator, "u8", true, &field_descriptions)
        else
            try zast.UnionDeclaration.init(builder_allocator, .inferred, &field_descriptions);
        const rendered = try helpers.renderDescription(allocator, description);
        defer allocator.free(rendered);
    }
}

test "shared container and declaration emission clean up allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}
