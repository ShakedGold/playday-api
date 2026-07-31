const std = @import("std");
const db = @import("db.zig");
const fr = @import("fridge");

const log = std.log.scoped(.game);

pub const Game = @This();

id: []const u8,
name: []const u8,
playtime: u32,
icon: []const u8,
logo: []const u8,

fn createGamesTable(connection: *fr.Session) !void {
    try connection.conn.execAll(
        \\ CREATE TABLE Game(
        \\  id TEXT PRIMARY KEY,
        \\  name TEXT NOT NULL,
        \\  playtime INTEGER NOT NULL,
        \\  icon BLOB,
        \\  logo BLOB
        \\);
    );
}

pub fn getGames(allocator: std.mem.Allocator, io: std.Io) ![]const Game {
    const connection = try db.getConnection(allocator, io);

    const games = connection.*.query(Game).findAll() catch |err| switch (err) {
        error.DbError => {
            log.debug("Failed to lookup the games, table does not exist", .{});
            log.debug("Creating the games table", .{});

            try createGamesTable(connection);
            return &[0]Game{};
        },
        else => return err,
    };
    return games;
}

pub fn addGame(self: *Game, allocator: std.mem.Allocator, io: std.Io) !void {
    const connection = try db.getConnection(allocator, io);

    _ = try connection.*.insert(Game, self);
}
