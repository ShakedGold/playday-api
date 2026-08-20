const std = @import("std");

const fr = @import("fridge");
const libraries = @import("libraries");

const db = @import("db.zig");

const log = std.log.scoped(.game);

pub const Game = @This();

id: []u8,
name: []u8,
playtime: u32,
last_played: ?u64,
installed_location: ?[]u8 = null,
library: std.meta.Tag(libraries.library.Library),
description: ?[]const u8 = null,
icon: ?[]const u8 = null,
logo: ?[]const u8 = null,
hero: ?[]const u8 = null,
grid: ?[]const u8 = null,

fn ensureTable(connection: *fr.Session) !void {
    try connection.conn.execAll(
        \\ CREATE TABLE IF NOT EXISTS game(
        \\  id TEXT PRIMARY KEY,
        \\  name TEXT NOT NULL,
        \\  playtime INTEGER NOT NULL,
        \\  last_played INTEGER,
        \\  installed_location TEXT,
        \\  library INTEGER NOT NULL,
        \\  description TEXT,
        \\  icon BLOB,
        \\  logo BLOB,
        \\  hero BLOB,
        \\  grid BLOB
        \\ );
    );
}

pub fn getGames(allocator: std.mem.Allocator, io: std.Io) !std.ArrayList(Game) {
    const connection = try db.getConnection(allocator, io);
    defer db.deinit(connection, allocator);

    try ensureTable(connection);

    const games: []const Game = try connection.query(Game).findAll();

    // We are copying the items here so we are not bound by the connection to the db
    var gamesList: std.ArrayList(Game) = try .initCapacity(allocator, games.len);
    for (games) |game| {
        try gamesList.append(allocator, .{
            .id = try allocator.dupe(u8, game.id),
            .name = try allocator.dupe(u8, game.name),
            .installed_location = if (game.installed_location) |installed_location| try allocator.dupe(u8, installed_location) else null,
            .playtime = game.playtime,
            .last_played = game.last_played,
            .library = game.library,
            .icon = if (game.icon) |icon| try allocator.dupe(u8, icon) else null,
            .logo = if (game.logo) |logo| try allocator.dupe(u8, logo) else null,
            .hero = if (game.hero) |hero| try allocator.dupe(u8, hero) else null,
            .grid = if (game.grid) |grid| try allocator.dupe(u8, grid) else null,
        });
    }

    return gamesList;
}

pub fn insert(self: *Game, io: std.Io, allocator: std.mem.Allocator) !void {
    var connection = try db.getConnection(allocator, io);
    defer db.deinit(connection, allocator);

    try ensureTable(connection);

    _ = try connection.insert(Game, self.*);
}

pub fn deinit(self: *Game, allocator: std.mem.Allocator) void {
    allocator.free(self.id);
    allocator.free(self.name);

    if (self.installed_location) |installed_location| allocator.free(installed_location);
    if (self.description) |description| allocator.free(description);
    if (self.icon) |icon| allocator.free(icon);
    if (self.logo) |logo| allocator.free(logo);
    if (self.hero) |hero| allocator.free(hero);
    if (self.grid) |grid| allocator.free(grid);
}

pub fn update(self: *Game, io: std.Io, allocator: std.mem.Allocator) !void {
    const connection = try db.getConnection(allocator, io);
    defer db.deinit(connection, allocator);

    try ensureTable(connection);

    var query = try connection.query(Game).where("id", self.id).update(self.*).prepare();
    try query.exec();
}
