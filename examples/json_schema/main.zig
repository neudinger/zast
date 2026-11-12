//! Original JSON schema playground. Run with `zig build run-json-schema`.
//! This demonstrates enums, fields, and methods from a small reflection input.

const std = @import("std");
const reflection = @import("reflection");
const zast = @import("zast");

/// Generate UByte enums, a tagged union example, and structs with UInt fields.
/// Declaration descriptions use a temporary arena; returned AST uses allocator.
fn toAst(allocator: std.mem.Allocator, schema: reflection.Schema) !std.zig.Ast {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const builder_allocator = arena.allocator();

    var context: zast.AstContext = .{};
    defer context.deinit(allocator);

    // Reserve node zero; connect it after all declarations exist.
    _ = try context.addNode(allocator, .root, 0, undefined);

    {
        var enum_fields: std.ArrayList(zast.Field) = .empty;

        try enum_fields.append(builder_allocator, .{
            .name = "unknown",
        });
        try enum_fields.append(builder_allocator, .{
            .name = "ok",
        });

        const enum_decl: *const zast.EnumDeclaration = try zast.EnumDeclaration.init(
            builder_allocator,
            null,
            false,
            enum_fields.items,
        );

        try enum_decl.emit(allocator, &context, "Status", .public);
    }

    {
        const enum_fields = [_]zast.Field{
            .{ .name = "unknown" },
            .{ .name = "ok" },
        };
        const enum_decl: *const zast.EnumDeclaration = try zast.EnumDeclaration.init(
            builder_allocator,
            null,
            false,
            &enum_fields,
        );

        try enum_decl.emit(
            allocator,
            &context,
            "enumName0",
            .public,
        );
    }

    {
        const literal_one: zast.Expression = .{ .integer_literal = "1" };
        const shift_amount: zast.Expression = .{ .integer_literal = "4" };
        const shifted_value: zast.Expression = .{
            .shift_left = .{
                .left = &literal_one,
                .right = &shift_amount,
            },
        };

        var enum_decl: *zast.EnumDeclaration = try zast.EnumDeclaration.init(
            builder_allocator,
            "i16",
            false,
            null,
        );

        // try enum_decl.add(builder_allocator, "negative", .{ .negate = &literal_one });
        // try enum_decl.add(builder_allocator, "flag", shifted_value);
        // try enum_decl.add(builder_allocator, "negative_flag", .{ .negate = &shifted_value });
        enum_decl.fields = &.{
            .{ .name = "negative", .value = .{ .negate = &literal_one } },
            .{ .name = "flag", .value = shifted_value },
            .{ .name = "negative_flag", .value = .{ .negate = &shifted_value } },
        };

        try enum_decl.emit(allocator, &context, "ComputedStatus", .public);
    }

    {
        const enum_decl: *const zast.EnumDeclaration = try zast.EnumDeclaration.init(
            builder_allocator,
            null,
            false,
            null,
        );

        try enum_decl.emit(
            allocator,
            &context,
            "enumName1",
            .public,
        );
    }

    {
        var enum_decl: *zast.EnumDeclaration = try zast.EnumDeclaration.init(
            builder_allocator,
            null,
            false,
            null,
        );

        // try enum_decl.add(builder_allocator, "unknown", null);
        // try enum_decl.add(builder_allocator, "ok", null);
        enum_decl.fields = &.{
            .{ .name = "unknown" },
            .{ .name = "ok" },
        };

        try enum_decl.emit(
            allocator,
            &context,
            "enumName",
            .public,
        );
    }

    {
        const union_fields = [_]zast.Field{
            .{ .name = "none" },
            .{ .name = "number", .type_expression = .{ .identifier = "u32" } },
            .{ .name = "boolean", .type_expression = .{ .identifier = "bool" } },
        };
        const union_decl = try zast.UnionDeclaration.init(builder_allocator, .inferred, &union_fields);

        try union_decl.emit(allocator, &context, "Payload", .public);
    }

    for (schema.enums) |schema_enum| {
        if (schema_enum.is_union or schema_enum.underlying_type.base_type != .UByte)
            return error.UnsupportedEnum;

        // No unnamed values remain when all 256 u8 values have names.
        var enum_decl: *zast.EnumDeclaration = try zast.EnumDeclaration.init(
            builder_allocator,
            "u8",
            schema_enum.values.len < 256,
            null,
        );

        var enum_fields: std.ArrayList(zast.Field) = .empty;
        defer enum_fields.deinit(allocator);
        for (schema_enum.values) |enum_value| {
            const value_spelling = try std.fmt.allocPrint(builder_allocator, "{d}", .{enum_value.value});
            // try enum_decl.add(builder_allocator, enum_value.name, .{ .integer_literal = value_spelling });
            try enum_fields.append(
                allocator,
                .{ .name = enum_value.name, .value = .{ .integer_literal = value_spelling } },
            );
        }
        enum_decl.fields = enum_fields.items;

        try enum_decl.emit(
            allocator,
            &context,
            schema_enum.name,
            .public,
        );
    }

    for (schema.objects) |object| {
        if (object.is_struct) return error.UnsupportedStructLayout;
        var struct_members: std.ArrayList(zast.StructDeclaration.Member) = .empty;
        for (object.fields) |field| {
            if (field.type.base_type != .UInt or field.type.index != -1 or
                field.optional or field.deprecated or field.required or field.offset64)
                return error.UnsupportedField;
            const default_value = std.math.cast(u32, field.default_integer) orelse return error.InvalidDefault;
            const default_spelling = try std.fmt.allocPrint(builder_allocator, "{d}", .{default_value});
            try struct_members.append(builder_allocator, .{ .field = .{
                .name = field.name,
                .type_expression = .{ .identifier = "u32" },
                .value = .{ .integer_literal = default_spelling },
            } });
        }
        const method = try zast.FunctionDeclaration.init(
            builder_allocator,
            &.{},
            .{ .identifier = "u32" },
            .{ .statements = &.{.{ .return_value = .{ .integer_literal = "84" } }} },
        );
        try struct_members.append(builder_allocator, .{ .function = .{
            .name = "answerFunc",
            .declaration = method,
            .visibility = .public,
        } });
        const struct_decl = try zast.StructDeclaration.init(builder_allocator, .automatic, struct_members.items);
        const object_name = try std.fmt.allocPrint(builder_allocator, "{f}", .{std.zig.fmtId(object.name)});
        try struct_decl.emit(allocator, &context, object_name, .public);
    }

    const function_decl = try zast.FunctionDeclaration.init(
        builder_allocator,
        &.{},
        .{ .identifier = "u32" },
        .{ .statements = &.{
            .{ .return_value = .{ .integer_literal = "42" } },
        } },
    );
    try function_decl.emit(
        allocator,
        &context,
        "answer",
        .public,
    );

    std.debug.print("{s}\n", .{context.source.items});
    return context.finish(allocator);
}

