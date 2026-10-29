//! Function declarations, anonymous prototypes, methods, and composed bodies.
//!
//! ## Coverage
//!
//! - Borrowed parameters, pointer constness, and zero through three parameters.
//! - Anonymous prototypes, methods, comptime parameters, and composed types.
//! - Local declarations, nested blocks, assignments, returns, and `try` precedence.
//! - AST links, statement ranges, token spellings, and raw-source reparsing.
//! - Parameter validation, child emission errors, and allocation-failure cleanup.
//!
//! Parsed expectations establish syntax and formatting, not generated-code
//! compilation. Some fixtures intentionally leave referenced functions unresolved.
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

test "function initialization borrows parameters and selects pointer constness" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const builder_allocator = arena.allocator();
    const statements = [_]zast.Block.Statement{.{ .return_value = .{ .identifier = "changed" } }};
    var parameters: std.ArrayList(zast.FunctionDeclaration.Parameter) = .empty;
    try parameters.append(builder_allocator, .{ .name = "original", .type_expression = .{ .identifier = "u32" } });
    const fixed_function = try zast.FunctionDeclaration.init(builder_allocator, parameters.items, .{ .identifier = "u32" }, .{ .statements = &statements });
    try std.testing.expect(@TypeOf(fixed_function) == *const zast.FunctionDeclaration);
    try std.testing.expect(fixed_function.parameters.ptr == parameters.items.ptr);
    parameters.items[0].name = "changed";
    try expectRendered(fixed_function, "identity", "pub fn identity(changed: u32) u32 { return changed; }");

    const mutable_function = try zast.FunctionDeclaration.init(builder_allocator, null, .{ .identifier = "u32" }, .{ .statements = &statements });
    try std.testing.expect(@TypeOf(mutable_function) == *zast.FunctionDeclaration);
    mutable_function.parameters = parameters.items;
    try expectRendered(mutable_function, "identity", "pub fn identity(changed: u32) u32 { return changed; }");
    const empty_function = try zast.FunctionDeclaration.init(builder_allocator, &.{}, .{ .identifier = "void" }, .{});
    try std.testing.expect(@TypeOf(empty_function) == *const zast.FunctionDeclaration);
}

test "zero through three typed parameters render simple and multi prototypes" {
    const byte_type: zast.Expression = .{ .identifier = "u8" };
    const parameters = [_]zast.FunctionDeclaration.Parameter{
        .{ .name = "_", .type_expression = .{ .identifier = "u32" } },
        .{ .name = "_", .type_expression = .{ .identifier = "bool" } },
        .{ .name = "_", .type_expression = .{ .pointer_type = .{ .child_type = &byte_type, .is_const = true } } },
    };
    const expected_sources = [_][:0]const u8{
        "pub fn noop() void {}",
        "pub fn noop(_: u32) void {}",
        "pub fn noop(_: u32, _: bool) void {}",
        "pub fn noop(_: u32, _: bool, _: *const u8) void {}",
    };
    for (expected_sources, 0..) |expected_source, parameter_count| {
        const declaration: zast.FunctionDeclaration = .{ .parameters = parameters[0..parameter_count] };
        try expectRendered(&declaration, "noop", expected_source);
    }
}

test "function return expressions compose with parameters and pointer types" {
    const value: zast.Expression = .{ .identifier = "value" };
    const amount: zast.Expression = .{ .identifier = "amount" };
    const shift_function: zast.FunctionDeclaration = .{
        .parameters = &.{
            .{ .name = "value", .type_expression = .{ .identifier = "u32" } },
            .{ .name = "amount", .type_expression = .{ .identifier = "u5" } },
        },
        .return_type = .{ .identifier = "u32" },
        .body = .{ .statements = &.{.{ .return_value = .{ .shift_left = .{ .left = &value, .right = &amount } } }} },
    };
    try expectRendered(&shift_function, "shift", "pub fn shift(value: u32, amount: u5) u32 { return value << amount; }");

    const integer_type: zast.Expression = .{ .identifier = "u32" };
    const pointer_type: zast.Expression = .{ .pointer_type = .{ .child_type = &integer_type, .is_const = true } };
    const optional_pointer: zast.Expression = .{ .optional_type = &pointer_type };
    const pointer_function: zast.FunctionDeclaration = .{
        .parameters = &.{.{ .name = "value", .type_expression = optional_pointer }},
        .return_type = optional_pointer,
        .body = .{ .statements = &.{.{ .return_value = value }} },
    };
    try expectRendered(&pointer_function, "identity", "pub fn identity(value: ?*const u32) ?*const u32 { return value; }");
}

