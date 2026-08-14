const std = @import("std");
const models = @import("models");
const steam_web_api = @import("steam_web_api.zig");

pub const SteamLibrary = struct {
    steamAPI: *steam_web_api.SteamAPI,

    pub fn getGames(self: *SteamLibrary, allocator: std.mem.Allocator) !std.ArrayList(models.game.Game) {
        var apiGamesList = try self.steamAPI.*.getOwnedGames();
        defer apiGamesList.deinit();

        var games: std.ArrayList(models.game.Game) = try .initCapacity(allocator, apiGamesList.games.len);

        for (apiGamesList.games) |*apiGame| {
            const currentGame: models.game.Game = .{
                .id = try std.fmt.allocPrint(allocator, "{d}", .{apiGame.appid}),
                .name = try allocator.dupe(u8, apiGame.name),
                .playtime = apiGame.playtime_forever,
                .icon = &[0]u8{}, // It is possible to fetch the icon using `apiGame.fetchIcon`
            };

            try games.append(allocator, currentGame);
        }

        return games;
    }
};
