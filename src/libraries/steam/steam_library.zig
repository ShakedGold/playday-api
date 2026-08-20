const std = @import("std");

const metadata = @import("metadata");
const models = @import("models");
const utils = @import("utils");

const steam_local = @import("local/steam_local.zig");
const steam_web_api = @import("steam_web_api.zig");

const log = std.log.scoped(.steam_library);

pub const SteamLibrary = struct {
    steamAPI: *steam_web_api.SteamAPI,
    steamLocal: *steam_local.SteamLocal,

    pub fn init(steamAPI: *steam_web_api.SteamAPI, steamLocal: *steam_local.SteamLocal) SteamLibrary {
        return .{
            .steamAPI = steamAPI,
            .steamLocal = steamLocal,
        };
    }

    pub fn deinit(self: *SteamLibrary) void {
        self.steamAPI.deinit();
        self.steamAPI.* = undefined;

        self.steamLocal.deinit();
        self.steamLocal.* = undefined;
    }

    fn getGame(self: *SteamLibrary, apiGame: *steam_web_api.APIGame, allocator: std.mem.Allocator) !models.game.Game {
        var installedGame = self.steamLocal.getInstalledGame(apiGame.appid) catch |err| blk: {
            if (err == error.GameNotFound) {
                log.warn("game = {s} is not found on the file system", .{apiGame.name});
            }

            break :blk null;
        };
        defer if (installedGame) |game| game.app_manifest.deinit();

        const id = try std.fmt.allocPrint(allocator, "{d}", .{apiGame.appid});
        errdefer allocator.free(id);

        const name = try allocator.dupe(u8, apiGame.name);
        errdefer allocator.free(name);

        const icon = try apiGame.fetchIcon(&self.steamAPI.client, allocator);
        errdefer if (icon) |i| allocator.free(i);

        var installedLocation: ?[]u8 = null;
        if (installedGame) |*game| {
            installedLocation = try game.app_manifest.value.getInstallFullPath(allocator, game.path);
        }
        errdefer if (installedLocation) |location| allocator.free(location);

        var lastPlayed: ?u64 = null;
        if (installedGame) |*game| {
            lastPlayed = game.app_manifest.value.AppState.LastPlayed;
        }

        return .{
            .id = id,
            .name = name,
            .playtime = apiGame.playtime_forever,
            .installed_location = installedLocation,
            .library = .steam,
            .icon = icon,
            .last_played = lastPlayed,
        };
    }

    fn getGameTask(self: *SteamLibrary, allocator: std.mem.Allocator, games: []?models.game.Game, apiGame: *steam_web_api.APIGame, index: usize) void {
        const result = &games[index];
        result.* = self.getGame(apiGame, allocator) catch |err| blk: {
            log.err("Error while fetching installed game: {}", .{err});

            break :blk null;
        };
    }

    pub fn getGames(self: *SteamLibrary, io: std.Io, allocator: std.mem.Allocator) ![]?models.game.Game {
        var apiGamesList = try self.steamAPI.getOwnedGames();
        defer apiGamesList.deinit();

        log.info("Received: {d} games", .{apiGamesList.games.len});
        const games = try allocator.alloc(?models.game.Game, apiGamesList.games.len);

        // A caution measure, if we do not go over all of the items for whatever reason, we want them to be null so we wont put garbage data in the database
        @memset(games, null);

        const concurrency: utils.async.BoundedConcurrency(steam_web_api.APIGame) = .{
            .items = apiGamesList.games,
            .batch_size = 25,
        };

        try concurrency.processAll(io, getGameTask, .{ self, allocator, games });

        return games;
    }
};
