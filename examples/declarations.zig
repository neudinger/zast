//! Run with `zig build run-declarations`.
//! A declaration combines a binding kind, an optional type, and a value.
//! In a type alias, the value is itself a type expression.
//! The first four declarations are public; the remaining four are private.
//!
//! Expected output:
//! ```zig
//! pub const Count = u32;
//! pub const answer = 42;
//! pub const typed_answer: u32 = 42;
//! pub var counter: u32 = 0;
//! const message: []const u8 = "hello";
//! var selected_message: []const u8 = "hello";
//! var maybe_count: ?u32 = null;
//! const counter_pointer: *u32 = &counter;
//! ```

const std = @import("std");
const zast = @import("zast");
const printDeclaration = @import("support.zig").printDeclaration;

pub fn main(init: std.process.Init) !void {
    const integer_type: zast.Expression = .{ .identifier = "u32" };
    const byte_type: zast.Expression = .{ .identifier = "u8" };
    const text_type: zast.Expression = .{ .slice_type = .{
        .child_type = &byte_type,
        .is_const = true,
    } };
    const counter_reference: zast.Expression = .{ .identifier = "counter" };

    // Descriptions and their borrowed children remain alive through emission.
    const declarations = [_]struct {
        name: []const u8,
        description: zast.Declaration,
        // Set .visibility = .private on an entry to omit pub.
        visibility: zast.Declaration.Visibility = .public,
    }{
        .{ .name = "Count", .description = .{ .value = integer_type } },
        .{ .name = "answer", .description = .{ .value = .{ .integer_literal = "42" } } },
        .{ .name = "typed_answer", .description = .{
            .type_expression = integer_type,
            .value = .{ .integer_literal = "42" },
        } },
        .{ .name = "counter", .description = .{
            .kind = .variable,
            .type_expression = integer_type,
            .value = .{ .integer_literal = "0" },
        } },
        .{ .name = "message", .visibility = .private, .description = .{
            .type_expression = text_type,
            .value = .{ .string_literal = "\"hello\"" },
        } },
        // var lets the binding select another string; its bytes remain const.
        .{ .name = "selected_message", .visibility = .private, .description = .{
            .kind = .variable,
            .type_expression = text_type,
            .value = .{ .string_literal = "\"hello\"" },
        } },
        .{ .name = "maybe_count", .visibility = .private, .description = .{
            .kind = .variable,
            .type_expression = .{ .optional_type = &integer_type },
            .value = .{ .identifier = "null" },
        } },
        // The binding is const, but *u32 still allows updating counter.
        .{ .name = "counter_pointer", .visibility = .private, .description = .{
            .type_expression = .{ .pointer_type = .{ .child_type = &integer_type } },
            .value = .{ .address_of = &counter_reference },
        } },
    };
    for (declarations) |declaration| {
        try printDeclaration(init, declaration.description, declaration.name, declaration.visibility);
    }
}
