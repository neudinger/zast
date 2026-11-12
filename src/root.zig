//! Public components for constructing Zig source tokens and AST nodes.

/// Owned AST buffers with explicit finalization and separate source cleanup.
pub const AstContext = @import("AstContext.zig");
/// Borrowed value and type expressions with automatic precedence grouping.
pub const Expression = @import("Expression.zig").Expression;
/// Borrowed field name, optional type, and optional default or enum value.
pub const Field = @import("Field.zig");
/// Named const/var bindings, visibility, and shared type declaration emission.
pub const Declaration = @import("Declaration.zig");
/// Shared member emission and container node layouts, separate from statement blocks.
pub const Container = @import("Container.zig");
/// Enum descriptions with anonymous type and named declaration emission.
pub const EnumDeclaration = @import("EnumDeclaration.zig");
/// Tagged and untagged union descriptions with borrowed fields.
pub const UnionDeclaration = @import("UnionDeclaration.zig");
