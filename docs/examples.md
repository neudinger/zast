# Copyable examples

Copyable code for the [README illustrations](../README.md#reading-the-examples).
Each example includes its expected generated Zig source. Sections 14 and 15
show JSON excerpts and use their linked generators instead of the runner below.
See [ownership and formatting](../README.md#ownership-and-formatting) for
allocation, borrowing, and rendering rules.

## Reading the examples

Each **zast** snippet is independent. Put it inside the `generate` function in
the [complete runner](#complete-runner). The runner supplies:

- `const std = @import("std");`
- `const zast = @import("zast");`
- `allocator: std.mem.Allocator`
- `context: *zast.AstContext`, with its root node already reserved.

Descriptions provide values and types; `emit` adds a named declaration to the
file. The runner calls `finish` and `renderAlloc` once after generation.

## Complete runner

[Runnable example](../examples/declarations.zig) · [AST lifecycle tests](../tests/test_ast_context.zig)

This complete program generates the constant from example 1. Replace only the
body of `generate` with another **zast** snippet to try it.

```zig
const std = @import("std");
const zast = @import("zast");

fn generate(allocator: std.mem.Allocator, context: *zast.AstContext) !void {
    const declaration: zast.Declaration = .{
        .type_expression = .{ .identifier = "u32" },
        .value = .{ .integer_literal = "42" },
    };
    try declaration.emit(allocator, context, "answer", .public);
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var context: zast.AstContext = .{};
    defer context.deinit(allocator);
    _ = try context.addNode(allocator, .root, 0, undefined);

    try generate(allocator, &context);

    var tree = try context.finish(allocator);
    const source = tree.source;
    defer allocator.free(source);
    defer tree.deinit(allocator);
    const rendered = try tree.renderAlloc(allocator);
    defer allocator.free(rendered);
    try std.Io.File.stdout().writeStreamingAll(init.io, rendered);
}
```

Save it as `/tmp/zast-playground.zig`, then run from the `zast` directory:

```sh
zig run --dep zast -Mroot=/tmp/zast-playground.zig -Mzast=src/root.zig
```

`undefined` above is only the reserved root's temporary data. `finish` fills
that node after all declarations have been emitted. The finished AST borrows
its source, so the runner releases the source separately from the tree.

## 1. A constant

[View illustration](../README.md#1-a-constant) · [Complete runner](#complete-runner) ·
[Runnable example](../examples/declarations.zig) · [Related tests](../tests/test_declaration.zig)

**zast**

```zig
const declaration: zast.Declaration = .{
    .type_expression = .{ .identifier = "u32" },
    .value = .{ .integer_literal = "42" },
};
try declaration.emit(allocator, context, "answer", .public);
```

**Rendered Zig**

```zig
pub const answer: u32 = 42;
```

The name and visibility belong to the declaration. Its type and value are
expressions. Set `.kind = .variable` to emit `var` instead of `const`.

## 2. Compose types

[View illustration](../README.md#2-compose-types) · [Complete runner](#complete-runner) ·
[Runnable example](../examples/compound_types.zig) · [Related tests](../tests/test_declaration.zig)

**zast**

```zig
const byte_type: zast.Expression = .{ .identifier = "u8" };
const text_type: zast.Expression = .{ .slice_type = .{
    .child_type = &byte_type,
    .is_const = true,
} };
const optional_text: zast.Declaration = .{
    .value = .{ .optional_type = &text_type },
};
try optional_text.emit(allocator, context, "OptionalText", .public);
```

**Rendered Zig**

```zig
pub const OptionalText = ?[]const u8;
```

The child expressions remain alive until emission finishes. Arrays, pointers,
sentinels, qualifiers, and error unions compose in the same way; see
[compound_types.zig](../examples/compound_types.zig).

## 3. An enum

[View illustration](../README.md#3-an-enum) · [Complete runner](#complete-runner) ·
[Runnable example](../examples/enum.zig) · [Related tests](../tests/test_enum_declaration.zig)

### Inferred enum

This is the enum shown in the illustration.

**zast**

```zig
const status: zast.EnumDeclaration = .{
    .backing_type = null,
    .non_exhaustive = false,
    .fields = &.{
        .{ .name = "unknown" },
        .{ .name = "ok" },
    },
};
try status.emit(
    allocator, context, "Status", .public,
);
```

**Rendered Zig**

```zig
pub const Status = enum {
    unknown,
    ok,
};
```

### Explicit backing type and catch-all field

This variant adds numeric values and a non-exhaustive field.

**zast**

```zig
const declaration: zast.EnumDeclaration = .{
    .backing_type = "u8",
    .non_exhaustive = true,
    .fields = &.{
        .{ .name = "unknown", .value = .{ .integer_literal = "0" } },
        .{ .name = "ok", .value = .{ .integer_literal = "1" } },
        .{ .name = "warning", .value = .{ .integer_literal = "2" } },
    },
};
try declaration.emit(allocator, context, "Status", .public);
```

**Rendered Zig**

```zig
pub const Status = enum(u8) {
    unknown = 0,
    ok = 1,
    warning = 2,
    _,
};
```

`non_exhaustive` adds `_`. For an inferred `enum { ... }`, use a null backing
type, set `non_exhaustive` to false, and omit explicit field values.

## 4. A tagged union

[View illustration](../README.md#4-a-tagged-union) · [Complete runner](#complete-runner) ·
[Runnable example](../examples/union.zig) · [Related tests](../tests/test_union_declaration.zig)

**zast**

```zig
const declaration: zast.UnionDeclaration = .{
    .tag_type = .inferred,
    .fields = &.{
        .{ .name = "none" },
        .{ .name = "number", .type_expression = .{ .identifier = "u32" } },
        .{ .name = "boolean", .type_expression = .{ .identifier = "bool" } },
    },
};
try declaration.emit(allocator, context, "Payload", .public);
```

**Rendered Zig**

```zig
pub const Payload = union(enum) {
    none,
    number: u32,
    boolean: bool,
};
```

Enum and union descriptions share `Field`. For this tagged union, a field
without a type has a `void` payload.

## 5. A function

[View illustration](../README.md#5-a-function) · [Complete runner](#complete-runner) ·
[Runnable example](../examples/function.zig) · [Related tests](../tests/test_function_declaration.zig)

**zast**

```zig
const declaration: zast.FunctionDeclaration = .{
    .parameters = &.{.{
        .name = "value",
        .type_expression = .{ .identifier = "u32" },
    }},
    .return_type = .{ .identifier = "u32" },
    .body = .{ .statements = &.{
        .{ .return_value = .{ .identifier = "value" } },
    } },
};
try declaration.emit(allocator, context, "identity", .public);
```

**Rendered Zig**

```zig
pub fn identity(value: u32) u32 {
    return value;
}
```

Parameters describe the signature. `Block.Statement` describes the function
body: returns, declarations, assignments, calls, and nested blocks.

## 6. Reuse a function inside a struct

[View illustration](../README.md#6-reuse-a-function-inside-a-struct) · [Complete runner](#complete-runner) ·
[Runnable example](../examples/struct.zig) · [Related tests](../tests/test_struct_declaration.zig)

**zast**

```zig
const self_type: zast.Expression = .{ .builtin_call = .{ .name = "@This" } };
const receiver: zast.Expression = .{ .identifier = "self" };
const getter: zast.FunctionDeclaration = .{
    .parameters = &.{.{
        .name = "self",
        .type_expression = .{ .pointer_type = .{
            .child_type = &self_type,
            .is_const = true,
        } },
    }},
    .return_type = .{ .identifier = "u32" },
    .body = .{ .statements = &.{.{ .return_value = .{ .field_access = .{
        .base = &receiver,
        .name = "value",
    } } }} },
};
const declaration: zast.StructDeclaration = .{
    .members = &.{
        .{ .field = .{
            .name = "value",
            .type_expression = .{ .identifier = "u32" },
            .value = .{ .integer_literal = "42" },
        } },
        .{ .function = .{
            .name = "get",
            .declaration = &getter,
            .visibility = .public,
        } },
    },
};
try declaration.emit(allocator, context, "Reading", .public);
```

**Rendered Zig**

```zig
pub const Reading = struct {
    value: u32 = 42,
    pub fn get(self: *const @This()) u32 {
        return self.value;
    }
};
```

The same `FunctionDeclaration` describes a top-level function or a struct
member. The explicit `self` parameter makes this function usable as a method.
The struct emits the member; do not also emit `getter` at the file root.

## 7. Embed an anonymous type

[View illustration](../README.md#7-embed-an-anonymous-type) · [Complete runner](#complete-runner) ·
[Runnable example](../examples/type_composition.zig) · [Related tests](../tests/test_type_composition.zig)

**zast**

```zig
const status: zast.EnumDeclaration = .{
    .backing_type = null,
    .non_exhaustive = false,
    .fields = &.{ .{ .name = "unknown" }, .{ .name = "ok" } },
};
const declaration: zast.StructDeclaration = .{
    .members = &.{.{ .field = .{
        .name = "status",
        .type_expression = zast.Expression.fromType(&status),
        .value = .{ .enum_literal = "unknown" },
    } }},
};
try declaration.emit(allocator, context, "Response", .public);
```

**Rendered Zig**

```zig
pub const Response = struct {
    status: enum {
        unknown,
        ok,
    } = .unknown,
};
```

`Expression.fromType` borrows the descriptor and delegates to its `emitType`
method. The enclosing field supplies the name and default value. To refer to
an already declared type, use `.identifier = "Status"` instead; embedding the
same description again creates another type expression.

## 8. A builtin call

[View illustration](../README.md#8-a-builtin-call) · [Complete runner](#complete-runner) ·
[Runnable example](../examples/calls.zig) · [Related tests](../tests/test_call_expression.zig)

**zast**

```zig
const declaration: zast.Declaration = .{
    .value = .{ .builtin_call = .{
        .name = "@sizeOf",
        .arguments = &.{.{ .identifier = "u32" }},
    } },
};
try declaration.emit(allocator, context, "scalar_size", .public);
```

**Rendered Zig**

```zig
pub const scalar_size = @sizeOf(u32);
```

This emits a call for the generated program. Zig evaluates it when that program
is compiled; `scalar_size` is 4. Ordinary calls use `.call` with a callee
expression; [calls.zig](../examples/calls.zig) also composes imports and member access.

## 9. A value initializer

[View illustration](../README.md#9-a-value-initializer) · [Complete runner](#complete-runner) ·
[Runnable example](../examples/initializers.zig) · [Related tests](../tests/test_initializer_expression.zig)

**zast**

```zig
const declaration: zast.Declaration = .{
    .value = .{ .struct_init = .{
        .fields = &.{
            .{ .name = "required", .value = .{ .identifier = "true" } },
            .{ .name = "status", .value = .{ .enum_literal = "unknown" } },
        },
        .trailing_comma = true,
    } },
};
try declaration.emit(allocator, context, "options", .public);
```

**Rendered Zig**

```zig
pub const options = .{
    .required = true,
    .status = .unknown,
};
```

`struct_init` describes a value. Set its `type_expression` to generate a typed
initializer such as `Options{ ... }`. See [initializers.zig](../examples/initializers.zig)
for empty, nested, and positional initializers.

## 10. Comments and documentation

[View illustration](../README.md#10-comments-and-documentation) · [Complete runner](#complete-runner) ·
[Runnable example](../examples/comments.zig) · [AST lifecycle tests](../tests/test_ast_context.zig)

**zast**

```zig
try context.source.appendSlice(
    allocator,
    "// Generated by zast.\n",
);
_ = try context.token(
    allocator,
    .container_doc_comment,
    "//! Documented declarations.",
);
try context.source.append(allocator, '\n');
_ = try context.token(
    allocator,
    .doc_comment,
    "/// The default answer.",
);
try context.source.append(allocator, '\n');
const answer: zast.Declaration = .{
    .type_expression = .{ .identifier = "u32" },
    .value = .{ .integer_literal = "42" },
};
try answer.emit(allocator, context, "answer", .public);
```

**Rendered Zig**

```zig
// Generated by zast.
//! Documented declarations.
/// The default answer.
pub const answer: u32 = 42;
```

An ordinary comment uses source bytes; file and declaration documentation also
use tokens. Every comment ends with a newline.

## 11. A function pointer type

[View illustration](../README.md#11-a-function-pointer-type) · [Complete runner](#complete-runner) ·
[Runnable example](../examples/function_types.zig) · [Related tests](../tests/test_function_declaration.zig)

**zast**

```zig
const scalar: zast.Expression = .{ .identifier = "u32" };
const signature: zast.FunctionDeclaration = .{
    .parameters = &.{.{ .type_expression = scalar }},
    .return_type = scalar,
};
const prototype = zast.Expression.fromType(&signature);
const callback: zast.Declaration = .{
    .value = .{ .pointer_type = .{
        .child_type = &prototype,
        .is_const = true,
    } },
};
try callback.emit(allocator, context, "Callback", .public);
```

**Rendered Zig**

```zig
pub const Callback = *const fn (u32) u32;
```

Function type parameters can omit names. `Expression.fromType` emits the
signature without a body; wrapping it in a const pointer creates a callable
callback type.

## 12. Nested blocks

[View illustration](../README.md#12-nested-blocks) · [Complete runner](#complete-runner) ·
[Runnable example](../examples/blocks.zig) · [Related tests](../tests/test_function_declaration.zig)

**zast**

```zig
const inner: zast.Block = .{ .statements = &.{
    .{ .declaration = .{
        .name = "value",
        .declaration = .{
            .value = .{ .integer_literal = "42" },
        },
    } },
    .{ .assignment = .{
        .target = .{ .identifier = "_" },
        .value = .{ .identifier = "value" },
    } },
} };
const function: zast.FunctionDeclaration = .{
    .body = .{ .statements = &.{
        .{ .block = &inner },
        .{ .return_value = null },
    } },
};
try function.emit(allocator, context, "noop", .public);
```

**Rendered Zig**

```zig
pub fn noop() void {
    {
        const value = 42;
        _ = value;
    }
    return;
}
```

`Block.Statement.block` nests a borrowed block. Assignment to `_` discards a
value, and a null `return_value` emits a bare `return;`. The default function
return type is `void`.

## 13. Comptime parameters and error propagation

[View illustration](../README.md#13-comptime-parameters-and-error-propagation) · [Complete runner](#complete-runner) ·
[Runnable example](../examples/rich_functions.zig) · [Related tests](../tests/test_function_declaration.zig)

**zast**

```zig
const value_type: zast.Expression = .{
    .identifier = "Value",
};
const errors: zast.Expression = .{
    .identifier = "anyerror",
};
const result_type: zast.Expression = .{
    .error_union_type = .{
        .error_set = &errors,
        .payload_type = &value_type,
    },
};
const value: zast.Expression = .{ .identifier = "value" };
const function: zast.FunctionDeclaration = .{
    .parameters = &.{
        .{
            .name = "Value",
            .is_comptime = true,
            .type_expression = .{ .identifier = "type" },
        },
        .{ .name = "value", .type_expression = result_type },
    },
    .return_type = result_type,
    .body = .{ .statements = &.{
        .{ .declaration = .{
            .name = "result",
            .declaration = .{
                .kind = .variable,
                .type_expression = value_type,
                .value = .{ .identifier = "undefined" },
            },
        } },
        .{ .assignment = .{
            .target = .{ .identifier = "result" },
            .value = .{ .@"try" = &value },
        } },
        .{ .return_value = .{ .identifier = "result" } },
    } },
};
try function.emit(allocator, context, "forward", .public);
```

**Rendered Zig**

```zig
pub fn forward(comptime Value: type, value: anyerror!Value) anyerror!Value {
    var result: Value = undefined;
    result = try value;
    return result;
}
```

A `comptime` type parameter determines the error-union parameter and return
types. The body combines a local `var`, assignment, and `try`; errors return
before the uninitialized local is read. The runnable example emits this
standalone function.

## 14. JSON schema playground

[View illustration](../README.md#14-json-schema-playground) ·
[Runnable example](../examples/json_schema/main.zig) · [Struct tests](../tests/test_struct_declaration.zig) · [Enum tests](../tests/test_enum_declaration.zig)

**JSON object excerpt**

```json
{
  "name": "Reading",
  "fields": [{
    "name": "answer",
    "type": {"base_type": "UInt"},
    "default_integer": 65
  }]
}
```

**Rendered Zig excerpt**

```zig
pub const Reading = struct {
    answer: u32 = 65,
    pub fn answerFunc() u32 {
        return 84;
    }
};
```

This object comes from the embedded `objects` array in the [JSON playground](../examples/json_schema/main.zig). It is an input excerpt, not a complete schema document or a **zast** runner snippet. The full embedded JSON also includes an `enums` array.

Run the existing example from the `zast` directory:

```sh
zig build run-json-schema > /tmp/json-schema.generated.zig
```

`UInt` maps to `u32`; `default_integer` supplies `65`. The generator adds `answerFunc`, which returns `84`, independently of the JSON. This lesson demonstrates schema-driven declaration generation.

Only the matching `Reading` declaration is shown. The full playground prints additional demonstrations, including two declarations named `Status`, so its complete output is not one compilable Zig module.

## 15. FlatBuffers JSON

[View illustration](../README.md#15-flatbuffers-json) ·
[Runnable example](../examples/flatbuf_json/main.zig) · [Related tests](../tests/test_flatbuf_json.zig)

**JSON enum excerpt**

```json
{
  "name": "Status",
  "values": [
    {"name": "Unknown", "value": 0},
    {"name": "Ok", "value": 1},
    {"name": "Warning", "value": 2}
  ],
  "underlying_type": {"base_type": "UByte"}
}
```

**Rendered Zig excerpt**

```zig
pub const Status = enum(u8) {
    Unknown = 0,
    Ok = 1,
    Warning = 2,
    _,
};
```

This excerpt selects the `Status` enum from the compiler-generated [reading.json](../examples/flatbuf_json/reading.json); extra metadata is omitted from the illustration. The complete fixture comes from the local [reading.fbs](../examples/flatbuf_json/reading.fbs), containing one enum and one `Reading` table with a `uint` field. The example parses it using the existing [reflection.zig](../examples/json_schema/reflection.zig) types.

Run the [example generator](../examples/flatbuf_json/main.zig) from the `zast` directory:

```sh
zig build run-flatbuf-json > /tmp/reading.generated.zig
zig build test
```

The generator maps `UByte` enums to `enum(u8)` and `UInt` fields to `u32`, preserves the names and defaults, and escapes Zig identifiers. It uses `EnumDeclaration` and `StructDeclaration`, then renders their shared AST. The full output is recorded in [expected.zig](../examples/flatbuf_json/expected.zig); [the tests](../tests/test_flatbuf_json.zig) compare rendering and compile the actual generated output.

See the [example guide](../examples/flatbuf_json/README.md) for the complete input, output, and component mapping. This is a small illustration of where `zast` can be used, not a reference FlatBuffers generator. The generated structs have ordinary Zig layouts.
