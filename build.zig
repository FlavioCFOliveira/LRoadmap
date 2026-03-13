const std = @import("std");

// Target architectures supported for cross-compilation
const TargetArch = enum {
    native,
    x86_64_linux,
    aarch64_linux,
    aarch64_macos,
    x86_64_windows,

    fn getTarget(self: TargetArch) std.Target.Query {
        return switch (self) {
            .native => .{},
            .x86_64_linux => .{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
            },
            .aarch64_linux => .{
                .cpu_arch = .aarch64,
                .os_tag = .linux,
            },
            .aarch64_macos => .{
                .cpu_arch = .aarch64,
                .os_tag = .macos,
            },
            .x86_64_windows => .{
                .cpu_arch = .x86_64,
                .os_tag = .windows,
            },
        };
    }

    fn getInstallPath(self: TargetArch, b: *std.Build) []const u8 {
        const arch_name = switch (self) {
            .native => getNativeArchName(b),
            .x86_64_linux => "x86_64-linux",
            .aarch64_linux => "aarch64-linux",
            .aarch64_macos => "aarch64-macos",
            .x86_64_windows => "x86_64-windows",
        };
        // Note: The build system automatically prepends 'zig-out'
        // So we only need to provide the relative path after that
        return b.pathJoin(&.{ arch_name, "bin" });
    }

    fn getNativeArchName(b: *std.Build) []const u8 {
        const target = b.graph.host;
        const arch = target.result.cpu.arch;
        const os = target.result.os.tag;
        return b.fmt("{s}-{s}", .{
            @tagName(arch),
            @tagName(os),
        });
    }
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    // Check if a specific target arch is requested via -Dtarget-arch
    const target_arch: TargetArch = b.option(
        TargetArch,
        "target-arch",
        "Target architecture for cross-compilation (native, x86_64_linux, aarch64_linux, aarch64_macos, x86_64_windows)",
    ) orelse .native;

    const target = b.resolveTargetQuery(target_arch.getTarget());

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

    // Link with SQLite (system library or source)
    exe.linkLibC();
    linkSQLite(b, exe, target);

    // Install with architecture-specific directory: ./zig-out/[arch]/bin/rmp
    const install_path = target_arch.getInstallPath(b);

    // Use custom install instead of default installArtifact
    const install_exe = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = install_path } },
    });

    // Add install step for this specific architecture
    const install_step_name = b.fmt("install-{s}", .{@tagName(target_arch)});
    const install_step_desc = b.fmt("Install rmp binary for {s} architecture", .{@tagName(target_arch)});
    const custom_install = b.step(install_step_name, install_step_desc);
    custom_install.dependOn(&install_exe.step);

    // Default install step should use the custom path
    b.getInstallStep().dependOn(&install_exe.step);

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
    linkSQLite(b, unit_tests, target);

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Clean step
    const clean_step = b.step("clean", "Clean build artifacts");
    const clean_cmd = b.addSystemCommand(&.{"rm", "-rf", "zig-out", ".zig-cache"});
    clean_step.dependOn(&clean_cmd.step);

    // Cross-compilation steps for all architectures
    addCrossCompileSteps(b, optimize);
}

fn addCrossCompileSteps(b: *std.Build, optimize: std.builtin.OptimizeMode) void {
    // Create steps for all target architectures
    const archs = .{
        .{ .name = "build-x86_64-linux", .arch = TargetArch.x86_64_linux, .display = "x86_64 Linux" },
        .{ .name = "build-aarch64-linux", .arch = TargetArch.aarch64_linux, .display = "aarch64 Linux" },
        .{ .name = "build-aarch64-macos", .arch = TargetArch.aarch64_macos, .display = "aarch64 macOS" },
        .{ .name = "build-x86_64-windows", .arch = TargetArch.x86_64_windows, .display = "x86_64 Windows" },
    };

    const all_step = b.step("build-all", "Build for all supported architectures");

    inline for (archs) |info| {
        const target = b.resolveTargetQuery(info.arch.getTarget());

        const cross_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        const is_windows = info.arch == .x86_64_windows;
        const cross_exe = b.addExecutable(.{
            .name = if (is_windows) "rmp.exe" else "rmp",
            .root_module = cross_module,
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
        });

        cross_exe.linkLibC();
        // Note: When cross-compiling, SQLite needs to be available for the target
        linkSQLite(b, cross_exe, target);

        // Set custom output path
        const install_path = info.arch.getInstallPath(b);
        const cross_install = b.addInstallArtifact(cross_exe, .{
            .dest_dir = .{ .override = .{ .custom = install_path } },
        });
        all_step.dependOn(&cross_install.step);

        // Individual arch step
        const arch_step = b.step(info.name, b.fmt("Build for {s}", .{info.display}));
        arch_step.dependOn(&cross_install.step);
    }

    // Native build step (default behavior)
    const native_step = b.step("build-native", "Build for native architecture");
    native_step.dependOn(b.getInstallStep());
}

fn linkSQLite(b: *std.Build, exe: *std.Build.Step.Compile, _: std.Build.ResolvedTarget) void {
    // Check for SQLITE_SOURCE environment variable (used in CI for Windows)
    const sqlite_source_path = b.graph.env_map.get("SQLITE_SOURCE");

    if (sqlite_source_path) |source_path| {
        // Compile SQLite from source
        const sqlite_c = b.pathJoin(&.{ source_path, "sqlite3.c" });
        exe.addCSourceFile(.{
            .file = .{ .cwd_relative = sqlite_c },
            .flags = &.{
                "-DSQLITE_THREADSAFE=1",
                "-DSQLITE_ENABLE_FTS5",
                "-DSQLITE_ENABLE_RTREE",
            },
        });
        // Add include path for sqlite3.h
        exe.addIncludePath(.{ .cwd_relative = source_path });
    } else {
        // Link with system SQLite
        exe.linkSystemLibrary("sqlite3");
    }
}
