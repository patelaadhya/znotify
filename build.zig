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
            exe.linkFramework("AppKit");
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
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
