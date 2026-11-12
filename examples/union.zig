//! Run with `zig build run-union`.
//!
//! Expected output:
//! ```zig
//! pub const Payload = union(enum) {
//!     none,
//!     number: u32,
//!     boolean: bool,
//! };
//! pub const RawPayload = union {
//!     number: u32,
//!     boolean: bool,
//! };
//! pub const Kind = enum {
//!     none,
//!     number,
//!     boolean,
//! };
//! pub const NamedPayload = union(Kind) {
//!     none,
//!     number: u32,
//!     boolean: bool,
//! };
//! pub const SizedPayload = union(enum(u8)) {
//!     none,
//!     number: u32,
//!     boolean: bool,
//! };
//! ```

const std = @import("std");
const zast = @import("zast");
const printDeclaration = @import("support.zig").printDeclaration;

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const fields = [_]zast.Field{
        .{ .name = "none" },
        .{ .name = "number", .type_expression = .{ .identifier = "u32" } },
        .{ .name = "boolean", .type_expression = .{ .identifier = "bool" } },
    };
    const declaration = try zast.UnionDeclaration.init(arena.allocator(), .inferred, &fields);
    try printDeclaration(init, declaration, "Payload", .public);

    // Untagged fields require explicit payload types; omit the implicit void case.
    const raw = try zast.UnionDeclaration.init(arena.allocator(), .untagged, fields[1..]);
    try printDeclaration(init, raw, "RawPayload", .public);

    const tags = [_]zast.Field{
        .{ .name = "none" },
        .{ .name = "number" },
        .{ .name = "boolean" },
    };
    const kind = try zast.EnumDeclaration.init(arena.allocator(), null, false, &tags);
    try printDeclaration(init, kind, "Kind", .public);
    const named = try zast.UnionDeclaration.init(
        arena.allocator(),
        .{ .enum_type = .{ .identifier = "Kind" } },
        &fields,
    );
    try printDeclaration(init, named, "NamedPayload", .public);

    const sized = try zast.UnionDeclaration.init(
        arena.allocator(),
        .{ .backing_type = .{ .identifier = "u8" } },
        &fields,
    );
    try printDeclaration(init, sized, "SizedPayload", .public);
}
