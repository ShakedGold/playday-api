const std = @import("std");
const models = @import("models");
const steam_web_api = @import("steam_web_api.zig");
const steam_local = @import("local/steam_local.zig");

const log = std.log.scoped(.steam_library);

pub const SteamLibrary = struct {
    steamAPI: *steam_web_api.SteamAPI,
    steamLocal: *steam_local.SteamLocal,

    fn getGame(self: *SteamLibrary, apiGame: *steam_web_api.APIGame, allocator: std.mem.Allocator) !models.game.Game {
        var installedGame, const path = self.steamLocal.getInstalledGame(apiGame.appid) catch .{ null, null };
        defer if (installedGame != null) installedGame.?.deinit();

        return .{
            .id = try std.fmt.allocPrint(allocator, "{d}", .{apiGame.appid}),
            .name = try allocator.dupe(u8, apiGame.name),
            .playtime = apiGame.playtime_forever,
            .icon = try apiGame.fetchIcon(&self.steamAPI.client, allocator),
            .installed_location = if (installedGame != null and path != null) try installedGame.?.value.getInstallFullPath(allocator, path.?) else null,
        };
    }

    fn getGameTask(self: *SteamLibrary, apiGame: *steam_web_api.APIGame, allocator: std.mem.Allocator, result: *?models.game.Game) void {
        result.* = self.getGame(apiGame, allocator) catch return;
    }

    pub fn getGames(self: *SteamLibrary, io: std.Io, allocator: std.mem.Allocator) ![]?models.game.Game {
        var apiGamesList = try self.steamAPI.*.getOwnedGames();
        defer apiGamesList.deinit();

        log.info("Received: {d} games", .{apiGamesList.games.len});
        var games = try allocator.alloc(?models.game.Game, apiGamesList.games.len);

        var gameGroup: std.Io.Group = .init;
        defer gameGroup.cancel(io);

        for (apiGamesList.games, 0..) |*apiGame, index| {
            log.info("Creating the game model: {s}, appid: {d}", .{ apiGame.name, apiGame.appid });
            try gameGroup.concurrent(io, getGameTask, .{ self, apiGame, allocator, &games[index] });
        }

        try gameGroup.await(io);

        return games;
    }
};
