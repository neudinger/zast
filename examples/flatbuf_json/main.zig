//! A small compiler-generated FlatBuffers schema JSON becomes Zig declarations.
//! Run `zig build run-flatbuf-json`. This demonstrates zast's components;
//! it is not a FlatBuffers implementation.

const std = @import("std");
const zast = @import("zast");
pub const Schema = @import("reflection").Schema;

pub const json = @embedFile("reading.json");
pub const expected_source = @embedFile("expected.zig");

/// Borrow input until emission completes. Temporary descriptions use an arena;
/// the caller owns the returned AST buffers and its separately allocated source.
/// This lesson maps only UByte enums and objects containing UInt fields.
pub fn toAst(allocator: std.mem.Allocator, schema: Schema) !std.zig.Ast {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const descriptions = arena.allocator();
    var context: zast.AstContext = .{};
    defer context.deinit(allocator);
    _ = try context.addNode(allocator, .root, 0, undefined);

    for (schema.enums) |schema_enum| {
        if (schema_enum.is_union or schema_enum.underlying_type.base_type != .UByte)
            return error.UnsupportedEnumBacking;
        const fields = try descriptions.alloc(zast.Field, schema_enum.values.len);
        for (schema_enum.values, fields) |enum_value, *field| {
            const value = std.math.cast(u8, enum_value.value) orelse return error.InvalidEnumValue;
            field.* = .{
                .name = try identifier(descriptions, enum_value.name),
                .value = .{ .integer_literal = try std.fmt.allocPrint(descriptions, "{d}", .{value}) },
            };
        }
        const declaration: zast.EnumDeclaration = .{
            .backing_type = "u8",
            .non_exhaustive = fields.len < 256,
            .fields = fields,
        };
        try declaration.emit(allocator, &context, try identifier(descriptions, schema_enum.name), .public);
    }

    for (schema.objects) |object| {
        if (object.is_struct) return error.UnsupportedObject;
        const members = try descriptions.alloc(zast.StructDeclaration.Member, object.fields.len);
        for (object.fields, members) |field, *member| {
            if (field.type.base_type != .UInt or field.type.index != -1 or
                field.optional or field.deprecated or field.required or field.offset64)
                return error.UnsupportedField;
            const default_value = std.math.cast(u32, field.default_integer) orelse return error.InvalidDefault;
            member.* = .{ .field = .{
                .name = try identifier(descriptions, field.name),
                .type_expression = .{ .identifier = "u32" },
                .value = .{ .integer_literal = try std.fmt.allocPrint(descriptions, "{d}", .{default_value}) },
            } };
        }
        const declaration: zast.StructDeclaration = .{ .members = members };
        try declaration.emit(allocator, &context, try identifier(descriptions, object.name), .public);
    }
    return context.finish(allocator);
}

fn identifier(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{f}", .{std.zig.fmtId(name)});
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const parsed = try std.json.parseFromSlice(Schema, allocator, json, .{});
    defer parsed.deinit();
    var tree = try toAst(allocator, parsed.value);
    const source = tree.source;
    defer allocator.free(source);
    defer tree.deinit(allocator);
    const rendered = try tree.renderAlloc(allocator);
    defer allocator.free(rendered);
    try std.Io.File.stdout().writeStreamingAll(init.io, rendered);
}
