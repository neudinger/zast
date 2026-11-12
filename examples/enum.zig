//! Run with `zig build run-enum`.
//!
//! Expected output:
//! ```zig
//! pub const Status = enum(u8) {
//!     unknown = 0,
//!     ok = 1,
//!     warning = 2,
//!     _,
//! };
//! ```

const std = @import("std");
const zast = @import("zast");
const printDeclaration = @import("support.zig").printDeclaration;

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const fields = [_]zast.Field{
        .{ .name = "unknown", .value = .{ .integer_literal = "0" } },
        .{ .name = "ok", .value = .{ .integer_literal = "1" } },
        .{ .name = "warning", .value = .{ .integer_literal = "2" } },
    };
    const declaration = try zast.EnumDeclaration.init(arena.allocator(), "u8", true, &fields);
    try printDeclaration(init, declaration, "Status", .public);
}
