//! Borrowed type emitters compose through expressions without concrete imports.
//!
//! ## Coverage
//!
//! - Borrowed descriptors, deferred emission, and enclosing root registration.
//! - Anonymous enum, union, and struct types in calls, fields, and initializers.
//! - Function-type body omission, suffix grouping, and comptime parameters.
//! - Descriptor validation before mutation and propagation of custom errors.
//! - Nested namespaces and returned structs across allocation failures.
//!
//! ## Running
//!
//! Run `zig build test` from the `zast` directory via `test_all.zig`.
//! Assertions inspect AST links and tokens and compare parsed/rendered source.
//! Some expressions exercise syntax and grouping without representing valid
//! type operations, such as accessing a member of a function type.
//! Compile generated examples separately to check their semantic validity;
//! these tests do not compile the generated snippets.

const std = @import("std");
const zast = @import("zast");
const Ast = std.zig.Ast;
const helpers = @import("helpers.zig");

test "type adapters borrow descriptors and defer emission without root registration" {
    const Alias = struct {
        name: []const u8,
        emissions: *usize,

        pub fn emitType(self: *const @This(), allocator: std.mem.Allocator, context: *zast.AstContext) !Ast.Node.Index {
            self.emissions.* += 1;
            return context.identifierExpression(allocator, self.name);
        }
    };
    const allocator = std.testing.allocator;
    var emissions: usize = 0;
    var alias: Alias = .{ .name = "u8", .emissions = &emissions };
    const expression = zast.Expression.fromType(&alias);
    try std.testing.expectEqual(@as(usize, 0), emissions);
    alias.name = "u16";
    var context: zast.AstContext = .{};
    defer context.deinit(allocator);
    _ = try context.addNode(allocator, .root, 0, undefined);
    const node = try expression.emit(allocator, &context);
    try std.testing.expectEqual(.identifier, context.nodes.items(.tag)[@backingInt(node)]);
    try std.testing.expectEqual(@as(usize, 1), emissions);
    try std.testing.expectEqual(@as(usize, 0), context.declarations.items.len);
    try std.testing.expectEqualStrings("u16 ", context.source.items);
    const rendered = try helpers.renderDescription(allocator, zast.Declaration{ .value = expression });
    defer allocator.free(rendered);
    try helpers.expectFormattedSource(allocator, "pub const Generated = u16;", rendered);
    try std.testing.expectEqual(@as(usize, 2), emissions);
}

test "anonymous enum arguments preserve call ranges and register only the enclosing declaration" {
    const allocator = std.testing.allocator;
    const tags: zast.EnumDeclaration = .{ .backing_type = "u8", .fields = &.{
        .{ .name = "none", .value = .{ .integer_literal = "0" } },
        .{ .name = "text", .value = .{ .integer_literal = "1" } },
    } };
    const standard_library: zast.Expression = .{ .identifier = "std" };
    const array_function: zast.Expression = .{ .field_access = .{ .base = &standard_library, .name = "EnumArray" } };
    const counts: zast.Expression = .{ .call = .{
        .callee = &array_function,
        .arguments = &.{ zast.Expression.fromType(&tags), .{ .identifier = "u32" } },
    } };
    var context: zast.AstContext = .{};
    defer context.deinit(allocator);
    _ = try context.addNode(allocator, .root, 0, undefined);
    try (zast.Declaration{ .value = counts }).emit(allocator, &context, "Counts", .public);
    var tree = try context.finish(allocator);
    const source = tree.source;
    defer allocator.free(source);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), tree.rootDecls().len);
    const call_node = tree.fullVarDecl(tree.rootDecls()[0]).?.ast.init_node.unwrap().?;
    var call_buffer: [1]Ast.Node.Index = undefined;
    const arguments = tree.fullCall(&call_buffer, call_node).?.ast.params;
    try std.testing.expectEqual(@as(usize, 2), arguments.len);
    var container_buffer: [2]Ast.Node.Index = undefined;
    const enum_type = tree.fullContainerDecl(&container_buffer, arguments[0]).?.ast;
    try std.testing.expectEqual(.keyword_enum, tree.tokenTag(enum_type.main_token));
    try std.testing.expectEqual(@as(usize, 2), enum_type.members.len);
    try std.testing.expectEqualStrings("none", tree.tokenSlice(tree.nodeMainToken(enum_type.members[0])));
    try std.testing.expectEqualStrings("text", tree.tokenSlice(tree.nodeMainToken(enum_type.members[1])));
    try std.testing.expectEqual(.identifier, tree.nodeTag(arguments[1]));
    try std.testing.expectEqualStrings("u32", tree.tokenSlice(tree.nodeMainToken(arguments[1])));
    var parsed = try Ast.parse(allocator, source, .{});
    defer parsed.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), parsed.errors.len);
    try std.testing.expectEqualSlices(std.zig.Token.Tag, parsed.tokens.items(.tag), tree.tokens.items(.tag));
    const rendered = try tree.renderAlloc(allocator);
    defer allocator.free(rendered);
    try helpers.expectFormattedSource(allocator,
        \\pub const Counts = std.EnumArray(enum(u8) {
        \\    none = 0,
        \\    text = 1,
        \\}, u32);
    , rendered);
}

