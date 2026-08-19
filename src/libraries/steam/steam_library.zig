const std = @import("std");
const models = @import("models");
const steam_web_api = @import("steam_web_api.zig");
const steam_local = @import("local/steam_local.zig");
const metadata = @import("metadata");

const log = std.log.scoped(.steam_library);

pub const SteamLibrary = struct {
    steamAPI: *steam_web_api.SteamAPI,
    steamLocal: *steam_local.SteamLocal,

    fn getGame(self: *SteamLibrary, apiGame: *steam_web_api.APIGame, allocator: std.mem.Allocator) !models.game.Game {
        var installedGame, const path = self.steamLocal.getInstalledGame(apiGame.appid) catch .{ null, null };
        defer if (installedGame != null) installedGame.?.deinit();

        const id = try std.fmt.allocPrint(allocator, "{d}", .{apiGame.appid});
        errdefer allocator.free(id);

        const name = try allocator.dupe(u8, apiGame.name);
        errdefer allocator.free(name);

        var installedLocation: ?[]u8 = null;
        if (path != null) {
            installedLocation = try installedGame.?.value.getInstallFullPath(allocator, path.?);
        }
        errdefer if (installedLocation != null) allocator.free(installedLocation);

        return .{
            .id = id,
            .name = name,
            .playtime = apiGame.playtime_forever,
            .installed_location = if (installedGame != null and path != null) installedLocation else null,
        };
    }

    fn getGameTask(self: *SteamLibrary, apiGame: *steam_web_api.APIGame, allocator: std.mem.Allocator, result: *?models.game.Game) void {
        result.* = self.getGame(apiGame, allocator) catch null;
    }

    pub fn getGames(self: *SteamLibrary, io: std.Io, allocator: std.mem.Allocator) ![]?models.game.Game {
        var apiGamesList = try self.steamAPI.*.getOwnedGames();
        defer apiGamesList.deinit();

        log.info("Received: {d} games", .{apiGamesList.games.len});
        var games = try allocator.alloc(?models.game.Game, apiGamesList.games.len);

        const concurrency_limit = 25;
        var i: usize = 0;
        while (i < apiGamesList.games.len) {
            const end = @min(i + concurrency_limit, apiGamesList.games.len);
            var gameGroup: std.Io.Group = .init;
            errdefer gameGroup.cancel(io);

            var j = i;
            while (j < end) : (j += 1) {
                log.info("Creating the game model: {s}, appid: {d}", .{ apiGamesList.games[j].name, apiGamesList.games[j].appid });
                try gameGroup.concurrent(io, getGameTask, .{ self, &apiGamesList.games[j], allocator, &games[j] });
            }

            try gameGroup.await(io);
            i = end;
        }

        return games;
    }
};
