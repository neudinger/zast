//! Run with `zig build run-rich-functions`.
//! The generated function uses only Zig's builtin types and error propagation.
//!
//! Expected output:
//! ```zig
//! pub fn forward(comptime Value: type, value: anyerror!Value) anyerror!Value {
//!     var result: Value = undefined;
//!     result = try value;
//!     return result;
//! }
//! ```

const std = @import("std");
const zast = @import("zast");
const printDeclaration = @import("support.zig").printDeclaration;

pub fn main(init: std.process.Init) !void {
    const value_type: zast.Expression = .{ .identifier = "Value" };
    const errors: zast.Expression = .{ .identifier = "anyerror" };
    const result_type: zast.Expression = .{ .error_union_type = .{
        .error_set = &errors,
        .payload_type = &value_type,
    } };
    const value: zast.Expression = .{ .identifier = "value" };
    const function: zast.FunctionDeclaration = .{
        .parameters = &.{
            .{ .name = "Value", .is_comptime = true, .type_expression = .{ .identifier = "type" } },
            .{ .name = "value", .type_expression = result_type },
        },
        .return_type = result_type,
        .body = .{ .statements = &.{
            .{ .declaration = .{ .name = "result", .declaration = .{
                .kind = .variable,
                .type_expression = value_type,
                .value = .{ .identifier = "undefined" },
            } } },
            .{ .assignment = .{
                .target = .{ .identifier = "result" },
                .value = .{ .@"try" = &value },
            } },
            .{ .return_value = .{ .identifier = "result" } },
        } },
    };
    try printDeclaration(init, &function, "forward", .public);
}
