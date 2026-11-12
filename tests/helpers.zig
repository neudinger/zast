//! Shared rendering helpers for the component test modules (`test_*.zig`).
//!
//! ## Emission contract
//!
//! Descriptions provide `emit(allocator, context, name, visibility)`, which
//! appends a complete named declaration and registers its node in the context.
//!
//! Rendering builds the AST directly. `expectFormattedSource` parses expected
//! Zig source for comparison; neither operation type-checks generated source.
//!
//! ## Ownership and errors
//!
//! Descriptions and their borrowed data must remain valid until rendering ends.
//! The supplied allocator owns the temporary AST buffers and the returned text.
//! Temporary storage is released on success or failure; the caller frees the
//! returned slice with that allocator. Descriptor storage remains caller-owned.
//!
//! ## Example
//!
//! Place these statements inside a test block in a component test beside this
//! file. Run the suite with `zig build test` from the `zast` directory.
//!
//! ```zig
//! const std = @import("std");
//! const zast = @import("zast");
//! const helpers = @import("helpers.zig");
//! const allocator = std.testing.allocator;
//! const answer: zast.Declaration = .{ .value = .{ .integer_literal = "42" } };
//! const rendered = try helpers.renderNamedDescription(allocator, answer, "answer", .public);
//! defer allocator.free(rendered);
//! try helpers.expectFormattedSource(allocator, "pub const answer=42;", rendered);
//! ```
//!
//! ### Expected output
//!
//! ```zig
//! pub const answer = 42;
//! ```

const std = @import("std");
const zast = @import("zast");

/// Render a description as a public declaration named `Generated`.
///
/// Follows `renderNamedDescription`'s emission contract and ownership rules.
pub fn renderDescription(allocator: std.mem.Allocator, description: anytype) ![]u8 {
    return renderNamedDescription(allocator, description, "Generated", .public);
}

/// Emit named declarations into a fresh context, finalize its root, and render.
///
/// Accepts a value or pointer with `emit(allocator, *zast.AstContext, name, visibility)`.
/// The name must already be valid Zig identifier spelling. Descriptions may
/// register multiple root declarations.
///
/// ### Ownership and errors
///
/// The returned source belongs to the caller and must be freed with `allocator`.
/// Allocation and emission errors propagate; temporary AST buffers are cleaned up
/// on both success and failure.
pub fn renderNamedDescription(
    allocator: std.mem.Allocator,
    description: anytype,
    name: []const u8,
    visibility: zast.Declaration.Visibility,
) ![]u8 {
    var context: zast.AstContext = .{};
    defer context.deinit(allocator);
    _ = try context.addNode(allocator, .root, 0, undefined);
    try description.emit(allocator, &context, name, visibility);

    var tree = try context.finish(allocator);
    const owned_source = tree.source;
    defer allocator.free(owned_source);
    defer tree.deinit(allocator);
    return tree.renderAlloc(allocator);
}

/// Parse and format expected Zig, then compare it with already rendered source.
///
/// Both inputs are borrowed; `expected_source` must have a zero sentinel for
/// `std.zig.Ast`.
/// Requires no parse errors and releases all temporary storage on either path.
///
/// This checks syntax and formatting, not semantic validity or generated nodes.
pub fn expectFormattedSource(
    allocator: std.mem.Allocator,
    expected_source: [:0]const u8,
    rendered: []const u8,
) !void {
    var expected_tree = try std.zig.Ast.parse(allocator, expected_source, .{ .mode = .zig });
    defer expected_tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), expected_tree.errors.len);
    const expected_rendered = try expected_tree.renderAlloc(allocator);
    defer allocator.free(expected_rendered);
    try std.testing.expectEqualStrings(expected_rendered, rendered);
}

/// One independently parsed expected declaration for a generated expression.
///
/// Keeps the expression and its complete expected source beside each other.
pub const ExpressionCase = struct {
    /// Borrowed expression and children, valid until `expect` returns.
    expression: zast.Expression,
    /// Expected public declaration named `Generated`; also identifies failures.
    source: [:0]const u8,

    /// Render and compare one case, releasing all temporary allocations.
    ///
    /// The source string is printed on any emission, parsing, or match failure.
    pub fn expect(case: ExpressionCase, allocator: std.mem.Allocator) !void {
        errdefer std.debug.print("Expression case ({s}): {s}\n", .{ @tagName(case.expression), case.source });
        const rendered = try renderDescription(allocator, zast.Declaration{ .value = case.expression });
        defer allocator.free(rendered);
        try expectFormattedSource(allocator, case.source, rendered);
    }
};
