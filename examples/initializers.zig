//! Run with `zig build run-initializers`.
//!
//! Expected output:
//! ```zig
//! pub const descriptor = .{
//!     .options = .{ .required = true },
//!     .defaults = .{},
//!     .status = .unknown,
//!     .kind = .string,
//!     .values = .{ 1, 2, 3 },
//!     .bytes = [2]u8{ 4, 5 },
//! };
//! ```

const std = @import("std");
const zast = @import("zast");
const printDeclaration = @import("support.zig").printDeclaration;

pub fn main(init: std.process.Init) !void {
    const byte_type: zast.Expression = .{ .identifier = "u8" };
    const length: zast.Expression = .{ .integer_literal = "2" };
    const array_type: zast.Expression = .{ .array_type = .{
        .length = &length,
        .child_type = &byte_type,
    } };
    const descriptor: zast.Expression = .{ .struct_init = .{
        .fields = &.{
            .{ .name = "options", .value = .{ .struct_init = .{ .fields = &.{
                .{ .name = "required", .value = .{ .identifier = "true" } },
            } } } },
            .{ .name = "defaults", .value = .{ .struct_init = .{} } },
            .{ .name = "status", .value = .{ .enum_literal = "unknown" } },
            .{ .name = "kind", .value = .{ .enum_literal = "string" } },
            .{ .name = "values", .value = .{ .array_init = .{ .elements = &.{
                .{ .integer_literal = "1" }, .{ .integer_literal = "2" }, .{ .integer_literal = "3" },
            } } } },
            .{ .name = "bytes", .value = .{ .array_init = .{
                .type_expression = &array_type,
                .elements = &.{ .{ .integer_literal = "4" }, .{ .integer_literal = "5" } },
            } } },
        },
        .trailing_comma = true,
    } };
    try printDeclaration(init, zast.Declaration{ .value = descriptor }, "descriptor", .public);
}