test "local declarations remain in their block and longer bodies use a member range" {
    const statements = [_]zast.Block.Statement{
        .{ .declaration = .{ .name = "first", .declaration = .{
            .type_expression = .{ .identifier = "u32" },
            .value = .{ .integer_literal = "42" },
        } } },
        .{ .declaration = .{ .name = "second", .declaration = .{ .value = .{ .identifier = "first" } } } },
        .{ .declaration = .{ .name = "third", .declaration = .{ .value = .{ .identifier = "second" } } } },
        .{ .return_value = .{ .identifier = "third" } },
    };
    const declaration: zast.FunctionDeclaration = .{ .return_type = .{ .identifier = "u32" }, .body = .{ .statements = &statements } };
    try expectRendered(&declaration, "answer",
        \\pub fn answer() u32 {
        \\    const first: u32 = 42;
        \\    const second = first;
        \\    const third = second;
        \\    return third;
        \\}
    );

    var context: zast.AstContext = .{};
    defer context.deinit(std.testing.allocator);
    _ = try context.addNode(std.testing.allocator, .root, 0, undefined);
    try declaration.emit(std.testing.allocator, &context, "answer", .private);
    try std.testing.expectEqual(@as(usize, 1), context.declarations.items.len);
    try std.testing.expect(std.mem.startsWith(u8, context.source.items, "fn answer"));
    const terminated = try std.testing.allocator.dupeSentinel(u8, context.source.items, 0);
    defer std.testing.allocator.free(terminated);
    var reparsed = try std.zig.Ast.parse(std.testing.allocator, terminated, .{ .mode = .zig });
    defer reparsed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), reparsed.errors.len);
    const rendered_raw = try reparsed.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered_raw);
    const rendered_ast = try helpers.renderNamedDescription(std.testing.allocator, &declaration, "answer", .private);
    defer std.testing.allocator.free(rendered_ast);
    try std.testing.expectEqualStrings(rendered_raw, rendered_ast);
}

test "nested blocks preserve outer ranges and trailing brace variants" {
    const base: zast.Expression = .{ .identifier = "base" };
    const amount: zast.Expression = .{ .identifier = "amount" };
    const nested_body: zast.Block = .{ .statements = &.{
        .{ .declaration = .{ .name = "shifted", .declaration = .{ .value = .{ .shift_left = .{ .left = &base, .right = &amount } } } } },
        .{ .declaration = .{ .name = "copied", .declaration = .{ .value = .{ .identifier = "shifted" } } } },
        .{ .return_value = .{ .identifier = "copied" } },
    } };
    const declaration: zast.FunctionDeclaration = .{
        .return_type = .{ .identifier = "u32" },
        .body = .{ .statements = &.{
            .{ .declaration = .{ .name = "base", .declaration = .{ .type_expression = .{ .identifier = "u32" }, .value = .{ .integer_literal = "1" } } } },
            .{ .declaration = .{ .name = "amount", .declaration = .{ .type_expression = .{ .identifier = "u5" }, .value = .{ .integer_literal = "4" } } } },
            .{ .block = &nested_body },
        } },
    };
    try expectRendered(&declaration, "nested",
        \\pub fn nested() u32 {
        \\    const base: u32 = 1;
        \\    const amount: u5 = 4;
        \\    {
        \\        const shifted = base << amount;
        \\        const copied = shifted;
        \\        return copied;
        \\    }
        \\}
    );
    const inner: zast.Block = .{ .statements = &.{.{ .return_value = .{ .integer_literal = "42" } }} };
    const single_block: zast.FunctionDeclaration = .{
        .return_type = .{ .identifier = "u32" },
        .body = .{ .statements = &.{.{ .block = &inner }} },
    };
    try expectRendered(&single_block, "nested", "pub fn nested() u32 { { return 42; } }");
}

