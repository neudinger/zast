//! Unmanaged storage used to construct one Zig file's tokens and AST nodes.
//!
//! ## Lifecycle
//!
//! Start with `var context: AstContext = .{};` and reserve the `.root` node at
//! index zero before emitting children. Tokens describe source spelling; nodes
//! describe how the constructs connect. Both must agree for rendering to work.
//!
//! `source.items` contains unformatted token text, not the pretty-printed result.
//! Call `finish` after emission, then render the returned tree with `renderAlloc`.
//!
//! ## Ownership and errors
//!
//! Pass the same allocator to every operation on these buffers, including
//! `deinit`. Allocating operations can leave partial output on failure; clean up
//! the context rather than rendering or retrying from that partial state.
//!
//! Descriptions can use a separate arena; AST buffers must remain valid for the
//! finished tree's lifetime.
//! Buffer growth invalidates pointers and slices into `source`, `tokens`, `nodes`,
//! and `extra_data`. Keep indexes and reacquire buffer views after child emission;
//! borrowed spellings and input slices must not alias buffers being grown.
//! Node, token, source-offset, and extra-data indexes must fit their `u32` storage.
//!
//! ## Complete example
//!
//! Generate, finalize, render, and release a declaration.
//! Save this example as `example_test.zig` in the `zast/` package directory, then run
//! `zig test --dep zast -Mroot=example_test.zig -Mzast=src/root.zig`.
//!
//! ```zig
//! const std = @import("std");
//! const AstContext = @import("zast").AstContext;
//! const Declaration = @import("zast").Declaration;
//!
//! test "render a generated declaration" {
//!     const allocator = std.testing.allocator;
//!     var context: AstContext = .{};
//!     defer context.deinit(allocator);
//!     _ = try context.addNode(allocator, .root, 0, undefined);
//!
//!     const answer: Declaration = .{
//!         .value = .{ .integer_literal = "42" },
//!     };
//!     try answer.emit(allocator, &context, "answer", .public);
//!
//!     var tree = try context.finish(allocator);
//!     // Ast borrows source; save it before tree.deinit invalidates the tree.
//!     const owned_source = tree.source;
//!     defer allocator.free(owned_source);
//!     defer tree.deinit(allocator);
//!     const rendered_source = try tree.renderAlloc(allocator);
//!     defer allocator.free(rendered_source);
//!     try std.testing.expectEqualStrings(
//!         "pub const answer = 42;\n",
//!         rendered_source,
//!     );
//! }
//! ```
//!
//! ### Expected output
//!
//! The formatted source is stored in `rendered_source`:
//!
//! ```zig
//! pub const answer = 42;
//! ```

const std = @import("std");
/// The file itself is the AstContext struct; no allocator is stored in it.
const Self = @This();

/// Owned, growable token text. `token` separates spellings with spaces.
/// Add the zero sentinel only when transferring this buffer into an Ast.
source: std.ArrayList(u8) = .empty,
/// Token tags and byte offsets into `source`; token indexes address this list.
tokens: std.zig.Ast.TokenList = .empty,
/// Syntax nodes and their links. Node zero must be the file's `.root` node.
nodes: std.zig.Ast.NodeList = .empty,
/// Packed u32 payloads used by node layouts that cannot store all data inline.
/// A node's tag determines whether entries hold indexes, ranges, or other data.
extra_data: std.ArrayList(u32) = .empty,
/// Root declaration node indexes, in source order. Finalization copies these
/// into `extra_data` and assigns that range to the root node.
declarations: std.ArrayList(u32) = .empty,

/// Release buffers still owned here with the allocator used to allocate them.
///
/// Buffers moved out by `finish` are no longer owned here: the `std.zig.Ast` frees
/// its tokens, nodes, and extra data; the caller separately frees its source.
/// Do not use the context again without reinitializing it to `.{}`.
pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    inline for (.{ "source", "tokens", "nodes", "extra_data", "declarations" }) |field_name| {
        @field(self, field_name).deinit(allocator);
    }
}

/// Connect the root declarations, append EOF, and transfer buffers into an AST.
///
/// ### Preconditions and errors
///
/// Call once after all emission, with a `.root` node reserved at index zero.
/// Does not parse or validate syntax. Allocation errors leave partial state;
/// call `deinit` instead of retrying or continuing emission.
///
/// ### Ownership after success
///
/// - Save `tree.source` before calling `tree.deinit(allocator)`.
/// - Free the saved source slice separately with the same allocator.
/// - Call the context's `deinit` on both success and failure; it still owns
///   its declarations buffer after successful finalization.
/// - Do not emit into or finish the context again. The returned tree owns its
///   transferred buffers; context cleanup does not release those buffers.
///
/// The module example demonstrates the required cleanup order.
pub fn finish(context: *Self, allocator: std.mem.Allocator) !std.zig.Ast {
    // Root members follow any extra data already written by child constructs.
    const declarations_start = try context.addExtra(allocator, context.declarations.items);
    context.nodes.items(.data)[0] = .{ .extra_range = .{
        .start = declarations_start,
        .end = @fromBackingInt(@intCast(context.extra_data.items.len)),
    } };
    _ = try context.token(allocator, .eof, "");

    const source = try context.source.toOwnedSliceSentinel(allocator, 0);
    errdefer allocator.free(source);
    const extra_data = try context.extra_data.toOwnedSlice(allocator);
    return .{
        .source = source,
        .tokens = context.tokens.toOwnedSlice(),
        .nodes = context.nodes.toOwnedSlice(),
        .extra_data = extra_data,
        .errors = &.{},
    };
}

