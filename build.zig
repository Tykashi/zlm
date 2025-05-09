const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const zcont = b.dependency("zcont", .{
        .target = target,
        .optimize = optimize,
    });

    const zchan = b.dependency("zchan", .{
        .target = target,
        .optimize = optimize,
    });

    const zlog = b.dependency("zlog", .{
        .target = target,
        .optimize = optimize,
    });

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("./src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib_mod.addImport("zlog", zlog.module("zlog"));
    lib_mod.addImport("zcont", zcont.module("zcont"));
    lib_mod.addImport("zchan", zchan.module("zchan"));

    const build_zig_zon = b.createModule(.{
        .root_source_file = b.path("build.zig.zon"),
        .target = target,
        .optimize = optimize,
    });

    lib_mod.addImport("build", build_zig_zon);
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zlm",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    b.modules.put("zlm", lib_mod) catch unreachable;
}