test "void functions support expression statements and bare returns" {
    const declaration: zast.FunctionDeclaration = .{
        .parameters = &.{.{ .name = "nothing", .type_expression = .{ .identifier = "void" } }},
        .body = .{ .statements = &.{
            .{ .expression = .{ .identifier = "nothing" } },
            .{ .return_value = null },
        } },
    };
    try expectRendered(&declaration, "consume", "pub fn consume(nothing: void) void { nothing; return; }");
}

test "try preserves prefix and suffix precedence inside function returns" {
    const decode_function: zast.Expression = .{ .identifier = "decode" };
    const decode_call: zast.Expression = .{ .call = .{ .callee = &decode_function } };
    const unwrapped: zast.Expression = .{ .@"try" = &decode_call };
    const shift_amount: zast.Expression = .{ .integer_literal = "1" };
    const shifted: zast.Expression = .{ .shift_left = .{ .left = &decode_call, .right = &shift_amount } };
    const member: zast.Expression = .{ .field_access = .{ .base = &decode_call, .name = "value" } };
    const result_type: zast.Expression = .{ .identifier = "u32" };
    const error_type: zast.Expression = .{ .identifier = "anyerror" };
    const cases = [_]struct { expression: zast.Expression, spelling: []const u8 }{
        .{ .expression = unwrapped, .spelling = "try decode()" },
        .{ .expression = .{ .field_access = .{ .base = &unwrapped, .name = "value" } }, .spelling = "(try decode()).value" },
        .{ .expression = .{ .call = .{ .callee = &unwrapped } }, .spelling = "(try decode())()" },
        .{ .expression = .{ .negate = &unwrapped }, .spelling = "-try decode()" },
        .{ .expression = .{ .@"try" = &shifted }, .spelling = "try (decode() << 1)" },
        .{ .expression = .{ .@"try" = &unwrapped }, .spelling = "try try decode()" },
        .{ .expression = .{ .@"try" = &member }, .spelling = "try decode().value" },
    };
    // Unresolved decode signatures deliberately exercise distinct parse shapes.
    for (cases) |case| {
        const declaration: zast.FunctionDeclaration = .{
            .return_type = .{ .error_union_type = .{ .error_set = &error_type, .payload_type = &result_type } },
            .body = .{ .statements = &.{.{ .return_value = case.expression }} },
        };
        const expected = try std.fmt.allocPrintSentinel(std.testing.allocator, "pub fn read() anyerror!u32 {{ return {s}; }}", .{case.spelling}, 0);
        defer std.testing.allocator.free(expected);
        try expectRendered(&declaration, "read", expected);
    }
}

