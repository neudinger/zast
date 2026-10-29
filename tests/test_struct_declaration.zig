//! Struct declarations combining fields, namespace bindings, and methods.
//!
//! ## Coverage
//!
//! - Borrowed members, pointer constness, deferred assignment, and empty structs.
//! - Layout headers, escaped identifiers, composed field types, and defaults.
//! - Contiguous field groups, surrounding declarations, and embedded type nodes.
//! - Invalid fields and methods rejected before any AST storage is changed.
//! - Allocation-failure cleanup across struct and method emission.
//!
//! Expected Zig is independently parsed and formatted for comparison with
//! generated output. These assertions do not compile the generated structs.
//!
//! Run the component tests with the full suite from `zast/`:
//!
//! ```sh
//! zig build test
//! ```
const std = @import("std");
const zast = @import("zast");
const helpers = @import("helpers.zig");

fn expectRendered(description: anytype, name: []const u8, expected_source: [:0]const u8) !void {
    const allocator = std.testing.allocator;
    const rendered = try helpers.renderNamedDescription(allocator, description, name, .public);
    defer allocator.free(rendered);
    try helpers.expectFormattedSource(allocator, expected_source, rendered);
}

test "struct initialization borrows members and selects pointer constness" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var members: std.ArrayList(zast.StructDeclaration.Member) = .empty;
    try members.append(arena.allocator(), .{ .field = .{
        .name = "count",
        .type_expression = .{ .identifier = "u32" },
    } });
    const fixed_structure = try zast.StructDeclaration.init(arena.allocator(), .automatic, members.items);
    try std.testing.expect(@TypeOf(fixed_structure) == *const zast.StructDeclaration);
    try std.testing.expect(fixed_structure.members.ptr == members.items.ptr);
    members.items[0].field.name = "changed";
    try expectRendered(fixed_structure, "Generated", "pub const Generated = struct { changed: u32, };");

    const deferred_structure = try zast.StructDeclaration.init(arena.allocator(), .automatic, null);
    try std.testing.expect(@TypeOf(deferred_structure) == *zast.StructDeclaration);
    deferred_structure.members = members.items;
    try expectRendered(deferred_structure, "Generated", "pub const Generated = struct { changed: u32, };");
    const empty_structure = try zast.StructDeclaration.init(arena.allocator(), .automatic, &.{});
    try std.testing.expect(@TypeOf(empty_structure) == *const zast.StructDeclaration);
    try expectRendered(empty_structure, "Generated", "pub const Generated = struct {};");
}

test "empty and zero through three named struct fields render correctly" {
    const members = [_]zast.StructDeclaration.Member{
        .{ .field = .{ .name = "first", .type_expression = .{ .identifier = "u32" } } },
        .{ .field = .{ .name = "second", .type_expression = .{ .identifier = "u16" } } },
        .{ .field = .{ .name = "third", .type_expression = .{ .identifier = "u8" } } },
    };
    const expected_sources = [_][:0]const u8{
        "pub const Generated = struct {};",
        "pub const Generated = struct { first: u32, };",
        "pub const Generated = struct { first: u32, second: u16, };",
        "pub const Generated = struct { first: u32, second: u16, third: u8, };",
    };
    for (expected_sources, 0..) |expected_source, field_count| {
        const declaration: zast.StructDeclaration = .{ .members = members[0..field_count] };
        try expectRendered(&declaration, "Generated", expected_source);
    }
}

test "struct fields compose slice and optional pointer types with defaults" {
    const byte_type: zast.Expression = .{ .identifier = "u8" };
    const integer_type: zast.Expression = .{ .identifier = "u32" };
    const pointer_type: zast.Expression = .{ .pointer_type = .{ .child_type = &integer_type, .is_const = true } };
    const declaration: zast.StructDeclaration = .{ .members = &.{
        .{ .field = .{
            .name = "message",
            .type_expression = .{ .slice_type = .{ .child_type = &byte_type, .is_const = true } },
            .value = .{ .string_literal = "\"hello\"" },
        } },
        .{ .field = .{
            .name = "count_ptr",
            .type_expression = .{ .optional_type = &pointer_type },
            .value = .{ .identifier = "null" },
        } },
    } };
    try expectRendered(&declaration, "Generated",
        \\pub const Generated = struct {
        \\    message: []const u8 = "hello",
        \\    count_ptr: ?*const u32 = null,
        \\};
    );
}

