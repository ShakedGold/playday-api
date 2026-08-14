const std = @import("std");
const http = @import("http");

const log = std.log.scoped(.steam_web_api);

const APIGame = struct {
    appid: u32,
    name: []const u8,
    playtime_forever: u32,
    img_icon_url: []const u8,

    pub fn fetchIcon(self: *APIGame, client: *http.client.Client, allocator: std.mem.Allocator) !?[]u8 {
        log.debug("Fetching: {s} https://media.steampowered.com/steamcommunity/public/images/apps/{d}/{s}.jpg", .{ self.name, self.appid, self.img_icon_url });
        var response = try client.get("https://media.steampowered.com/steamcommunity/public/images/apps/{d}/{s}.jpg", .{ self.appid, self.img_icon_url });
        defer response.deinit();

        if (response.status != .ok) {
            return null;
        }

        return try allocator.dupe(u8, response.body);
    }
};

const DOMAIN = "api.steampowered.com";

fn Response(comptime T: type) type {
    return struct {
        response: T,
    };
}

const OwnedGamesResponse = Response(struct {
    game_count: u8,
    games: []APIGame,
});

pub const OwnedGames = struct {
    parsed: std.json.Parsed(OwnedGamesResponse),
    games: []APIGame,

    pub fn deinit(self: *OwnedGames) void {
        self.parsed.deinit();
    }
};

pub const SteamAPI = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    key: []const u8,
    steamid: []const u8,
    client: http.client.Client,

    pub fn init(io: std.Io, allocator: std.mem.Allocator, key: []const u8, steamid: []const u8) SteamAPI {
        return .{
            .allocator = allocator,
            .io = io,
            .key = key,
            .client = .init(io, allocator),
            .steamid = steamid,
        };
    }

    pub fn deinit(self: *SteamAPI) void {
        self.client.deinit();

        self.* = undefined;
    }

    pub fn getOwnedGames(self: *SteamAPI) !OwnedGames {
        var response = try self.client.get(
            "https://{s}/IPlayerService/GetOwnedGames/v0001/?key={s}&steamid={s}&include_appinfo=true&include_played_free_games=true&format=json",
            .{ DOMAIN, self.key, self.steamid },
        );
        defer response.deinit();

        const parsed = try std.json.parseFromSlice(
            OwnedGamesResponse,
            self.allocator,
            response.body,
            .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
        );
        return .{
            .parsed = parsed,
            .games = parsed.value.response.games,
        };
    }
};
