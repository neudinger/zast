//! Small JSON-to-Zig example: rendering, escaping, and compiled declarations.
//! `generated_reading` is the example's actual stdout supplied by the build graph.

const std = @import("std");
const example = @import("flatbuf_json");
const generated = @import("generated_reading");
const helpers = @import("helpers.zig");

test "compiler-generated JSON renders the expected enum and struct" {
    const parsed = try std.json.parseFromSlice(example.Schema, std.testing.allocator, example.json, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("Reading", parsed.value.root_table.?.name);
    try std.testing.expectEqualStrings("//reading.fbs", parsed.value.fbs_files.?[0].filename);
    try std.testing.expectEqual(@as(u16, 4), parsed.value.objects[0].fields[0].offset);
    try expectRendering(std.testing.allocator, parsed.value, example.expected_source);
}

test "generated example declarations compile and preserve defaults and enum values" {
    const reading: generated.Reading = .{};
    try std.testing.expectEqual(u32, @FieldType(generated.Reading, "answer"));
    try std.testing.expectEqual(@as(u32, 65), reading.answer);
    try std.testing.expectEqual(@as(u8, 0), @backingInt(generated.Status.Unknown));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(generated.Status.Ok));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(generated.Status.Warning));
    const unnamed: generated.Status = @fromBackingInt(@intCast(255));
    try std.testing.expectEqual(@as(u8, 255), @backingInt(unnamed));
}

test "JSON example escapes names before creating identifier tokens" {
    try expectRendering(std.testing.allocator, .{
        .enums = &.{.{
            .name = "enum",
            .values = &.{.{ .name = "a-b", .value = 1 }},
            .underlying_type = &.{ .base_type = .UByte },
        }},
        .objects = &.{.{
            .name = "struct",
            .fields = &.{.{ .name = "const", .type = &.{ .base_type = .UInt } }},
        }},
    },
        \\pub const @"enum" = enum(u8) { @"a-b" = 1, _, };
        \\pub const @"struct" = struct { @"const": u32 = 0, };
    );
}

test "JSON example rejects scalar mappings outside the lesson" {
    try std.testing.expectError(error.UnsupportedEnumBacking, example.toAst(std.testing.allocator, .{
        .objects = &.{},
        .enums = &.{.{ .name = "Status", .values = &.{}, .underlying_type = &.{ .base_type = .UInt } }},
    }));
    try std.testing.expectError(error.UnsupportedField, example.toAst(std.testing.allocator, .{
        .enums = &.{},
        .objects = &.{.{
            .name = "Reading",
            .fields = &.{.{ .name = "answer", .type = &.{ .base_type = .UByte } }},
        }},
    }));
}

test "reflection numbers must fit the lesson's unsigned scalar types" {
    for ([_]i64{ -1, 256 }) |value| {
        try std.testing.expectError(error.InvalidEnumValue, example.toAst(std.testing.allocator, .{
            .objects = &.{},
            .enums = &.{.{
                .name = "Status",
                .values = &.{.{ .name = "Value", .value = value }},
                .underlying_type = &.{ .base_type = .UByte },
            }},
        }));
    }
    for ([_]i64{ -1, 4294967296 }) |value| {
        try std.testing.expectError(error.InvalidDefault, example.toAst(std.testing.allocator, .{
            .enums = &.{},
            .objects = &.{.{
                .name = "Reading",
                .fields = &.{.{ .name = "answer", .type = &.{ .base_type = .UInt }, .default_integer = value }},
            }},
        }));
    }
}

test "JSON generation releases every allocation on failure" {
    const parsed = try std.json.parseFromSlice(example.Schema, std.testing.allocator, example.json, .{});
    defer parsed.deinit();
    try std.testing.checkAllAllocationFailures(std.testing.allocator, expectRendering, .{ parsed.value, example.expected_source });
}

test "empty JSON description emits an empty file" {
    try expectRendering(std.testing.allocator, .{ .objects = &.{}, .enums = &.{} }, "");
}

fn expectRendering(backing_allocator: std.mem.Allocator, schema: example.Schema, expected_source: [:0]const u8) !void {
    // Force relocation so failure counts do not depend on in-place heap growth.
    var allocator_state = std.testing.FailingAllocator.init(backing_allocator, .{ .resize_fail_index = 0 });
    const allocator = allocator_state.allocator();
    var tree = try example.toAst(allocator, schema);
    const source = tree.source;
    defer allocator.free(source);
    defer tree.deinit(allocator);
    const rendered = try tree.renderAlloc(allocator);
    defer allocator.free(rendered);
    try helpers.expectFormattedSource(allocator, expected_source, rendered);
    // Verify that emitted tokens and manually linked nodes describe the same file.
    try helpers.expectFormattedSource(allocator, source, rendered);
}
