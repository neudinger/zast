//! Run with `zig build run-blocks`.
//! Nested scopes compose local declarations, void calls, and a bare return.
//!
//! Expected output:
//! ```zig
//! pub const State = struct {
//!     value: u32 = 0,
//!     pub fn set(self: *@This(), value: u32) void {
//!         {
//!             const next = value;
//!             self.store(next);
//!         }
//!         return;
//!     }
//!     fn store(self: *@This(), value: u32) void {
//!         self.value = value;
//!     }
//! };
//! ```

const std = @import("std");
const zast = @import("zast");
const printDeclaration = @import("support.zig").printDeclaration;

pub fn main(init: std.process.Init) !void {
    const state_type: zast.Expression = .{ .builtin_call = .{ .name = "@This" } };
    const value_type: zast.Expression = .{ .identifier = "u32" };
    const parameters = [_]zast.FunctionDeclaration.Parameter{
        .{ .name = "self", .type_expression = .{ .pointer_type = .{ .child_type = &state_type } } },
        .{ .name = "value", .type_expression = value_type },
    };
    const self: zast.Expression = .{ .identifier = "self" };
    const value: zast.Expression = .{ .identifier = "value" };
    const inner: zast.Block = .{ .statements = &.{
        .{ .declaration = .{ .name = "next", .declaration = .{ .value = value } } },
        .{ .expression = .{ .call = .{
            .callee = &.{ .field_access = .{ .base = &self, .name = "store" } },
            .arguments = &.{.{ .identifier = "next" }},
        } } },
    } };
    const setter: zast.FunctionDeclaration = .{
        .parameters = &parameters,
        .body = .{ .statements = &.{ .{ .block = &inner }, .{ .return_value = null } } },
    };
    const store: zast.FunctionDeclaration = .{
        .parameters = &parameters,
        .body = .{ .statements = &.{.{ .assignment = .{
            .target = .{ .field_access = .{ .base = &self, .name = "value" } },
            .value = value,
        } }} },
    };
    const state: zast.StructDeclaration = .{ .members = &.{
        .{ .field = .{ .name = "value", .type_expression = value_type, .value = .{ .integer_literal = "0" } } },
        .{ .function = .{ .name = "set", .visibility = .public, .declaration = &setter } },
        .{ .function = .{ .name = "store", .declaration = &store } },
    } };
    try printDeclaration(init, &state, "State", .public);
}