test "struct layout selects automatic extern or packed headers" {
    const members = [_]zast.StructDeclaration.Member{.{ .field = .{ .name = "value", .type_expression = .{ .identifier = "u8" } } }};
    const layouts = [_]zast.StructDeclaration.Layout{ .automatic, .@"extern", .@"packed" };
    const expected_sources = [_][:0]const u8{
        "pub const Generated = struct { value: u8, };",
        "pub const Generated = extern struct { value: u8, };",
        "pub const Generated = packed struct { value: u8, };",
    };
    for (layouts, expected_sources) |layout, expected_source| {
        const declaration: zast.StructDeclaration = .{ .layout = layout, .members = &members };
        try expectRendered(&declaration, "Generated", expected_source);
    }
}

test "namespace declarations can precede and follow one field group" {
    const declaration: zast.StructDeclaration = .{ .members = &.{
        .{ .declaration = .{
            .name = "default_count",
            .visibility = .public,
            .declaration = .{ .type_expression = .{ .identifier = "u32" }, .value = .{ .integer_literal = "7" } },
        } },
        .{ .field = .{
            .name = "count",
            .type_expression = .{ .identifier = "u32" },
            .value = .{ .identifier = "default_count" },
        } },
        .{ .declaration = .{
            .name = "counter",
            .visibility = .public,
            .declaration = .{ .kind = .variable, .type_expression = .{ .identifier = "u32" }, .value = .{ .integer_literal = "0" } },
        } },
    } };
    try expectRendered(&declaration, "Generated",
        \\pub const Generated = struct {
        \\    pub const default_count: u32 = 7;
        \\    count: u32 = default_count,
        \\    pub var counter: u32 = 0;
        \\};
    );
}

test "a function before fields still selects the final field comma layout" {
    const function: zast.FunctionDeclaration = .{
        .return_type = .{ .identifier = "u32" },
        .body = .{ .statements = &.{.{ .return_value = .{ .integer_literal = "1" } }} },
    };
    const declaration: zast.StructDeclaration = .{ .members = &.{
        .{ .function = .{ .name = "version", .declaration = &function, .visibility = .public } },
        .{ .field = .{ .name = "value", .type_expression = .{ .identifier = "u8" } } },
    } };
    try expectRendered(&declaration, "Generated",
        \\pub const Generated = struct {
        \\    pub fn version() u32 {
        \\        return 1;
        \\    }
        \\    value: u8,
        \\};
    );
}

const AnonymousStruct = struct {
    declaration: *const zast.StructDeclaration,

    pub fn emit(description: AnonymousStruct, allocator: std.mem.Allocator, context: *zast.AstContext, name: []const u8, visibility: zast.Declaration.Visibility) !void {
        if (visibility == .public) _ = try context.token(allocator, .keyword_pub, null);
        const declaration_token = try context.token(allocator, .keyword_const, null);
        _ = try context.token(allocator, .identifier, name);
        _ = try context.token(allocator, .equal, null);
        const type_node = try description.declaration.emitType(allocator, context);
        try std.testing.expectEqual(@as(usize, 0), context.declarations.items.len);
        _ = try context.token(allocator, .semicolon, null);
        const declaration_node = try context.addNode(allocator, .simple_var_decl, declaration_token, .{
            .opt_node_and_opt_node = .{ .none, type_node.toOptional() },
        });
        try context.declarations.append(allocator, @backingInt(declaration_node));
    }
};