test "anonymous types compose in union tags, payload fields, pointers and initializers" {
    const allocator = std.testing.allocator;
    const tags: zast.EnumDeclaration = .{ .backing_type = "u8", .fields = &.{
        .{ .name = "none", .value = .{ .integer_literal = "0" } },
        .{ .name = "value", .value = .{ .integer_literal = "1" } },
    } };
    const record: zast.StructDeclaration = .{ .members = &.{.{ .field = .{
        .name = "count",
        .type_expression = .{ .identifier = "u32" },
        .value = .{ .integer_literal = "0" },
    } }} };
    const record_type = zast.Expression.fromType(&record);
    const payload: zast.UnionDeclaration = .{ .tag_type = .{ .enum_type = zast.Expression.fromType(&tags) }, .fields = &.{
        .{ .name = "none" },
        .{ .name = "value", .type_expression = record_type },
    } };
    const examples = [_]helpers.ExpressionCase{
        .{
            .expression = zast.Expression.fromType(&payload),
            .source = "pub const Generated = union((enum(u8) { none = 0, value = 1, })) { none, value: struct { count: u32 = 0, }, };",
        },
        .{
            .expression = .{ .pointer_type = .{ .child_type = &record_type, .is_const = true } },
            .source = "pub const Generated = *const struct { count: u32 = 0, };",
        },
        .{
            .expression = .{ .struct_init = .{ .type_expression = &record_type } },
            .source = "pub const Generated = struct { count: u32 = 0, }{};",
        },
    };
    for (examples) |example| try example.expect(allocator);
}

test "borrowed function types omit bodies and group before suffix expressions" {
    const allocator = std.testing.allocator;
    const invalid_body_type: zast.EnumDeclaration = .{ .backing_type = null, .non_exhaustive = true };
    const callback: zast.FunctionDeclaration = .{
        .parameters = &.{
            .{ .type_expression = .{ .identifier = "u32" } },
            .{ .type_expression = .{ .identifier = "bool" } },
        },
        .return_type = .{ .identifier = "u32" },
        .body = .{ .statements = &.{.{ .return_value = zast.Expression.fromType(&invalid_body_type) }} },
    };
    const callback_type = zast.Expression.fromType(&callback);
    const examples = [_]helpers.ExpressionCase{
        .{ .expression = callback_type, .source = "pub const Generated = fn (u32, bool) u32;" },
        .{
            .expression = .{ .pointer_type = .{ .child_type = &callback_type, .is_const = true } },
            .source = "pub const Generated = *const fn (u32, bool) u32;",
        },
        .{
            .expression = .{ .field_access = .{ .base = &callback_type, .name = "Result" } },
            .source = "pub const Generated = (fn (u32, bool) u32).Result;",
        },
    };
    // The final expression checks syntax/grouping, not a member of function types.
    for (examples) |example| try example.expect(allocator);
}