test "assignments link target and try nodes in inline and ranged blocks" {
    const allocator = std.testing.allocator;
    const builder: zast.Expression = .{ .identifier = "builder" };
    const decode_function: zast.Expression = .{ .identifier = "decode" };
    const decode_call: zast.Expression = .{ .call = .{
        .callee = &decode_function,
        .arguments = &.{ .{ .identifier = "first" }, .{ .identifier = "second" }, .{ .identifier = "third" } },
    } };
    const assignment: zast.Block.Statement = .{ .assignment = .{
        .target = .{ .field_access = .{ .base = &builder, .name = "force_defaults" } },
        .value = .{ .@"try" = &decode_call },
    } };
    const statements: [3]zast.Block.Statement = @splat(assignment);
    for (1..4) |statement_count| {
        var context: zast.AstContext = .{};
        defer context.deinit(allocator);
        _ = try context.addNode(allocator, .root, 0, undefined);
        const declaration: zast.FunctionDeclaration = .{ .body = .{ .statements = statements[0..statement_count] } };
        try declaration.emit(allocator, &context, "write", .public);
        var tree = try context.finish(allocator);
        const source = tree.source;
        defer allocator.free(source);
        defer tree.deinit(allocator);
        const body_node = tree.nodeData(tree.rootDecls()[0]).node_and_node[1];
        const expected_tag: std.zig.Ast.Node.Tag = if (statement_count <= 2) .block_two_semicolon else .block_semicolon;
        try std.testing.expectEqual(expected_tag, tree.nodeTag(body_node));
        var statement_buffer: [2]std.zig.Ast.Node.Index = undefined;
        const statement_nodes = tree.blockStatements(&statement_buffer, body_node).?;
        try std.testing.expectEqual(statement_count, statement_nodes.len);
        for (statement_nodes) |statement_node| {
            try std.testing.expectEqual(.assign, tree.nodeTag(statement_node));
            try std.testing.expectEqual(.equal, tree.tokenTag(tree.nodeMainToken(statement_node)));
            const target_node, const value_node = tree.nodeData(statement_node).node_and_node;
            try std.testing.expectEqual(.field_access, tree.nodeTag(target_node));
            const base_node, const member_token = tree.nodeData(target_node).node_and_token;
            try std.testing.expectEqualStrings("builder", tree.tokenSlice(tree.nodeMainToken(base_node)));
            try std.testing.expectEqualStrings("force_defaults", tree.tokenSlice(member_token));
            try std.testing.expectEqual(.@"try", tree.nodeTag(value_node));
            try std.testing.expectEqual(.keyword_try, tree.tokenTag(tree.nodeMainToken(value_node)));
            const call_node = tree.nodeData(value_node).node;
            var argument_buffer: [1]std.zig.Ast.Node.Index = undefined;
            const arguments = tree.fullCall(&argument_buffer, call_node).?.ast.params;
            try std.testing.expectEqual(@as(usize, 3), arguments.len);
            for (arguments, [_][]const u8{ "first", "second", "third" }) |argument_node, expected_name| {
                try std.testing.expectEqualStrings(expected_name, tree.tokenSlice(tree.nodeMainToken(argument_node)));
            }
            try std.testing.expectEqual(.semicolon, tree.tokenTag(tree.lastToken(statement_node) + 1));
        }
        // Parse raw spellings independently to catch mismatched tokens or links.
        var parsed = try std.zig.Ast.parse(allocator, source, .{});
        defer parsed.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), parsed.errors.len);
        try std.testing.expectEqualSlices(std.zig.Token.Tag, parsed.tokens.items(.tag), tree.tokens.items(.tag));
        const rendered = try tree.renderAlloc(allocator);
        defer allocator.free(rendered);
        try helpers.expectFormattedSource(allocator, source, rendered);
        try std.testing.expectEqual(@as(usize, 1), tree.rootDecls().len);
    }
}

test "generic functions compose try in declarations assignments statements and returns" {
    const value_type: zast.Expression = .{ .identifier = "Value" };
    const error_type: zast.Expression = .{ .identifier = "anyerror" };
    const decode_call: zast.Expression = .{ .call = .{
        .callee = &.{ .identifier = "decode" },
        .arguments = &.{value_type},
    } };
    const check_call: zast.Expression = .{ .call = .{
        .callee = &.{ .identifier = "check" },
        .arguments = &.{.{ .identifier = "result" }},
    } };
    const declaration: zast.FunctionDeclaration = .{
        .parameters = &.{.{ .name = "Value", .is_comptime = true, .type_expression = .{ .identifier = "type" } }},
        .return_type = .{ .error_union_type = .{ .error_set = &error_type, .payload_type = &value_type } },
        .body = .{ .statements = &.{
            .{ .declaration = .{ .name = "result", .declaration = .{ .kind = .variable, .value = .{ .@"try" = &decode_call } } } },
            .{ .assignment = .{ .target = .{ .identifier = "result" }, .value = .{ .@"try" = &decode_call } } },
            .{ .assignment = .{ .target = .{ .identifier = "_" }, .value = .{ .@"try" = &decode_call } } },
            .{ .expression = .{ .@"try" = &check_call } },
            .{ .return_value = .{ .@"try" = &decode_call } },
        } },
    };
    try expectRendered(&declaration, "read",
        \\pub fn read(comptime Value: type) anyerror!Value {
        \\    var result = try decode(Value);
        \\    result = try decode(Value);
        \\    _ = try decode(Value);
        \\    try check(result);
        \\    return try decode(Value);
        \\}
    );
}

