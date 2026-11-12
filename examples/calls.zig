//! Run with `zig build run-calls`.
//!
//! Expected output (the generated declaration evaluates to 42):
//! ```zig
//! pub const answer = @import("std").math.rotl(u8, 21, 1);
//! ```

const std = @import("std");
const zast = @import("zast");
const printDeclaration = @import("support.zig").printDeclaration;

pub fn main(init: std.process.Init) !void {
    const standard_library: zast.Expression = .{ .builtin_call = .{
        .name = "@import",
        .arguments = &.{.{ .string_literal = "\"std\"" }},
    } };
    const math_namespace: zast.Expression = .{ .field_access = .{
        .base = &standard_library,
        .name = "math",
    } };
    const rotate_function: zast.Expression = .{ .field_access = .{
        .base = &math_namespace,
        .name = "rotl",
    } };
    const rotation: zast.Expression = .{ .call = .{
        .callee = &rotate_function,
        .arguments = &.{
            .{ .identifier = "u8" },
            .{ .integer_literal = "21" },
            .{ .integer_literal = "1" },
        },
    } };
    try printDeclaration(init, zast.Declaration{ .value = rotation }, "answer", .public);
}
