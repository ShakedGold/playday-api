const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const utils = b.addModule("utils", .{
        .root_source_file = b.path("src/utils/root.zig"),
    });

    const playday_vdf = b.dependency("playday_vdf", .{});

    const http = b.addModule("http", .{
        .root_source_file = b.path("src/http/root.zig"),
    });

    const sqlite = b.dependency("fridge", .{ .bundle = true });

    // Use .bundle = false if you want to link system SQLite3
    const models = b.addModule("models", .{
        .root_source_file = b.path("src/models/root.zig"),
        .imports = &.{
            .{ .name = "fridge", .module = sqlite.module("fridge") },
        },
    });

    const steam = b.addModule("steam", .{
        .root_source_file = b.path("src/libraries/steam/root.zig"),
        .imports = &.{
            .{ .name = "utils", .module = utils },
            .{ .name = "http", .module = http },
            .{ .name = "models", .module = models },
            .{ .name = "playday_vdf", .module = playday_vdf.module("playday_vdf") },
        },
    });

    const libraries = b.addModule("libraries", .{
        .root_source_file = b.path("src/libraries/root.zig"),
        .imports = &.{
            .{ .name = "steam", .module = steam },
            .{ .name = "models", .module = models },
        },
    });

    models.addImport("libraries", libraries);

    const metadata = b.addModule("metadata", .{
        .root_source_file = b.path("src/metadata/root.zig"),
        .imports = &.{
            .{ .name = "models", .module = models },
            .{ .name = "http", .module = http },
        },
    });

    const playday_api_mod = b.addModule("playday-api", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "models", .module = models },
            .{ .name = "http", .module = http },
            .{ .name = "libraries", .module = libraries },
            .{ .name = "metadata", .module = metadata },
            .{ .name = "utils", .module = utils },
            .{ .name = "playday_vdf", .module = playday_vdf.module("playday_vdf") },
        },
    });

    const lib = b.addLibrary(.{
        .name = "playday-api",
        .linkage = .static,
        .root_module = playday_api_mod,
    });
    b.installArtifact(lib);
}
