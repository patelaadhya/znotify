const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main executable
    const exe = b.addExecutable(.{
        .name = "znotify",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Platform-specific linking
    const target_os = target.result.os.tag;
    switch (target_os) {
        .windows => {
            exe.linkSystemLibrary("ole32");
            exe.linkSystemLibrary("shell32");
            exe.linkSystemLibrary("user32");
            exe.subsystem = .Console;
        },
        .linux => {
            exe.linkSystemLibrary("c");
            // D-Bus will be loaded dynamically
        },
        .macos => {
            exe.linkFramework("Foundation");
            exe.linkFramework("CoreFoundation");
            exe.linkFramework("AppKit");
            exe.linkFramework("UserNotifications");
            exe.linkSystemLibrary("objc");
        },
        else => {},
    }

    // Build options
    const options = b.addOptions();
    options.addOption(bool, "enable_debug", b.option(bool, "debug", "Enable debug output") orelse false);
    options.addOption(bool, "enable_config", b.option(bool, "config", "Enable config file support") orelse true);
    exe.root_module.addOptions("build_options", options);

    b.installArtifact(exe);

    // macOS: Create app bundle for UserNotifications support
    if (target.result.os.tag == .macos) {
        // Create ZNotify.app bundle structure
        const bundle_step = b.addInstallDirectory(.{
            .source_dir = b.path("bundle_template"),
            .install_dir = .prefix,
            .install_subdir = "ZNotify.app",
        });

        // Install executable into bundle
        const exe_install = b.addInstallFile(
            exe.getEmittedBin(),
            "ZNotify.app/Contents/MacOS/znotify",
        );

        exe_install.step.dependOn(&exe.step);
        bundle_step.step.dependOn(&exe_install.step);

        // Code sign the app bundle (required for UserNotifications)
        const codesign = b.addSystemCommand(&[_][]const u8{
            "codesign",
            "--force",
            "--deep",
            "--sign",
            "-",
            "zig-out/ZNotify.app",
        });
        codesign.step.dependOn(&bundle_step.step);
        b.getInstallStep().dependOn(&codesign.step);

        // Create symlink for CLI usage: zig-out/bin/znotify -> ZNotify.app/Contents/MacOS/znotify
        const symlink_step = b.addInstallFile(
            exe.getEmittedBin(),
            "bin/znotify",
        );
        b.getInstallStep().dependOn(&symlink_step.step);
    }

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run znotify");
    run_step.dependOn(&run_cmd.step);

    // Test command
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    unit_tests.root_module.addOptions("build_options", options);

    // Link frameworks for macOS tests
    if (target.result.os.tag == .macos) {
        unit_tests.linkFramework("Foundation");
        unit_tests.linkFramework("CoreFoundation");
        unit_tests.linkFramework("AppKit");
        unit_tests.linkFramework("UserNotifications");
        unit_tests.linkSystemLibrary("objc");
    }

    const test_step = b.step("test", "Run unit tests");

    // macOS: Run tests from within app bundle to provide bundle context for UNUserNotificationCenter
    if (target.result.os.tag == .macos) {
        // Install test executable into app bundle
        const test_install = b.addInstallFile(
            unit_tests.getEmittedBin(),
            "ZNotify.app/Contents/MacOS/znotify_test",
        );
        test_install.step.dependOn(&unit_tests.step);
        // Ensure the app bundle is fully built and signed before installing tests
        test_install.step.dependOn(b.getInstallStep());

        // Run tests from within the bundle (provides bundle context)
        const run_bundled_tests = b.addSystemCommand(&[_][]const u8{
            "zig-out/ZNotify.app/Contents/MacOS/znotify_test",
        });
        run_bundled_tests.step.dependOn(&test_install.step);

        test_step.dependOn(&run_bundled_tests.step);
    } else {
        // Non-macOS: Run tests normally
        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_unit_tests.step);
    }

    // Benchmark command
    const bench = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bench.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    bench.root_module.addOptions("build_options", options);
    const run_bench = b.addRunArtifact(bench);
    const bench_step = b.step("bench", "Run performance benchmarks");
    bench_step.dependOn(&run_bench.step);
}
