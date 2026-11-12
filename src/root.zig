//! Public components for constructing Zig source tokens and AST nodes.

/// Owned AST buffers with explicit finalization and separate source cleanup.
pub const AstContext = @import("AstContext.zig");
/// Borrowed value and type expressions with automatic precedence grouping.
pub const Expression = @import("Expression.zig").Expression;
/// Named const/var bindings, visibility, and shared type declaration emission.
pub const Declaration = @import("Declaration.zig");
