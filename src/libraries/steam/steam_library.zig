const std = @import("std");
const models = @import("models");
const steam_web_api = @import("steam_web_api.zig");
const steam_local = @import("local/steam_local.zig");

const log = std.log.scoped(.steam_library);

pub const SteamLibrary = struct {
    steamAPI: *steam_web_api.SteamAPI,
    steamLocal: *steam_local.SteamLocal,

    fn isGameInstalled(self: *SteamLibrary, appid: u32) bool {
        // TODO: use the fields from the acf to get more metadata on the game
        _ = self.steamLocal.getInstalledGame(appid) catch return false;
        return true;
    }

    pub fn getGames(self: *SteamLibrary, allocator: std.mem.Allocator) !std.ArrayList(models.game.Game) {
        log.info("Requesting game list from the steam web api", .{});
        var apiGamesList = try self.steamAPI.*.getOwnedGames();
        defer apiGamesList.deinit();

        log.info("Received: {d} games", .{apiGamesList.games.len});

        var games: std.ArrayList(models.game.Game) = try .initCapacity(allocator, apiGamesList.games.len);

        for (apiGamesList.games) |*apiGame| {
            log.info("Creating the game model: {s}, appid: {d}", .{ apiGame.name, apiGame.appid });
            const currentGame: models.game.Game = .{
                .id = try std.fmt.allocPrint(allocator, "{d}", .{apiGame.appid}),
                .name = try allocator.dupe(u8, apiGame.name),
                .playtime = apiGame.playtime_forever,
                .icon = try apiGame.fetchIcon(&self.steamAPI.client, allocator),
                .is_installed = self.isGameInstalled(apiGame.appid),
            };

            try games.append(allocator, currentGame);
        }

        return games;
    }
};