test "comptime parameters preserve modifiers and nested type nodes in multi-parameter prototypes" {
    const allocator = std.testing.allocator;
    const options: zast.StructDeclaration = .{ .members = &.{.{ .field = .{
        .name = "enabled",
        .type_expression = .{ .identifier = "bool" },
    } }} };
    const callback: zast.FunctionDeclaration = .{
        .parameters = &.{
            .{ .name = "capacity", .is_comptime = true, .type_expression = .{ .identifier = "usize" } },
            .{ .name = "options", .type_expression = zast.Expression.fromType(&options) },
        },
        .return_type = .{ .identifier = "type" },
    };
    var context: zast.AstContext = .{};
    defer context.deinit(allocator);
    _ = try context.addNode(allocator, .root, 0, undefined);
    try (zast.Declaration{ .value = zast.Expression.fromType(&callback) }).emit(allocator, &context, "Factory", .public);
    var tree = try context.finish(allocator);
    const source = tree.source;
    defer allocator.free(source);
    defer tree.deinit(allocator);
    const prototype_node = tree.fullVarDecl(tree.rootDecls()[0]).?.ast.init_node.unwrap().?;
    var prototype_buffer: [1]Ast.Node.Index = undefined;
    const prototype = tree.fullFnProto(&prototype_buffer, prototype_node).?;
    var parameters = prototype.iterate(&tree);
    const first = parameters.next().?;
    const second = parameters.next().?;
    try std.testing.expectEqual(.keyword_comptime, tree.tokenTag(first.comptime_noalias.?));
    try std.testing.expectEqualStrings("capacity", tree.tokenSlice(first.name_token.?));
    try std.testing.expectEqual(@as(?Ast.TokenIndex, null), second.comptime_noalias);
    try std.testing.expectEqualStrings("options", tree.tokenSlice(second.name_token.?));
    try std.testing.expectEqual(.keyword_struct, tree.tokenTag(tree.nodeMainToken(second.type_expr.?)));
    try std.testing.expect(parameters.next() == null);
    const rendered = try tree.renderAlloc(allocator);
    defer allocator.free(rendered);
    try helpers.expectFormattedSource(
        allocator,
        "pub const Factory = fn (comptime capacity: usize, options: struct { enabled: bool, }) type;",
        rendered,
    );
}

test "adapted validation and custom child errors propagate through nested declarations" {
    const allocator = std.testing.allocator;
    const invalid_enum: zast.EnumDeclaration = .{ .backing_type = null, .non_exhaustive = true };
    const invalid_union: zast.UnionDeclaration = .{ .tag_type = .untagged, .fields = &.{.{ .name = "missing" }} };
    const invalid_structure: zast.StructDeclaration = .{ .members = &.{.{ .field = .{ .name = "missing" } }} };
    const expressions = [_]zast.Expression{
        zast.Expression.fromType(&invalid_enum), zast.Expression.fromType(&invalid_union), zast.Expression.fromType(&invalid_structure),
    };
    const errors = [_]anyerror{ error.MissingBackingType, error.MissingFieldType, error.MissingFieldType };
    for (expressions, errors) |expression, expected_error| {
        var context: zast.AstContext = .{};
        defer context.deinit(allocator);
        _ = try context.addNode(allocator, .root, 0, undefined);
        try std.testing.expectError(expected_error, expression.emit(allocator, &context));
        try std.testing.expectEqual(@as(usize, 0), context.source.items.len);
        try std.testing.expectEqual(@as(usize, 0), context.tokens.len);
        try std.testing.expectEqual(@as(usize, 1), context.nodes.len);
        try std.testing.expectEqual(@as(usize, 0), context.extra_data.items.len);
        try std.testing.expectEqual(@as(usize, 0), context.declarations.items.len);
    }
    const RejectedType = struct {
        pub fn emitType(_: *const @This(), _: std.mem.Allocator, _: *zast.AstContext) error{RejectedType}!Ast.Node.Index {
            return error.RejectedType;
        }
    };
    const rejected: RejectedType = .{};
    const factory: zast.FunctionDeclaration = .{
        .return_type = .{ .identifier = "type" },
        .body = .{ .statements = &.{.{ .return_value = zast.Expression.fromType(&rejected) }} },
    };
    const outer: zast.StructDeclaration = .{ .members = &.{.{ .function = .{ .name = "Factory", .declaration = &factory } }} };
    try std.testing.expectError(error.RejectedType, helpers.renderDescription(allocator, &outer));
}

