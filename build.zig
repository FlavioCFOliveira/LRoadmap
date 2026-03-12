const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create module for the executable
    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Executable
    const exe = b.addExecutable(.{
        .name = "rmp",
        .root_module = exe_module,
        .version = .{
            .major = 1,
            .minor = 0,
            .patch = 0,
        },
    });

    // Link with SQLite (system library)
    exe.linkLibC();
    exe.linkSystemLibrary("sqlite3");

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const unit_tests = b.addTest(.{
        .root_module = test_module,
    });

    unit_tests.linkLibC();
    unit_tests.linkSystemLibrary("sqlite3");

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Clean step
    const clean_step = b.step("clean", "Clean build artifacts");
    const clean_cmd = b.addSystemCommand(&.{"rm", "-rf", "zig-out", ".zig-cache"});
    clean_step.dependOn(&clean_cmd.step);
}
