const std = @import("std");
const models = @import("models");
const steam_web_api = @import("steam_web_api.zig");

pub const SteamLibrary = struct {
    steamAPI: *steam_web_api.SteamAPI,
    allocator: std.mem.Allocator,

    pub fn getGames(self: *SteamLibrary) !std.ArrayList(models.game.Game) {
        const apiGamesList = try self.steamAPI.*.getOwnedGames();

        var games: std.ArrayList(models.game.Game) = try .initCapacity(self.allocator, apiGamesList.capacity);
        var buffer: [256]u8 = undefined;

        for (apiGamesList.items) |apiGame| {
            const appId = try std.fmt.bufPrint(&buffer, "{d}", .{apiGame.appid});
            const currentGame: models.game.Game = .{ .name = apiGame.name, .id = appId };
            try games.append(self.allocator, currentGame);
        }

        return games;
    }
};
