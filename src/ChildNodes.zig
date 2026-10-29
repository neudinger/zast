//! Internal storage for an ordered list of AST child indexes.
//!
//! Up to two indexes fit inline; callers choose a limit of zero, one, or two
//! according to their node layout. Larger lists reserve a contiguous range
//! before recursive emission.
//!
//! Only indexes are retained, so buffer growth cannot invalidate this description.
//! `AstContext` owns all allocated storage. Tokens, node tags, and the final
//! `Node.Data` layout remain caller decisions.
//!
//! This helper is internal and is not exported by `@import("zast")`. Generator
//! implementations import it as `@import("ChildNodes.zig")`.
//!
//! ## Example
//!
//! With that import, `AstContext`, an allocator, and node zero reserved as `.root`
//! in a fresh context:
//!
//! ```zig
//! var children = try ChildNodes.init(allocator, &context, 3, 2);
//! for ([_][]const u8{ "first", "second", "third" }, 0..) |name, index| {
//!     const node = try context.identifierExpression(allocator, name);
//!     children.set(&context, index, node);
//! }
//! const range_index = try children.appendRange(allocator, &context);
//! // Attach range_index to a node whose layout expects a SubRange record.
//! ```
//!
//! ## Expected output
//!
//! No complete source file is emitted. With no earlier extra data, the first
//! three words contain the child node indexes; the final two encode `[0, 3)`:
//!
//! ```text
//! context.extra_data.items = { 1, 2, 3, 0, 3 }
//! range_index = 3
//! ```

const std = @import("std");
const Ast = std.zig.Ast;
const AstContext = @import("AstContext.zig");
const Self = @This();

/// Optional child slots for the small node layouts; unused slots stay empty.
inline_nodes: [2]Ast.Node.OptionalIndex = @splat(.none),
/// Child range in `extra_data`; storage is reserved only when `uses_extra` is true.
/// Empty lists have a valid empty range; nonempty inline lists do not use it.
range: Ast.Node.SubRange,
/// Whether children belong in the reserved range rather than inline slots.
uses_extra: bool,

/// Reserve out-of-line slots before emitting children.
///
/// The limit may be runtime data, as typed and inferred initializers have
/// different inline capacities. It must be at most two. Counts and resulting
/// extra-data offsets must fit `u32`; reserved slots are initially undefined.
/// Allocation errors propagate; discard the enclosing context after failure.
pub fn init(allocator: std.mem.Allocator, context: *AstContext, count: usize, inline_capacity: usize) !Self {
    std.debug.assert(inline_capacity <= 2);
    const start: u32 = @intCast(context.extra_data.items.len);
    const end = start + @as(u32, @intCast(count));
    const uses_extra = count > inline_capacity;
    if (uses_extra) try context.extra_data.resize(allocator, end);
    return .{
        .range = .{ .start = @fromBackingInt(start), .end = @fromBackingInt(end) },
        .uses_extra = uses_extra,
    };
}

/// Store an emitted child at its original list position without allocating.
/// Reacquire the destination by index after any recursive buffer growth.
/// Use the same context passed to `init`, with `index` less than the original
/// count. Set every child slot before attaching or rendering the enclosing node.
pub fn set(self: *Self, context: *AstContext, index: usize, node: Ast.Node.Index) void {
    if (self.uses_extra) {
        context.extra_data.items[@backingInt(self.range.start) + index] = @backingInt(node);
    } else {
        self.inline_nodes[index] = node.toOptional();
    }
}

/// Append a `SubRange` record for layouts whose other slot holds another node.
///
/// Direct-range layouts use `range` instead. Call after all children are stored.
/// Only ranged or empty lists have a valid extra-data range to append.
pub fn appendRange(self: Self, allocator: std.mem.Allocator, context: *AstContext) !Ast.ExtraIndex {
    return context.addExtra(allocator, &.{ @backingInt(self.range.start), @backingInt(self.range.end) });
}
