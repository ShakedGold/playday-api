const std = @import("std");

const APIGame = struct {
    appid: u32,
    name: []const u8,
};

const DOMAIN = "api.steampowered.com";

fn Response(comptime T: type) type {
    return struct {
        response: T,
    };
}

pub const SteamAPI = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    key: []const u8,
    steamid: []const u8,
    client: std.http.Client,

    pub fn init(allocator: std.mem.Allocator, key: []const u8, steamid: []const u8) !*SteamAPI {
        var api = try allocator.create(SteamAPI);

        api.key = key;
        api.allocator = allocator;
        api.io = std.Io.Threaded.global_single_threaded.io();
        api.client = std.http.Client{ .allocator = api.allocator, .io = api.io };
        api.steamid = steamid;

        return api;
    }

    pub fn deinit(self: *SteamAPI) void {
        self.client.deinit();
        self.allocator.destroy(self);

        self.* = undefined;
    }

    pub fn getOwnedGames(self: *SteamAPI) !std.ArrayList(APIGame) {
        var redirect_buffer: [8 * 1024]u8 = undefined;
        var buffer: [1024]u8 = undefined;

        var body = std.Io.Writer.Allocating.init(self.allocator);

        const formattedUri = try std.fmt.bufPrint(&buffer, "https://" ++ DOMAIN ++ "/IPlayerService/GetOwnedGames/v0001/?key={s}&steamid={s}&include_appinfo=true&include_played_free_games=true&format=json", .{ self.key, self.steamid });
        const uri = try std.Uri.parse(formattedUri);

        _ = try self.client.fetch(.{ .method = .GET, .location = .{ .uri = uri }, .redirect_buffer = &redirect_buffer, .response_writer = &body.writer });
        try body.writer.flush();

        const response = try std.json.parseFromSlice(Response(struct { game_count: u8, games: []APIGame }), self.allocator, body.writer.buffered(), .{ .ignore_unknown_fields = true });

        return .fromOwnedSlice(response.value.response.games);
    }
};
