const std = @import("std");
const db = @import("db.zig");
const fr = @import("fridge");

const log = std.log.scoped(.extra_game_metadata);

pub const ExtraGameMetadata = @This();

id: []const u8,
description: ?[]const u8 = null,
icon: ?[]const u8 = null,
logo: ?[]const u8 = null,
hero: ?[]const u8 = null,
grid: ?[]const u8 = null,

fn createTable(connection: *fr.Session) !void {
    try connection.conn.execAll(
        \\ CREATE TABLE extra_game_metadata(
        \\ id TEXT NOT NULL,
        \\ description TEXT,
        \\ icon BLOB,
        \\ logo BLOB,
        \\ hero BLOB,
        \\ grid BLOB
        \\ );
    );
}

pub fn getMetadata(id: []u8, allocator: std.mem.Allocator, io: std.Io) !ExtraGameMetadata {
    var connection = try db.getConnection(allocator, io);
    defer db.deinit(connection, allocator);

    const metadata: ?ExtraGameMetadata = connection.find(ExtraGameMetadata, id) catch |err| switch (err) {
        error.DbError => {
            log.debug("Failed to lookup the metadata on {s}, table does not exist", .{id});
            log.debug("Creating the metadata table", .{});

            try createTable(connection);
            return .{ .id = try allocator.dupe(u8, id) };
        },
        else => return err,
    } orelse return error.MetadataNotFound;

    return metadata.?;
}

pub fn deinit(self: *ExtraGameMetadata, allocator: std.mem.Allocator) void {
    allocator.free(self.id);

    if (self.description != null) allocator.free(self.description.?);
    if (self.icon != null) allocator.free(self.icon.?);
    if (self.logo != null) allocator.free(self.logo.?);
    if (self.hero != null) allocator.free(self.hero.?);
    if (self.grid != null) allocator.free(self.grid.?);
}
