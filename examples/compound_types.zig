//! Run with `zig build run-compound-types`.
//! Compose borrowed type expressions, wrap them in `zast.Declaration`, and print aliases.
//!
//! Expected output:
//! ```zig
//! pub const Buffer = [4]u8;
//! pub const TerminatedBuffer = [4:0]u8;
//! pub const ManyBytes = [*]u8;
//! pub const TerminatedBytes = [*:0]const u8;
//! pub const CBytes = [*c]u8;
//! pub const QualifiedBytes = [*]allowzero align(1) const volatile u8;
//! pub const Text = [:0]const u8;
//! pub const Failure = error{ Invalid, Missing };
//! pub const NoFailure = error{};
//! pub const ReadResult = Failure![:0]const u8;
//! pub const InlineResult = error{ Invalid, Missing }![:0]const u8;
//! pub const MaybeBuffer = ?*const [4:0]u8;
//! ```

const std = @import("std");
const zast = @import("zast");
const printDeclaration = @import("support.zig").printDeclaration;

pub fn main(init: std.process.Init) !void {
    // Child descriptions stay in scope until every alias has been emitted.
    const byte_type: zast.Expression = .{ .identifier = "u8" };
    const length: zast.Expression = .{ .integer_literal = "4" };
    const zero: zast.Expression = .{ .integer_literal = "0" };
    const alignment: zast.Expression = .{ .integer_literal = "1" };
    const terminated_buffer: zast.Expression = .{ .array_type = .{
        .length = &length,
        .child_type = &byte_type,
        .sentinel = &zero,
    } };
    const text: zast.Expression = .{ .slice_type = .{
        .child_type = &byte_type,
        .sentinel = &zero,
        .is_const = true,
    } };
    const failures: zast.Expression = .{ .error_set_type = &.{ "Invalid", "Missing" } };
    // Refer to the named alias, or embed the error set itself below.
    const failure_type: zast.Expression = .{ .identifier = "Failure" };
    const buffer_pointer: zast.Expression = .{ .pointer_type = .{
        .child_type = &terminated_buffer,
        .is_const = true,
    } };

    const aliases = [_]struct { name: []const u8, value: zast.Expression }{
        .{ .name = "Buffer", .value = .{ .array_type = .{
            .length = &length,
            .child_type = &byte_type,
        } } },
        .{ .name = "TerminatedBuffer", .value = terminated_buffer },
        .{ .name = "ManyBytes", .value = .{ .pointer_type = .{
            .child_type = &byte_type,
            .kind = .{ .many = null },
        } } },
        .{ .name = "TerminatedBytes", .value = .{ .pointer_type = .{
            .child_type = &byte_type,
            .kind = .{ .many = &zero },
            .is_const = true,
        } } },
        // C pointers already allow zero; do not set is_allowzero here.
        .{ .name = "CBytes", .value = .{ .pointer_type = .{
            .child_type = &byte_type,
            .kind = .c,
        } } },
        .{ .name = "QualifiedBytes", .value = .{ .pointer_type = .{
            .child_type = &byte_type,
            .kind = .{ .many = null },
            .is_allowzero = true,
            .alignment = &alignment,
            .is_const = true,
            .is_volatile = true,
        } } },
        .{ .name = "Text", .value = text },
        .{ .name = "Failure", .value = failures },
        .{ .name = "NoFailure", .value = .{ .error_set_type = &.{} } },
        .{ .name = "ReadResult", .value = .{ .error_union_type = .{
            .error_set = &failure_type,
            .payload_type = &text,
        } } },
        .{ .name = "InlineResult", .value = .{ .error_union_type = .{
            .error_set = &failures,
            .payload_type = &text,
        } } },
        .{ .name = "MaybeBuffer", .value = .{ .optional_type = &buffer_pointer } },
    };
    for (aliases) |alias| {
        const declaration: zast.Declaration = .{ .value = alias.value };
        try printDeclaration(init, declaration, alias.name, .public);
    }
}
