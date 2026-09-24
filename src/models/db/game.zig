const std = @import("std");

const fr = @import("fridge");

const db = @import("root.zig");

pub const Game = @This();

id: []const u8,
name: []u8,
playtime: u32,
last_played: ?u64 = null,
installed_location: ?[]u8 = null,

pub fn ensureTable(connection: *fr.Session) !void {
    try connection.conn.execAll(
        \\ CREATE TABLE IF NOT EXISTS game(
        \\  id TEXT PRIMARY KEY,
        \\  name TEXT NOT NULL,
        \\  playtime INTEGER NOT NULL,
        \\  last_played INTEGER,
        \\  installed_location TEXT
        \\ );
    );
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    allocator.free(self.id);
    allocator.free(self.name);

    if (self.installed_location) |installed_location| {
        allocator.free(installed_location);
    }
}

pub fn insert(self: *@This(), io: std.Io, allocator: std.mem.Allocator) !void {
    var connection = try db.getConnection(allocator, io);
    defer db.deinit(connection, allocator);

    try ensureTable(connection);

    _ = try connection.insert(Game, self.*);
}

pub fn update(self: *@This(), io: std.Io, allocator: std.mem.Allocator) !void {
    const connection = try db.getConnection(allocator, io);
    defer db.deinit(connection, allocator);

    try ensureTable(connection);

    var query = try connection.query(Game).where("id", self.id).update(self.*).prepare();
    defer query.deinit();

    try query.exec();
}

pub fn clone(self: *const @This(), allocator: std.mem.Allocator) !@This() {
    return .{
        .id = try allocator.dupe(u8, self.id),
        .name = try allocator.dupe(u8, self.name),
        .installed_location = if (self.installed_location) |installed_location| try allocator.dupe(u8, installed_location) else null,
        .last_played = self.last_played,
        .playtime = self.playtime,
    };
}
