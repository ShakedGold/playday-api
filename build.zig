const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "playday-api",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(lib);

    // Use .bundle = false if you want to link system SQLite3
    const models = b.addModule("models", .{
        .root_source_file = b.path("src/models/root.zig"),
    });

    const sqlite = b.dependency("fridge", .{ .bundle = true });
    models.addImport("fridge", sqlite.module("fridge"));

    lib.root_module.addImport("models", models);

    _ = b.addModule("playday-api", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "models", .module = models },
        },
    });
}