test "emitType returns an unregistered struct expression for another construct" {
    const declaration: zast.StructDeclaration = .{ .members = &.{.{ .field = .{
        .name = "count",
        .type_expression = .{ .identifier = "u32" },
    } }} };
    try expectRendered(AnonymousStruct{ .declaration = &declaration }, "Alias", "pub const Alias = struct { count: u32, };");
}

test "struct errors are rejected before any AST writes even through borrowed aliases" {
    const allocator = std.testing.allocator;
    var parameters = [_]zast.FunctionDeclaration.Parameter{.{ .name = "value", .type_expression = .{ .identifier = "u32" } }};
    const method: zast.FunctionDeclaration = .{ .parameters = &parameters };
    const invalid_structures = [_]zast.StructDeclaration{
        .{ .members = &.{.{ .field = .{ .name = "missing" } }} },
        .{ .members = &.{
            .{ .field = .{ .name = "first", .type_expression = .{ .identifier = "u32" } } },
            .{ .declaration = .{ .name = "answer", .declaration = .{ .value = .{ .integer_literal = "42" } } } },
            .{ .field = .{ .name = "second", .type_expression = .{ .identifier = "u32" } } },
        } },
        .{ .members = &.{.{ .function = .{ .name = "invalid", .declaration = &method } }} },
    };
    parameters[0].name = null;
    const expected_errors = [_]anyerror{ error.MissingFieldType, error.NonContiguousFields, error.MissingParameterName };
    for (invalid_structures, expected_errors) |declaration, expected_error| {
        var context: zast.AstContext = .{};
        defer context.deinit(allocator);
        _ = try context.addNode(allocator, .root, 0, undefined);
        try std.testing.expectError(expected_error, declaration.emitType(allocator, &context));
        try std.testing.expectError(expected_error, declaration.emit(allocator, &context, "Invalid", .public));
        try std.testing.expectEqual(@as(usize, 1), context.nodes.len);
        try std.testing.expectEqual(@as(usize, 0), context.tokens.len);
        try std.testing.expectEqual(@as(usize, 0), context.source.items.len);
        try std.testing.expectEqual(@as(usize, 0), context.extra_data.items.len);
        try std.testing.expectEqual(@as(usize, 0), context.declarations.items.len);
    }
}

test "struct and field names support escaped Zig identifiers" {
    const declaration: zast.StructDeclaration = .{ .members = &.{.{ .field = .{
        .name = "@\"error\"",
        .type_expression = .{ .identifier = "u32" },
        .value = .{ .integer_literal = "1" },
    } }} };
    try expectRendered(&declaration, "@\"struct\"", "pub const @\"struct\" = struct { @\"error\": u32 = 1, };");
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const value: zast.Expression = .{ .identifier = "value" };
    const amount: zast.Expression = .{ .identifier = "amount" };
    const method = try zast.FunctionDeclaration.init(arena.allocator(), &[_]zast.FunctionDeclaration.Parameter{
        .{ .name = "value", .type_expression = .{ .identifier = "u32" } },
        .{ .name = "amount", .type_expression = .{ .identifier = "u5" } },
    }, .{ .identifier = "u32" }, .{ .statements = &.{
        .{ .declaration = .{ .name = "shifted", .declaration = .{ .value = .{ .shift_left = .{ .left = &value, .right = &amount } } } } },
        .{ .declaration = .{ .name = "result", .declaration = .{ .value = .{ .identifier = "shifted" } } } },
        .{ .return_value = .{ .identifier = "result" } },
    } });
    const members = [_]zast.StructDeclaration.Member{
        .{ .field = .{ .name = "answer", .type_expression = .{ .identifier = "u32" }, .value = .{ .integer_literal = "65" } } },
        .{ .function = .{ .name = "shift", .declaration = method, .visibility = .public } },
    };
    const declaration = try zast.StructDeclaration.init(arena.allocator(), .automatic, &members);
    const rendered = try helpers.renderNamedDescription(allocator, declaration, "Reading", .public);
    defer allocator.free(rendered);
}

test "struct and method emission clean up allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}
