const std = @import("std");

const fr = @import("fridge");

const db = @import("root.zig");

pub const GameMetadata = @This();
id: []const u8,
description: ?[]const u8 = null,
icon: ?[]const u8 = null,
logo: ?[]const u8 = null,
hero: ?[]const u8 = null,
grid: ?[]const u8 = null,

pub fn ensureTable(connection: *fr.Session) !void {
    try connection.conn.execAll(
        \\ CREATE TABLE IF NOT EXISTS metadata(
        \\ id TEXT PRIMARY KEY,
        \\ description TEXT,
        \\ icon BLOB,
        \\ logo BLOB,
        \\ hero BLOB,
        \\ grid BLOB
        \\ );
    );
}

pub fn clone(self: *const @This(), allocator: std.mem.Allocator) !@This() {
    return .{
        .id = self.id,
        .description = if (self.description) |description| try allocator.dupe(u8, description) else null,
        .icon = if (self.icon) |icon| try allocator.dupe(u8, icon) else null,
        .logo = if (self.logo) |logo| try allocator.dupe(u8, logo) else null,
        .hero = if (self.hero) |hero| try allocator.dupe(u8, hero) else null,
        .grid = if (self.grid) |grid| try allocator.dupe(u8, grid) else null,
    };
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    if (self.description) |description| allocator.free(description);
    if (self.icon) |icon| allocator.free(icon);
    if (self.logo) |logo| allocator.free(logo);
    if (self.hero) |hero| allocator.free(hero);
    if (self.grid) |grid| allocator.free(grid);

    self.* = undefined;
}

pub fn insert(self: *@This(), io: std.Io, allocator: std.mem.Allocator) !void {
    var connection = try db.getConnection(allocator, io);
    defer db.deinit(connection, allocator);

    try ensureTable(connection);

    _ = try connection.insert(@This(), self.*);
}

pub fn update(self: *@This(), io: std.Io, allocator: std.mem.Allocator) !void {
    const connection = try db.getConnection(allocator, io);
    defer db.deinit(connection, allocator);

    try ensureTable(connection);

    var query = try connection.query(@This()).where("id", self.id).update(self.*).prepare();
    defer query.deinit();

    try query.exec();
}
