const std = @import("std");
const db = @import("db.zig");
const fr = @import("fridge");

const log = std.log.scoped(.game);

pub const Game = @This();

id: []u8,
name: []u8,
playtime: u32,
icon: []const u8,

fn createGamesTable(connection: *fr.Session) !void {
    try connection.conn.execAll(
        \\ CREATE TABLE Game(
        \\  id TEXT PRIMARY KEY,
        \\  name TEXT NOT NULL,
        \\  playtime INTEGER NOT NULL,
        \\  icon BLOB
        \\);
    );
}

pub fn getGames(allocator: std.mem.Allocator, io: std.Io) !std.ArrayList(Game) {
    const connection = try db.getConnection(allocator, io);
    defer connection.deinit();

    const games = connection.query(Game).findAll() catch |err| switch (err) {
        error.DbError => {
            log.debug("Failed to lookup the games, table does not exist", .{});
            log.debug("Creating the games table", .{});

            try createGamesTable(connection);
            return .initCapacity(allocator, 0);
        },
        else => return err,
    };

    // We are copying the items here so we are not bound by the connection to the db
    var gamesList: std.ArrayList(Game) = try .initCapacity(allocator, games.len);
    for (games) |game| {
        try gamesList.append(allocator, .{
            .id = try allocator.dupe(u8, game.id),
            .name = try allocator.dupe(u8, game.name),
            .icon = try allocator.dupe(u8, game.icon),
            .playtime = game.playtime,
        });
    }

    return gamesList;
}

pub fn insert(self: *Game, io: std.Io, allocator: std.mem.Allocator) !void {
    var connection = try fr.Session.open(fr.SQLite3, allocator, io, .{ .filename = "playday.db" });
    defer connection.deinit();

    _ = try connection.insert(Game, self.*);
}

pub fn deinit(self: *const Game, allocator: std.mem.Allocator) void {
    allocator.free(self.id);
    allocator.free(self.name);
    allocator.free(self.icon);
}
