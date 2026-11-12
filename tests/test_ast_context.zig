//! Finalized trees retain their storage after the emitting context is released.
//!
//! ## Coverage
//!
//! - Empty files and files containing one named declaration.
//! - Root declaration counts, the EOF token, and the source's zero sentinel.
//! - Rendering after context cleanup, with the expected source checked exactly.
//! - Separate release of the finished tree and its borrowed source buffer.
//! - Cleanup at every injected allocation failure.
//!
//! ## Allocation setup
//!
//! The scenario disables allocator resizing to force owned-slice fallbacks.
//! This makes allocation-failure coverage deterministic without changing the
//! production context's allocator behavior.
//!
//! Run `zig build test` from the `zast` directory.

const std = @import("std");
const zast = @import("zast");

fn finishAllocationScenario(backing_allocator: std.mem.Allocator, emit_declaration: bool) !void {
    // Force owned-slice fallbacks so every allocation can fail deterministically.
    var allocator_state = std.testing.FailingAllocator.init(backing_allocator, .{ .resize_fail_index = 0 });
    const allocator = allocator_state.allocator();
    var tree = finished: {
        var context: zast.AstContext = .{};
        defer context.deinit(allocator);
        _ = try context.addNode(allocator, .root, 0, undefined);
        if (emit_declaration) {
            const declaration: zast.Declaration = .{ .value = .{ .integer_literal = "42" } };
            try declaration.emit(allocator, &context, "answer", .public);
        }
        break :finished try context.finish(allocator);
    };
    const source = tree.source;
    defer allocator.free(source);
    defer tree.deinit(allocator);

    try std.testing.expectEqual(@as(usize, @intFromBool(emit_declaration)), tree.rootDecls().len);
    try std.testing.expectEqual(.eof, tree.tokens.items(.tag)[tree.tokens.len - 1]);
    try std.testing.expectEqual(@as(u8, 0), source[source.len]);
    const rendered = try tree.renderAlloc(allocator);
    defer allocator.free(rendered);
    try std.testing.expectEqualStrings(if (emit_declaration) "pub const answer = 42;\n" else "", rendered);
}

test "finish transfers empty and populated trees and cleans up allocation failures" {
    for ([_]bool{ false, true }) |emit_declaration| {
        try std.testing.checkAllAllocationFailures(std.testing.allocator, finishAllocationScenario, .{emit_declaration});
    }
}
