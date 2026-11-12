# Small FlatBuffers schema JSON → Zig example

This example demonstrates where `zast` can be used: translate a small
FlatBuffers schema JSON into a Zig enum and struct. The input is real
compiler-generated metadata, parsed using the existing `reflection.zig` types.
The generator is a small usage example, not a reference FlatBuffers implementation.

Run from the `zast` directory:

```sh
zig build run-flatbuf-json
zig build run-flatbuf-json > /tmp/reading.generated.zig
zig build test
```

Only Zig and this project are required to run the checked-in fixture. Edit
the JSON, then rerun the example.

## Files

- [reading.fbs](reading.fbs): standalone source with one enum and one table.
- [reading.json](reading.json): schema JSON generated from that source with the
  FlatBuffers compiler 25.12.19; default-valued metadata is omitted.
- [reflection.zig](../json_schema/reflection.zig): the shared reflection types.
  The parsed value owns their strings, slices, and child pointers.
- [main.zig](main.zig): parse the JSON, emit declarations, and render the AST.
- [expected.zig](expected.zig): complete expected output, shown below.
- [Tests](../../tests/test_flatbuf_json.zig): rendering, compiled output,
  escaped names, unsupported scalar mappings, and allocation cleanup.

## Component mapping

| Input | zast component | Generated Zig |
| --- | --- | --- |
| `Status`, with `UByte` backing | `zast.EnumDeclaration` and `zast.Field` | `enum(u8)` with explicit values and `_` |
| `Reading`, with a `UInt` field | `zast.StructDeclaration` and `zast.Field` | `struct` with a `u32` field |
| `default_integer: 65` | `zast.Expression.integer_literal` | `= 65` |

The generated file is:

```zig
pub const Status = enum(u8) {
    Unknown = 0,
    Ok = 1,
    Warning = 2,
    _,
};
pub const Reading = struct {
    answer: u32 = 65,
};
```

## Follow the code

`toAst` creates one `zast.AstContext`, emits the enum and struct into it, and
finishes the tree. `main` renders the tree and writes the result to stdout.
The names are escaped with `std.zig.fmtId`; fields keep their JSON order.
Root, file, and layout metadata remain in the JSON but are unused by this small
mapping. The FlatBuffers compiler is needed only to regenerate the fixture.

Temporary descriptions live in an arena until emission finishes. The returned
AST and its source use the caller's allocator and are released separately.
The example supports only `UByte` enum backing and `UInt` object fields; the
other combination reports an error. These declarations use ordinary Zig
layouts and do not implement a binary format or serialization.
