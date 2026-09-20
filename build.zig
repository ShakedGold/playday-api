const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const utils = b.addModule("utils", .{
        .root_source_file = b.path("src/utils/root.zig"),
        .optimize = optimize,
        .target = target,
    });

    const playday_vdf = b.dependency("playday_vdf", .{});

    const http = b.addModule("http", .{
        .root_source_file = b.path("src/http/root.zig"),
        .optimize = optimize,
        .target = target,
    });

    const websocket = b.dependency("websocket", .{});

    const browser = b.addModule("browser", .{
        .root_source_file = b.path("src/browser/root.zig"),
        .optimize = optimize,
        .target = target,
        .imports = &.{
            .{ .name = "http", .module = http },
            .{ .name = "websocket", .module = websocket.module("websocket") },
        },
    });

    // Use .bundle = false if you want to link system SQLite3
    const sqlite = b.dependency("fridge", .{ .bundle = true });

    const db = b.addModule("db", .{
        .root_source_file = b.path("src/models/db/root.zig"),
        .optimize = optimize,
        .target = target,
        .imports = &.{
            .{ .name = "fridge", .module = sqlite.module("fridge") },
        },
    });

    const models = b.addModule("models", .{
        .root_source_file = b.path("src/models/root.zig"),
        .optimize = optimize,
        .target = target,
        .imports = &.{
            .{ .name = "fridge", .module = sqlite.module("fridge") },
            .{ .name = "db", .module = db },
        },
    });

    const steam = b.addModule("steam", .{
        .root_source_file = b.path("src/libraries/steam/root.zig"),
        .optimize = optimize,
        .target = target,
        .imports = &.{
            .{ .name = "utils", .module = utils },
            .{ .name = "http", .module = http },
            .{ .name = "models", .module = models },
            .{ .name = "playday_vdf", .module = playday_vdf.module("playday_vdf") },
        },
    });

    const gog = b.addModule("gog", .{
        .root_source_file = b.path("src/libraries/gog/root.zig"),
        .imports = &.{},
    });

    const libraries = b.addModule("libraries", .{
        .root_source_file = b.path("src/libraries/root.zig"),
        .optimize = optimize,
        .target = target,
        .imports = &.{
            .{ .name = "steam", .module = steam },
            .{ .name = "gog", .module = gog },
            .{ .name = "models", .module = models },
        },
    });

    models.addImport("libraries", libraries);
    db.addImport("libraries", libraries);

    const metadata = b.addModule("metadata", .{
        .root_source_file = b.path("src/metadata/root.zig"),
        .optimize = optimize,
        .target = target,
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

    const test_filter = b.option(
        []const []const u8,
        "test-filter",
        "Only run tests matching this filter",
    ) orelse &.{};

    // Tests
    const browser_tests = b.addTest(.{
        .root_module = browser,
        .filters = test_filter,
    });
    const run_tests = b.addRunArtifact(browser_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