pub fn main(init: std.process.Init) !void {
    // The arena owns every allocation in this example.
    // var arena = std.heap.ArenaAllocator.init(init.gpa);
    // defer arena.deinit();
    // const allocator = arena.allocator();
    const allocator = init.gpa;

    const json =
        \\{
        \\  "objects": [{
        \\    "name": "Reading",
        \\    "fields": [{
        \\      "name": "answer",
        \\      "type": {"base_type": "UInt"},
        \\      "default_integer": 65
        \\    }]
        \\  }],
        \\  "enums": [{
        \\    "name": "Status",
        \\    "values": [
        \\      {"name": "Unknown", "value": 0},
        \\      {"name": "Ok", "value": 1},
        \\      {"name": "Warning", "value": 2}
        \\    ],
        \\    "underlying_type": {
        \\      "base_type": "UByte"
        \\    }
        \\  }]
        \\}
    ;
    const parsed = try std.json.parseFromSlice(
        reflection.Schema,
        allocator,
        json,
        .{},
    );

    // The parsed value owns the borrowed JSON strings and slices.
    defer parsed.deinit();

    var tree = try toAst(allocator, parsed.value);
    const source = tree.source;
    defer allocator.free(source);
    defer tree.deinit(allocator);
    const rendered = try tree.renderAlloc(allocator);
    defer allocator.free(rendered);
    try std.Io.File.stdout().writeStreamingAll(init.io, rendered);
}
