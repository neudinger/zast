//! Run with `zig build run-function-types`.
//! Function type parameters omit names; the default callback is callable.
//!
//! Expected output:
//! ```zig
//! pub const Handler = struct {
//!     callback: *const fn (u32, u5) u32 = shift,
//!     fn shift(value: u32, amount: u5) u32 {
//!         return value << amount;
//!     }
//! };
//! ```

const std = @import("std");
const zast = @import("zast");
const printDeclaration = @import("support.zig").printDeclaration;

pub fn main(init: std.process.Init) !void {
    const value_type: zast.Expression = .{ .identifier = "u32" };
    const amount_type: zast.Expression = .{ .identifier = "u5" };
    const signature: zast.FunctionDeclaration = .{
        .parameters = &.{
            .{ .type_expression = value_type },
            .{ .type_expression = amount_type },
        },
        .return_type = value_type,
    };
    const callback_type = zast.Expression.fromType(&signature);
    const value: zast.Expression = .{ .identifier = "value" };
    const amount: zast.Expression = .{ .identifier = "amount" };
    const shift: zast.FunctionDeclaration = .{
        .parameters = &.{
            .{ .name = "value", .type_expression = value_type },
            .{ .name = "amount", .type_expression = amount_type },
        },
        .return_type = value_type,
        .body = .{ .statements = &.{.{ .return_value = .{ .shift_left = .{
            .left = &value,
            .right = &amount,
        } } }} },
    };
    const handler: zast.StructDeclaration = .{ .members = &.{
        .{ .field = .{
            .name = "callback",
            .type_expression = .{ .pointer_type = .{ .child_type = &callback_type, .is_const = true } },
            .value = .{ .identifier = "shift" },
        } },
        .{ .function = .{ .name = "shift", .declaration = &shift } },
    } };
    try printDeclaration(init, &handler, "Handler", .public);
}
