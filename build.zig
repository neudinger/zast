const std = @import("std");

comptime {
    // Manual AST layouts require the exact compiler version, not just a minimum.
    const required_version = @import("build.zig.zon").minimum_zig_version;
    if (!std.mem.eql(u8, @import("builtin").zig_version_string, required_version)) {
        @compileError("zast requires Zig " ++ required_version ++
            "; run `zvm run " ++ required_version ++ " build test`.");
    }
}

pub fn build(builder: *std.Build) void {
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});
    const zast = builder.addModule("zast", .{
        .root_source_file = builder.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const documentation = builder.addLibrary(.{
        .name = "zast",
        .root_module = zast,
    });
    const install_documentation = builder.addInstallDirectory(.{
        .source_dir = documentation.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    builder.step("docs", "Generate API documentation").dependOn(&install_documentation.step);

    // Reflection metadata belongs to the JSON examples, not the generator library.
    const reflection = builder.createModule(.{
        .root_source_file = builder.path("examples/json_schema/reflection.zig"),
        .target = target,
        .optimize = optimize,
    });
    const flatbuf_json = builder.createModule(.{
        .root_source_file = builder.path("examples/flatbuf_json/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zast", .module = zast },
            .{ .name = "reflection", .module = reflection },
        },
    });
    const flatbuf_executable = builder.addExecutable(.{
        .name = "zast-flatbuf-json",
        .root_module = flatbuf_json,
    });
    builder.installArtifact(flatbuf_executable);
    const run_flatbuf = builder.addRunArtifact(flatbuf_executable);
    builder.step("run-flatbuf-json", "Run the small FlatBuffers schema JSON example").dependOn(&run_flatbuf.step);

    const examples = .{
        .{ "declarations", "examples/declarations.zig", "zast-declarations" },
        .{ "comments", "examples/comments.zig", "zast-comments" },
        .{ "struct", "examples/struct.zig", "zast-struct" },
        .{ "enum", "examples/enum.zig", "zast-enum" },
        .{ "union", "examples/union.zig", "zast-union" },
        .{ "function", "examples/function.zig", "zast-function" },
        .{ "function-types", "examples/function_types.zig", "zast-function-types" },
        .{ "blocks", "examples/blocks.zig", "zast-blocks" },
        .{ "rich-functions", "examples/rich_functions.zig", "zast-rich-functions" },
        .{ "calls", "examples/calls.zig", "zast-calls" },
        .{ "initializers", "examples/initializers.zig", "zast-initializers" },
        .{ "type-composition", "examples/type_composition.zig", "zast-type-composition" },
        .{ "compound-types", "examples/compound_types.zig", "zast-compound-types" },
        .{ "json-schema", "examples/json_schema/main.zig", "zast" },
    };
    inline for (examples) |example| {
        const executable = builder.addExecutable(.{
            .name = example[2],
            .root_module = builder.createModule(.{
                .root_source_file = builder.path(example[1]),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "zast", .module = zast }},
            }),
        });
        builder.installArtifact(executable);
        const run = builder.addRunArtifact(executable);
        builder.step("run-" ++ example[0], "Run the " ++ example[0] ++ " example").dependOn(&run.step);
        if (comptime std.mem.eql(u8, example[0], "json-schema")) {
            executable.root_module.addImport("reflection", reflection);
            // Preserve the existing run command and the VS Code executable path.
            builder.step("run", "Run the JSON schema playground").dependOn(&run.step);
        }
    }

    // Compile the actual generated output, not just the checked-in expectation.
    const generate_reading = builder.addRunArtifact(flatbuf_executable);
    const generated_reading = builder.createModule(.{
        .root_source_file = generate_reading.captureStdOut(.{ .basename = "reading.zig" }),
        .target = target,
        .optimize = optimize,
    });
    const test_module = builder.createModule(.{
        .root_source_file = builder.path("tests/test_all.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zast", .module = zast },
            .{ .name = "reflection", .module = reflection },
            .{ .name = "flatbuf_json", .module = flatbuf_json },
            .{ .name = "generated_reading", .module = generated_reading },
        },
    });
    const tests = builder.addRunArtifact(builder.addTest(.{ .root_module = test_module }));
    builder.step("test", "Test the generator").dependOn(&tests.step);
}