fn nestedTypeAllocationScenario(allocator: std.mem.Allocator) !void {
    const options: zast.StructDeclaration = .{ .members = &.{.{ .field = .{
        .name = "force_defaults",
        .type_expression = .{ .identifier = "bool" },
        .value = .{ .identifier = "false" },
    } }} };
    const payload: zast.UnionDeclaration = .{ .tag_type = .inferred, .fields = &.{
        .{ .name = "none" }, .{ .name = "count", .type_expression = .{ .identifier = "u32" } },
    } };
    const local: zast.StructDeclaration = .{ .members = &.{.{ .field = .{
        .name = "value",
        .type_expression = .{ .identifier = "u32" },
    } }} };
    const capacity: zast.Expression = .{ .identifier = "capacity" };
    const byte_type: zast.Expression = .{ .identifier = "u8" };
    const storage_type: zast.StructDeclaration = .{ .members = &.{
        .{ .field = .{ .name = "buffer", .type_expression = .{ .array_type = .{
            .length = &capacity,
            .child_type = &byte_type,
        } }, .value = .{ .identifier = "undefined" } } },
        .{ .field = .{ .name = "options", .type_expression = .{ .identifier = "WriteOptions" }, .value = .{ .struct_init = .{} } } },
        .{ .field = .{ .name = "extra", .type_expression = .{ .identifier = "LocalAlias" }, .value = .{ .identifier = "undefined" } } },
    } };
    const factory: zast.FunctionDeclaration = .{
        .parameters = &.{.{ .name = "capacity", .is_comptime = true, .type_expression = .{ .identifier = "usize" } }},
        .return_type = .{ .identifier = "type" },
        .body = .{ .statements = &.{
            .{ .declaration = .{ .name = "Local", .declaration = .{ .value = zast.Expression.fromType(&local) } } },
            .{ .declaration = .{ .name = "LocalAlias", .declaration = .{ .value = .{ .identifier = "Local" } } } },
            .{ .return_value = zast.Expression.fromType(&storage_type) },
        } },
    };
    const outer: zast.StructDeclaration = .{ .members = &.{
        .{ .declaration = .{ .name = "WriteOptions", .visibility = .public, .declaration = .{ .value = zast.Expression.fromType(&options) } } },
        .{ .declaration = .{ .name = "Payload", .visibility = .public, .declaration = .{ .value = zast.Expression.fromType(&payload) } } },
        .{ .function = .{ .name = "Storage", .visibility = .public, .declaration = &factory } },
    } };
    const rendered = try helpers.renderDescription(allocator, zast.Declaration{ .value = zast.Expression.fromType(&outer) });
    defer allocator.free(rendered);
    try helpers.expectFormattedSource(allocator,
        \\pub const Generated = struct {
        \\    pub const WriteOptions = struct { force_defaults: bool = false, };
        \\    pub const Payload = union(enum) { none, count: u32, };
        \\    pub fn Storage(comptime capacity: usize) type {
        \\        const Local = struct { value: u32, };
        \\        const LocalAlias = Local;
        \\        return struct {
        \\            buffer: [capacity]u8 = undefined,
        \\            options: WriteOptions = .{},
        \\            extra: LocalAlias = undefined,
        \\        };
        \\    }
        \\};
    , rendered);
}

test "nested namespace types and returned structs preserve ranges and clean up allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, nestedTypeAllocationScenario, .{});
}
