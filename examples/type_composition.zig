//! Run with `zig build run-type-composition`.
//! The generated namespace uses only Zig's standard library.
//!
//! Expected output:
//! ```zig
//! pub const Generated = struct {
//!     const std = @import("std");
//!     pub const Counts = std.EnumArray(enum(u8) {
//!         none = 0,
//!         text = 1,
//!     }, u32);
//!     pub const Options = struct {
//!         enabled: bool = false,
//!     };
//!     pub fn Storage(comptime capacity: usize) type {
//!         return struct {
//!             buffer: [capacity]u8 = undefined,
//!         };
//!     }
//! };
//! ```

const std = @import("std");
const zast = @import("zast");
const printDeclaration = @import("support.zig").printDeclaration;

pub fn main(init: std.process.Init) !void {
    const tags: zast.EnumDeclaration = .{ .backing_type = "u8", .fields = &.{
        .{ .name = "none", .value = .{ .integer_literal = "0" } },
        .{ .name = "text", .value = .{ .integer_literal = "1" } },
    } };
    const options: zast.StructDeclaration = .{ .members = &.{.{ .field = .{
        .name = "enabled",
        .type_expression = .{ .identifier = "bool" },
        .value = .{ .identifier = "false" },
    } }} };
    const capacity: zast.Expression = .{ .identifier = "capacity" };
    const byte_type: zast.Expression = .{ .identifier = "u8" };
    const storage_type: zast.StructDeclaration = .{ .members = &.{.{ .field = .{
        .name = "buffer",
        .type_expression = .{ .array_type = .{ .length = &capacity, .child_type = &byte_type } },
        .value = .{ .identifier = "undefined" },
    } }} };
    const storage: zast.FunctionDeclaration = .{
        .parameters = &.{.{ .name = "capacity", .is_comptime = true, .type_expression = .{ .identifier = "usize" } }},
        .return_type = .{ .identifier = "type" },
        .body = .{ .statements = &.{.{ .return_value = zast.Expression.fromType(&storage_type) }} },
    };
    const standard_library: zast.Expression = .{ .identifier = "std" };
    const array_function: zast.Expression = .{ .field_access = .{ .base = &standard_library, .name = "EnumArray" } };
    const counts: zast.Expression = .{ .call = .{
        .callee = &array_function,
        .arguments = &.{ zast.Expression.fromType(&tags), .{ .identifier = "u32" } },
    } };
    const generated: zast.StructDeclaration = .{ .members = &.{
        .{ .declaration = .{ .name = "std", .declaration = .{ .value = .{ .builtin_call = .{
            .name = "@import",
            .arguments = &.{.{ .string_literal = "\"std\"" }},
        } } } } },
        .{ .declaration = .{ .name = "Counts", .visibility = .public, .declaration = .{ .value = counts } } },
        .{ .declaration = .{ .name = "Options", .visibility = .public, .declaration = .{ .value = zast.Expression.fromType(&options) } } },
        .{ .function = .{ .name = "Storage", .visibility = .public, .declaration = &storage } },
    } };
    try printDeclaration(init, &generated, "Generated", .public);
}
