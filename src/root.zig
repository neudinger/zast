//! Public components for constructing Zig source tokens and AST nodes.
//!
//! ## Getting started
//!
//! Import the library with `const zast = @import("zast");`.
//! Start with the complete, runnable example in `AstContext`, which covers
//! declaration emission, finalization, formatted output, and cleanup.
//!
//! 1. Create an `AstContext` and reserve node zero as `.root`.
//! 2. Describe the desired types, values, fields, and declarations.
//! 3. Emit those descriptions into the shared context, passing its allocator.
//! 4. Call `AstContext.finish`, then render the returned tree with `renderAlloc`.
//!
//! Use exactly the Zig version required by `build.zig.zon` and checked by
//! `build.zig`; the emitters construct that compiler's AST layouts directly.
//!
//! ## Construct descriptions
//!
//! Descriptors can be ordinary values, for example
//! `const status: zast.EnumDeclaration = .{ .backing_type = null };`.
//! `init` is an optional convenience for arena-allocated descriptors. Passing
//! literal `null` for its list argument returns a mutable descriptor whose list
//! can be assigned later; passing a slice or array pointer returns a const
//! descriptor. Neither form copies the list or freezes its borrowed elements.
//!
//! Emit a complete named declaration with `emit`. Methods named `emitType` or
//! `emitNode`, and the emitters on `Expression`, `Field`, `Block`, and `Container`,
//! return child nodes without root registration. Their caller must attach them
//! to an enclosing node in the same context and emit surrounding tokens in order.
//!
//! ## Choose a component
//!
//! | Component | Use it to describe |
//! | --- | --- |
//! | `Expression` | Values, types, calls, and initializers |
//! | `Field` | A container field and its optional value |
//! | `Declaration` | A named `const` or `var` binding |
//! | `EnumDeclaration` | An inferred or explicitly backed enum |
//! | `UnionDeclaration` | A tagged or untagged union |
//! | `StructDeclaration` | A struct with fields, methods, and declarations |
//! | `FunctionDeclaration` | A function or function type |
//! | `Block` | Statements in a function body or nested scope |
//! | `Container` | A type's member body and AST layout after its header |
//! | `AstContext` | Unmanaged token, source, node, and extra-data storage for one file |
//!
//! ## Ownership and scope
//!
//! Descriptions borrow their inputs until emission finishes. Components receive
//! allocators explicitly; `AstContext` owns the generated buffers. Follow its
//! cleanup example: the finished tree borrows its separately owned source text.
//! Keep borrowed inputs outside buffers that emission can grow. Reallocation
//! invalidates pointers and slices into context buffers; retain node/token indexes
//! and reacquire buffer views after recursive emission.
//!
//! ## Validation and errors
//!
//! | Component | Checks performed before its own syntax is written |
//! | --- | --- |
//! | `EnumDeclaration` | `MissingBackingType` for explicit values or a catch-all without a backing type |
//! | `UnionDeclaration` | `MissingFieldType` for an untagged union field without a payload type |
//! | `StructDeclaration` | `MissingFieldType`, `NonContiguousFields`, and named methods' `MissingParameterName` |
//! | `FunctionDeclaration` | `MissingParameterName` for named definitions; unnamed parameters work in `emitType` |
//!
//! Constructors allocate without validating. Emitters recheck current borrowed
//! inputs, but do not validate the entire child graph before writing a parent.
//! Allocation and child validation errors can therefore leave partial output;
//! discard and clean up that context. `Declaration`, `Field`, and `Container`
//! supply syntax without additional semantic validation.
//!
//! Input formats such as JSON belong to the calling application. These
//! components accept Zig descriptions independently of how they were obtained.
//! Rendering formats syntax; compile the generated Zig to check its semantics.

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
