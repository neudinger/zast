//! Build examples and docs; generate test source on the host for the selected target.
const std = @import("std");
const builtin = @import("builtin");
const manifest = @import("build.zig.zon");
const Build = std.Build;
const Module = Build.Module;

comptime {
    // Manual AST layouts require the exact compiler version, not just a minimum.
    const required_version = manifest.minimum_zig_version;
    if (!std.mem.eql(u8, builtin.zig_version_string, required_version)) {
        @compileError("zast requires Zig " ++ required_version ++
            "; run `zvm run " ++ required_version ++ " build test`.");
    }
}

fn module(builder: *Build, source: Build.LazyPath, options: Module.CreateOptions) *Module {
    var configuration = options;
    configuration.root_source_file = source;
    return builder.createModule(configuration);
}

pub fn build(builder: *Build) void {
    const options: Module.CreateOptions = .{
        .root_source_file = builder.path("src/root.zig"),
        .target = builder.standardTargetOptions(.{}),
        .optimize = builder.standardOptimizeOption(.{}),
    };
    const zast = builder.addModule("zast", options);
    // Reflection belongs to the JSON examples, not the public library.
    const reflection_source = builder.path("examples/json_schema/reflection.zig");
    const reflection = module(builder, reflection_source, options);
    var example_options = options;
    example_options.imports = &.{.{ .name = "zast", .module = zast }};
    const flatbuf_source = builder.path("examples/flatbuf_json/main.zig");
    const flatbuf_json = module(builder, flatbuf_source, example_options);
    flatbuf_json.addImport("reflection", reflection);
    const flatbuf = builder.addExecutable(.{
        .name = "zast-flatbuf-json",
        .root_module = flatbuf_json,
    });
    builder.installArtifact(flatbuf);
    // Only the generator executes on the host; tests compile its actual stdout for the target.
    const reading_source = reading_source_blk: {
        var host_options = options;
        host_options.target = builder.graph.host;
        const host_zast = module(builder, options.root_source_file.?, host_options);
        const host_reflection = module(builder, reflection_source, host_options);
        host_options.imports = &.{
            .{ .name = "zast", .module = host_zast },
            .{ .name = "reflection", .module = host_reflection },
        };
        const generator = builder.addExecutable(.{
            .name = "zast-flatbuf-json",
            .root_module = module(builder, flatbuf_source, host_options),
        });
        const generate = builder.addRunArtifact(generator);
        break :reading_source_blk generate.captureStdOut(.{ .basename = "reading.zig" });
    };
    var test_options = options;
    test_options.imports = &.{
        .{ .name = "zast", .module = zast },
        .{ .name = "reflection", .module = reflection },
        .{ .name = "flatbuf_json", .module = flatbuf_json },
        .{ .name = "generated_reading", .module = module(builder, reading_source, options) },
    };
    const tests = builder.addTest(.{
        .root_module = module(builder, builder.path("tests/test_all.zig"), test_options),
    });
    inline for (.{
        .{ "declarations", "examples/declarations.zig" },
        .{ "comments", "examples/comments.zig" },
        .{ "struct", "examples/struct.zig" },
        .{ "enum", "examples/enum.zig" },
        .{ "union", "examples/union.zig" },
        .{ "function", "examples/function.zig" },
        .{ "function-types", "examples/function_types.zig" },
        .{ "blocks", "examples/blocks.zig" },
        .{ "rich-functions", "examples/rich_functions.zig" },
        .{ "calls", "examples/calls.zig" },
        .{ "initializers", "examples/initializers.zig" },
        .{ "type-composition", "examples/type_composition.zig" },
        .{ "compound-types", "examples/compound_types.zig" },
        .{ "json-schema", "examples/json_schema/main.zig" },
    }) |example| {
        const example_module = module(builder, builder.path(example[1]), example_options);
        const is_schema = comptime std.mem.eql(u8, example[0], "json-schema");
        if (is_schema) example_module.addImport("reflection", reflection);
        // Preserve the JSON playground's existing executable path.
        const executable = builder.addExecutable(.{
            .name = if (is_schema) "zast" else "zast-" ++ example[0],
            .root_module = example_module,
        });
        builder.installArtifact(executable);
        const run = builder.addRunArtifact(executable);
        const command = builder.step("run-" ++ example[0], "Run the " ++ example[0] ++ " example");
        command.dependOn(&run.step);
        if (is_schema) builder.step("run", "Run the JSON schema playground").dependOn(&run.step);
    }
    const flatbuf_run = &builder.addRunArtifact(flatbuf).step;
    inline for (.{
        .{ .@"run-flatbuf-json", "Run the small FlatBuffers schema JSON example", flatbuf_run },
        .{ .check, "Compile the test suite without running it", &tests.step },
        .{ .@"test", "Test the generator", &builder.addRunArtifact(tests).step },
    }) |command| builder.step(@tagName(command[0]), command[1]).dependOn(command[2]);
}
