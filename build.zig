const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const use_llvm = b.option(bool, "llvm", "use LLVM when building (default: true)");

    const lib = b.addStaticLibrary(.{
        .name = "argparse",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .use_llvm = use_llvm,
    });
    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .use_llvm = use_llvm,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    const example = b.addExecutable(.{
        .name = "argparse-example",
        .root_source_file = b.path("src/example.zig"),
        .target = target,
        .optimize = optimize,
        .use_llvm = use_llvm,
    });
    b.installArtifact(example);

    example.root_module.addImport("argparse", &lib.root_module);

    const run_example = b.addRunArtifact(example);
    run_example.addArgs(b.args orelse &.{});

    const run_step = b.step("run", "Run the example application");
    run_step.dependOn(&run_example.step);
}
