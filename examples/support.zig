//! Shared finalization and printing for the small standalone examples.
//! Descriptions emit tokens and nodes directly. This helper connects the root
//! and renders that AST; parsing source is not part of code generation.

const std = @import("std");
const zast = @import("zast");

/// Print a declaration and release all temporary AST storage.
/// Pass `.public` to include `pub`, or `.private` to omit it.
/// The description and its borrowed fields remain owned by the example.
pub fn printDeclaration(
    init: std.process.Init,
    description: anytype,
    name: []const u8,
    visibility: zast.Declaration.Visibility,
) !void {
    const allocator = init.gpa;
    var context: zast.AstContext = .{};
    defer context.deinit(allocator);
    _ = try context.addNode(allocator, .root, 0, undefined);
    try description.emit(allocator, &context, name, visibility);

    // The AST owns its node buffers, but borrows the separately owned source.
    var tree = try context.finish(allocator);
    const source = tree.source;
    defer allocator.free(source);
    defer tree.deinit(allocator);
    const rendered = try tree.renderAlloc(allocator);
    defer allocator.free(rendered);
    try std.Io.File.stdout().writeStreamingAll(init.io, rendered);
}