/// Append a syntax node and return its index in this context.
///
/// - `main_token` identifies its principal token, not necessarily its first one.
/// - `data` must use the layout documented for `tag` in `std.zig.Ast.Node.Tag`.
/// - Use `undefined` only where that tag ignores data, such as an identifier,
///   or for the reserved root that will be filled before rendering.
///
/// This does not append tokens or register a root declaration.
///
/// ### Example
///
/// With an allocator and a context whose root is reserved:
///
/// ```zig
/// const number_token = try context.token(allocator, .number_literal, "42");
/// const number_node = try context.addNode(
///     allocator, .number_literal, number_token, undefined,
/// );
/// // The enclosing expression or declaration must attach number_node.
/// ```
///
/// ### Expected output
///
/// Appended source bytes, quoted to show the trailing space:
///
/// ```text
/// "42 "
/// ```
///
/// `number_node` has tag `.number_literal` and main token `number_token`.
/// This fragment is not yet a complete file that can be rendered.
pub fn addNode(
    context: *Self,
    allocator: std.mem.Allocator,
    tag: std.zig.Ast.Node.Tag,
    main_token: std.zig.Ast.TokenIndex,
    data: std.zig.Ast.Node.Data,
) !std.zig.Ast.Node.Index {
    const index: std.zig.Ast.Node.Index = @fromBackingInt(
        @as(u32, @intCast(context.nodes.len)),
    );
    try context.nodes.append(allocator, .{
        .tag = tag,
        .main_token = main_token,
        .data = data,
    });
    return index;
}

/// Append a token and its spelling, returning its index in `tokens`.
///
/// - For fixed syntax, pass `null`: `.keyword_const` supplies `const` and
///   `.comma` supplies `,`.
/// - Identifiers and literals need their complete Zig spelling, including
///   quotes and escapes for string and character literals.
/// - Pass `.eof, ""` when finalizing. Every other token adds one separating space.
///
/// Spelling bytes are copied; this does not validate them or create any nodes.
/// A `null` spelling is valid only for tags whose `lexeme()` is non-null.
///
/// ### Example
///
/// With an allocator and a context whose root is reserved:
///
/// ```zig
/// const const_token = try context.token(allocator, .keyword_const, null);
/// const name_token = try context.token(allocator, .identifier, "answer");
/// // Tokens are syntax only; create the declaration's node separately.
/// ```
///
/// ### Expected output
///
/// Appended source bytes, quoted to show the trailing space:
///
/// ```text
/// "const answer "
/// ```
///
/// No nodes are created; the declaration is still incomplete.
pub fn token(
    context: *Self,
    allocator: std.mem.Allocator,
    tag: std.zig.Token.Tag,
    spelling: ?[]const u8,
) !std.zig.Ast.TokenIndex {
    const index: std.zig.Ast.TokenIndex = @intCast(context.tokens.len);
    try context.tokens.append(allocator, .{
        .tag = tag,
        .start = @intCast(context.source.items.len),
    });
    try context.source.appendSlice(allocator, spelling orelse tag.lexeme().?);
    if (tag != .eof) try context.source.append(allocator, ' ');
    return index;
}

/// Append an identifier token and expression node, returning the node index.
///
/// `spelling` must be a complete Zig identifier such as `u32`, `Status`, or
/// `@"error"`; the method copies it without checking or escaping it.
/// Use `Expression.field_access` for a qualified name such as
/// `schema.Tag`.
///
/// The returned node must be attached by the enclosing construct.
pub fn identifierExpression(
    context: *Self,
    allocator: std.mem.Allocator,
    spelling: []const u8,
) !std.zig.Ast.Node.Index {
    const identifier_token = try context.token(allocator, .identifier, spelling);
    return context.addNode(allocator, .identifier, identifier_token, undefined);
}

/// Append encoded extra-data words and return their first index.
///
/// Copies the slice; the node tag still determines the record layout.
/// The input must not alias `extra_data`, which may reallocate during the copy.
/// No padding or type conversion is added. Allocation errors propagate.
///
/// For an empty buffer, `addExtra(allocator, &.{ 10, 20 })` returns index zero
/// and stores the two words in that order. A node must attach the resulting
/// range or record; appending words alone creates no syntax nodes.
pub fn addExtra(context: *Self, allocator: std.mem.Allocator, words: []const u32) !std.zig.Ast.ExtraIndex {
    const extra_index: std.zig.Ast.ExtraIndex = @fromBackingInt(@intCast(context.extra_data.items.len));
    try context.extra_data.appendSlice(allocator, words);
    return extra_index;
}
