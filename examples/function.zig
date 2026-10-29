//! Run with `zig build run-function`.
//!
//! Expected output:
//! ```zig
//! pub fn identity(value: u32) u32 {
//!     return value;
//! }
//! ```

const std = @import("std");
const zast = @import("zast");
const printDeclaration = @import("support.zig").printDeclaration;

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const parameters = [_]zast.FunctionDeclaration.Parameter{
        .{ .name = "value", .type_expression = .{ .identifier = "u32" } },
    };
    const statements = [_]zast.Block.Statement{
        .{ .return_value = .{ .identifier = "value" } },
    };
    const declaration = try zast.FunctionDeclaration.init(
        arena.allocator(),
        &parameters,
        .{ .identifier = "u32" },
        .{ .statements = &statements },
    );
    try printDeclaration(init, declaration, "identity", .public);
}