test "comptime field names determine later parameter types in setters" {
    const record_type: zast.Expression = .{ .identifier = "Record" };
    const byte_type: zast.Expression = .{ .identifier = "u8" };
    const field_name: zast.Expression = .{ .identifier = "field" };
    const declaration: zast.FunctionDeclaration = .{
        .parameters = &.{
            .{ .name = "Record", .is_comptime = true, .type_expression = .{ .identifier = "type" } },
            .{ .name = "record", .type_expression = .{ .pointer_type = .{ .child_type = &record_type } } },
            .{ .name = "field", .is_comptime = true, .type_expression = .{ .slice_type = .{ .child_type = &byte_type, .is_const = true } } },
            .{ .name = "value", .type_expression = .{ .builtin_call = .{
                .name = "@FieldType",
                .arguments = &.{ record_type, field_name },
            } } },
        },
        .body = .{ .statements = &.{.{ .assignment = .{
            .target = .{ .builtin_call = .{
                .name = "@field",
                .arguments = &.{ .{ .identifier = "record" }, field_name },
            } },
            .value = .{ .identifier = "value" },
        } }} },
    };
    try expectRendered(&declaration, "setField",
        \\pub fn setField(comptime Record: type, record: *Record, comptime field: []const u8, value: @FieldType(Record, field)) void {
        \\    @field(record, field) = value;
        \\}
    );
}

test "try and assignments propagate child emission errors" {
    const invalid: zast.EnumDeclaration = .{ .backing_type = null, .non_exhaustive = true };
    const invalid_expression = zast.Expression.fromType(&invalid);
    const statements = [_]zast.Block.Statement{
        .{ .expression = .{ .@"try" = &invalid_expression } },
        .{ .assignment = .{ .target = invalid_expression, .value = .{ .integer_literal = "0" } } },
        .{ .assignment = .{ .target = .{ .identifier = "result" }, .value = .{ .@"try" = &invalid_expression } } },
    };
    for (statements) |statement| {
        var context: zast.AstContext = .{};
        defer context.deinit(std.testing.allocator);
        _ = try context.addNode(std.testing.allocator, .root, 0, undefined);
        try std.testing.expectError(error.MissingBackingType, statement.emit(std.testing.allocator, &context));
        try std.testing.expectEqual(@as(usize, 0), context.declarations.items.len);
    }
}

