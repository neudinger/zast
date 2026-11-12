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
    var example_options = options;
    example_options.imports = &.{.{ .name = "zast", .module = zast }};
    var test_options = options;
    test_options.imports = &.{.{ .name = "zast", .module = zast }};
    const test_module = module(builder, builder.path("tests/test_all.zig"), test_options);
    const tests = builder.addTest(.{ .root_module = test_module });
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
    }) |example| {
        const example_module = module(builder, builder.path(example[1]), example_options);
        const executable = builder.addExecutable(.{
            .name = "zast-" ++ example[0],
            .root_module = example_module,
        });
        builder.installArtifact(executable);
        const run = builder.addRunArtifact(executable);
        const command = builder.step("run-" ++ example[0], "Run the " ++ example[0] ++ " example");
        command.dependOn(&run.step);
    }
    inline for (.{
        .{ .check, "Compile the test suite without running it", &tests.step },
        .{ .@"test", "Test the generator", &builder.addRunArtifact(tests).step },
    }) |command| builder.step(@tagName(command[0]), command[1]).dependOn(command[2]);
}
