//! Entry point for the complete generator test suite.
//!
//! ## Run the suite
//!
//! Run `zig build test` from the `zast` directory. The build supplies the `zast`
//! library, JSON example modules, and the actual generated Reading declarations.
//!
//! ## Coverage map
//!
//! | Test module | Main responsibility |
//! | --- | --- |
//! | `test_ast_context.zig` | Finalization, transferred buffers, and cleanup |
//! | `test_container.zig` | Shared enum/union member storage |
//! | `test_declaration.zig` | Type aliases, `const`/`var`, and pointer bindings |
//! | `test_enum_declaration.zig` | Borrowed fields, backing types, and schema values |
//! | `test_expression.zig` | Optional, pointer, array, and error types |
//! | `test_call_expression.zig` | Ordinary and builtin calls |
//! | `test_initializer_expression.zig` | Enum literals and value initializers |
//! | `test_type_composition.zig` | Nested and borrowed type descriptions |
//! | `test_function_declaration.zig` | Parameters, bodies, methods, and error propagation |
//! | `test_struct_declaration.zig` | Layouts, members, and struct validation |
//! | `test_union_declaration.zig` | Borrowed fields and the four union headers |
//! | `test_flatbuf_json.zig` | Small JSON example and compiled native output |
//!
//! ## Reading the assertions
//!
//! `helpers.zig` centralizes rendering and independently parsed expectations.
//! Individual tests also inspect AST links, validation errors, borrowed storage,
//! or allocation failures where relevant. Parsing and formatting do not establish
//! semantic validity; generated code must be compiled separately for that check.
//!
//! The string-named tests below the imported modules' overviews are executable
//! examples and regression checks, not API doctests. `zig build docs` currently
//! documents `src/root.zig`; it does not publish this directory as API pages.

test {
    _ = @import("test_ast_context.zig");
    _ = @import("test_container.zig");
    _ = @import("test_declaration.zig");
    _ = @import("test_enum_declaration.zig");
    _ = @import("test_expression.zig");
    _ = @import("test_call_expression.zig");
    _ = @import("test_initializer_expression.zig");
    _ = @import("test_type_composition.zig");
    _ = @import("test_function_declaration.zig");
    _ = @import("test_struct_declaration.zig");
    _ = @import("test_union_declaration.zig");
    _ = @import("test_flatbuf_json.zig");
}