const FunctionType = struct {
    declaration: *const zast.FunctionDeclaration,

    pub fn emit(description: FunctionType, allocator: std.mem.Allocator, context: *zast.AstContext, name: []const u8, visibility: zast.Declaration.Visibility) !void {
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

test "emitType embeds anonymous prototypes with named or unnamed parameters" {
    const unnamed: zast.FunctionDeclaration = .{
        .parameters = &.{
            .{ .type_expression = .{ .identifier = "u32" } },
            .{ .type_expression = .{ .identifier = "bool" } },
        },
        .return_type = .{ .identifier = "u32" },
    };
    try expectRendered(FunctionType{ .declaration = &unnamed }, "Callback", "pub const Callback = fn (u32, bool) u32;");
    const named: zast.FunctionDeclaration = .{
        .parameters = &.{.{ .name = "value", .type_expression = .{ .identifier = "u32" } }},
        .return_type = .{ .identifier = "u32" },
    };
    try expectRendered(FunctionType{ .declaration = &named }, "Callback", "pub const Callback = fn (value: u32) u32;");
}

test "emitNode embeds a method whose prototype and body both use extra data" {
    const reading_type: zast.Expression = .{ .identifier = "Reading" };
    const receiver: zast.Expression = .{ .identifier = "self" };
    const field_value: zast.Expression = .{ .field_access = .{ .base = &receiver, .name = "answer" } };
    const amount: zast.Expression = .{ .identifier = "amount" };
    const declaration: zast.FunctionDeclaration = .{
        .parameters = &.{
            .{ .name = "self", .type_expression = .{ .pointer_type = .{ .child_type = &reading_type, .is_const = true } } },
            .{ .name = "amount", .type_expression = .{ .identifier = "u5" } },
        },
        .return_type = .{ .identifier = "u32" },
        .body = .{ .statements = &.{
            .{ .declaration = .{ .name = "shifted", .declaration = .{ .value = .{ .shift_left = .{ .left = &field_value, .right = &amount } } } } },
            .{ .declaration = .{ .name = "result", .declaration = .{ .value = .{ .identifier = "shifted" } } } },
            .{ .return_value = .{ .identifier = "result" } },
        } },
    };
    const structure: zast.StructDeclaration = .{ .members = &.{
        .{ .field = .{
            .name = "answer",
            .type_expression = .{ .identifier = "u32" },
            .value = .{ .integer_literal = "65" },
        } },
        .{ .function = .{ .name = "read", .declaration = &declaration, .visibility = .public } },
    } };
    try expectRendered(&structure, "Reading",
        \\pub const Reading = struct {
        \\    answer: u32 = 65,
        \\    pub fn read(self: *const Reading, amount: u5) u32 {
        \\        const shifted = self.answer << amount;
        \\        const result = shifted;
        \\        return result;
        \\    }
        \\};
    );
}

test "missing definition parameter names are rejected before any AST writes" {
    const allocator = std.testing.allocator;
    var parameters = [_]zast.FunctionDeclaration.Parameter{.{ .name = "value", .type_expression = .{ .identifier = "u32" } }};
    const declaration: zast.FunctionDeclaration = .{ .parameters = &parameters };
    parameters[0].name = null;
    var context: zast.AstContext = .{};
    defer context.deinit(allocator);
    _ = try context.addNode(allocator, .root, 0, undefined);
    try std.testing.expectError(error.MissingParameterName, declaration.emitNode(allocator, &context, "invalid", .public));
    try std.testing.expectError(error.MissingParameterName, declaration.emit(allocator, &context, "invalid", .public));
    try std.testing.expectEqual(@as(usize, 1), context.nodes.len);
    try std.testing.expectEqual(@as(usize, 0), context.tokens.len);
    try std.testing.expectEqual(@as(usize, 0), context.source.items.len);
    try std.testing.expectEqual(@as(usize, 0), context.extra_data.items.len);
    try std.testing.expectEqual(@as(usize, 0), context.declarations.items.len);
}

fn allocationScenario(backing_allocator: std.mem.Allocator) !void {
    // Force growing buffers to relocate while parent child ranges are live.
    var allocator_state = std.testing.FailingAllocator.init(backing_allocator, .{ .resize_fail_index = 0 });
    const allocator = allocator_state.allocator();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const parameters = [_]zast.FunctionDeclaration.Parameter{
        .{ .name = "value", .type_expression = .{ .identifier = "u32" } },
        .{ .name = "_", .is_comptime = true, .type_expression = .{ .identifier = "bool" } },
        .{ .name = "_", .type_expression = .{ .identifier = "void" } },
    };
    const decode_call: zast.Expression = .{ .call = .{
        .callee = &.{ .identifier = "decode" },
        .arguments = &.{ .{ .identifier = "value" }, .{ .integer_literal = "0" }, .{ .integer_literal = "1" } },
    } };
    const inner: zast.Block = .{ .statements = &.{
        .{ .declaration = .{ .name = "first", .declaration = .{ .kind = .variable, .value = .{ .identifier = "value" } } } },
        .{ .assignment = .{ .target = .{ .identifier = "first" }, .value = .{ .@"try" = &decode_call } } },
        .{ .declaration = .{ .name = "second", .declaration = .{ .value = .{ .identifier = "first" } } } },
        .{ .return_value = .{ .identifier = "second" } },
    } };
    const declaration = try zast.FunctionDeclaration.init(arena.allocator(), &parameters, .{ .identifier = "u32" }, .{ .statements = &.{.{ .block = &inner }} });
    const rendered = try helpers.renderNamedDescription(allocator, declaration, "identity", .public);
    defer allocator.free(rendered);
    const rendered_type = try helpers.renderNamedDescription(allocator, FunctionType{ .declaration = declaration }, "Callback", .public);
    defer allocator.free(rendered_type);
}

test "function and block emission clean up allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}
