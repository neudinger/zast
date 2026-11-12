//! Public components for constructing Zig source tokens and AST nodes.

/// Owned AST buffers with explicit finalization and separate source cleanup.
pub const AstContext = @import("AstContext.zig");
/// Borrowed value and type expressions with automatic precedence grouping.
pub const Expression = @import("Expression.zig").Expression;
/// Borrowed field name, optional type, and optional default or enum value.
pub const Field = @import("Field.zig");
/// Named const/var bindings, visibility, and shared type declaration emission.
pub const Declaration = @import("Declaration.zig");
/// Statement lists for function bodies and nested scopes; exposes `Block.Statement`.
pub const Block = @import("Block.zig");
/// Shared member emission and container node layouts, separate from statement blocks.
pub const Container = @import("Container.zig");
/// Enum descriptions with anonymous type and named declaration emission.
pub const EnumDeclaration = @import("EnumDeclaration.zig");
/// Tagged and untagged union descriptions with borrowed fields.
pub const UnionDeclaration = @import("UnionDeclaration.zig");
/// Function descriptions with prototype, container member, and root emission.
pub const FunctionDeclaration = @import("FunctionDeclaration.zig");
/// Struct descriptions composing fields, functions, and named bindings.
pub const StructDeclaration = @import("StructDeclaration.zig");
