//! Run with `zig build run-struct`.
//!
//! Expected output:
//! ```zig
//! pub const Counter = struct {
//!     count: u32 = 7,
//!     enabled: bool = true,
//!     pub fn getCount(self: *const Counter) u32 {
//!         return self.count;
//!     }
//! };
//! pub const Point = extern struct {
//!     horizontal: f32,
//!     vertical: f32,
//! };
//! pub const Flags = packed struct {
//!     enabled: bool,
//!     priority: u7,
//! };
//! ```

const std = @import("std");
const zast = @import("zast");
const printDeclaration = @import("support.zig").printDeclaration;

pub fn main(init: std.process.Init) !void {
    const counter_type: zast.Expression = .{ .identifier = "Counter" };
    const self: zast.Expression = .{ .identifier = "self" };
    const get_count: zast.FunctionDeclaration = .{
        .parameters = &.{.{
            .name = "self",
            .type_expression = .{ .pointer_type = .{ .child_type = &counter_type, .is_const = true } },
        }},
        .return_type = .{ .identifier = "u32" },
        .body = .{ .statements = &.{.{ .return_value = .{
            .field_access = .{ .base = &self, .name = "count" },
        } }} },
    };
    const counter: zast.StructDeclaration = .{ .members = &.{
        .{ .field = .{
            .name = "count",
            .type_expression = .{ .identifier = "u32" },
            .value = .{ .integer_literal = "7" },
        } },
        .{ .field = .{
            .name = "enabled",
            .type_expression = .{ .identifier = "bool" },
            .value = .{ .identifier = "true" },
        } },
        .{ .function = .{ .name = "getCount", .declaration = &get_count, .visibility = .public } },
    } };
    try printDeclaration(init, &counter, "Counter", .public);

    const point: zast.StructDeclaration = .{ .layout = .@"extern", .members = &.{
        .{ .field = .{ .name = "horizontal", .type_expression = .{ .identifier = "f32" } } },
        .{ .field = .{ .name = "vertical", .type_expression = .{ .identifier = "f32" } } },
    } };
    try printDeclaration(init, &point, "Point", .public);

    const flags: zast.StructDeclaration = .{ .layout = .@"packed", .members = &.{
        .{ .field = .{ .name = "enabled", .type_expression = .{ .identifier = "bool" } } },
        .{ .field = .{ .name = "priority", .type_expression = .{ .identifier = "u7" } } },
    } };
    try printDeclaration(init, &flags, "Flags", .public);
}
