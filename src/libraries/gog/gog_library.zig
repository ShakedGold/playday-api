const std = @import("std");

const http = @import("http");
const models = @import("models");
const utils = @import("utils");

const web_api = @import("gog_web_api.zig");

const log = std.log.scoped(.gog_library);

pub const GOGLibrary = struct {
    gog_web_api: web_api.GOGWebAPI,

    pub fn init(io: std.Io, allocator: std.mem.Allocator, webApiOptions: web_api.GOGWebAPIOptions) !@This() {
        return .{ .gog_web_api = .init(io, allocator, webApiOptions) };
    }

    pub fn getGames(self: *@This(), io: std.Io, allocator: std.mem.Allocator) ![]?models.game.Game {
        var apiGamesList = try self.gog_web_api.getGames(io, allocator);
        defer apiGamesList.deinit(allocator);

        log.info("Received: {d} games", .{apiGamesList.games.items.len});
        const games = try allocator.alloc(?models.game.Game, apiGamesList.games.items.len);

        // A caution measure, if we do not go over all of the items for whatever reason, we want them to be null so we wont put garbage data in the database
        @memset(games, null);

        for (apiGamesList.games.items, 0..) |*game, index| {
            const gameId = try allocator.alloc(u8, 36);
            errdefer allocator.free(gameId);

            const uuid = utils.uuid.uuidV4(io);
            @memcpy(gameId, &uuid);

            games[index] = .init(.{
                .id = gameId,
                .name = try allocator.dupe(u8, game.owned_data.value.title),
                .playtime = 0, // GOG does not expose playtime
                .library = .{ .gog = .{ .id = game.id } },
            });
        }

        return games;
    }

    pub fn deinit(self: *@This()) void {
        self.gog_web_api.deinit();

        self.* = undefined;
    }
};

test "GOG Library - get games" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var library: GOGLibrary = .init(io, allocator, .{ .options = .{ .create_client = true } });
    defer library.deinit();

    const games = try library.getGames(io, allocator);
    defer allocator.free(games);

    for (games) |possibleGame| {
        var game = possibleGame orelse continue;
        game.deinit(allocator);
    }
}
