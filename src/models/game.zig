const std = @import("std");

const db = @import("db");
const fr = @import("fridge");

pub const Game = struct {
    game: db.Game,
    library: db.LibraryData,
    metadata: db.GameMetadata,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.game.deinit(allocator);
        self.library.deinit(allocator);
        self.metadata.deinit(allocator);
    }

    pub fn insert(self: *@This(), io: std.Io, allocator: std.mem.Allocator) !void {
        try self.game.insert(io, allocator);
        try self.library.insert(io, allocator);
        try self.metadata.insert(io, allocator);
    }

    pub fn update(self: *@This(), io: std.Io, allocator: std.mem.Allocator) !void {
        try self.game.update(io, allocator);
        try self.library.update(io, allocator);
        try self.metadata.update(io, allocator);
    }
};

/// Returns the full list of games from the DB. caller owns memory
pub fn getGames(allocator: std.mem.Allocator, io: std.Io) ![]Game {
    const connection = try db.getConnection(allocator, io);
    defer db.deinit(connection, allocator);

    try db.Game.ensureTable(connection);
    try db.GameMetadata.ensureTable(connection);
    try db.LibraryData.ensureTable(connection);

    const dbResults = try db.join(
        connection,
        allocator,
        Game,
        .{
            .{ "library", "game.id = library.id" },
            .{ "metadata", "game.id = metadata.id" },
        },
    );
    defer allocator.free(dbResults);

    const results = try allocator.alloc(Game, dbResults.len);

    for (dbResults, 0..) |result, index| {
        results[index] = .{
            .game = try result.game.clone(allocator),
            .library = try result.library.clone(allocator),
            .metadata = try result.metadata.clone(allocator),
        };

        // Overriding since they are the same values
        results[index].library.id = results[index].game.id;
        results[index].metadata.id = results[index].game.id;
    }

    return results;
}
