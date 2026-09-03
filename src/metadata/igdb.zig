const std = @import("std");

const http = @import("http");
const models = @import("models");

const log = std.log.scoped(.igdb);

const IGDB_BASE_URL = "https://api.igdb.com/v4/{[endpoint]s}";
const IGDB_IMAGE_URL = "https://images.igdb.com/igdb/image/upload/{[image_type]s}/{[image_id]s}.jpg";
const TWITCH_REFRESH_TOKEN = "https://id.twitch.tv/oauth2/token?client_id={[id]s}&client_secret={[secret]s}&grant_type=client_credentials";
const IGDB_GAME_SEARCH_QUERY = "fields cover.image_id, summary; search \"{[game_name]s}\"; limit 1;";

const TwitchOAuth2TokenResponse = struct {
    access_token: []u8,
};

const ClientParams = struct {
    id: []const u8,
    secret: []const u8,
};

const IGDBAPIResponse = struct {
    cover: struct {
        image_id: []const u8,
    },
    summary: []const u8,
};

pub const IGDB = struct {
    pub const Params = ClientParams;

    allocator: std.mem.Allocator,
    io: std.Io,
    client: http.client.Client,
    lock: std.Io.RwLock,

    client_params: Params,
    access_token: ?[]u8,

    pub fn init(io: std.Io, allocator: std.mem.Allocator, params: Params) @This() {
        return .{
            .io = io,
            .allocator = allocator,
            .client = .init(io, allocator),
            .lock = .init,

            .client_params = .{
                .id = params.id,
                .secret = params.secret,
            },
            .access_token = null,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.client.deinit();

        if (self.access_token) |accessToken| {
            self.allocator.free(accessToken);
        }

        self.* = undefined;
    }

    /// Warning: the lifetime of the refresher object should be less than the lifetime of this object,
    /// since this object is responsible for freeing the access_token all refreshers use
    pub fn refresher(self: *@This(), game: *models.game.Game) IGDBRefresher {
        return .init(self.io, self.allocator, &self.access_token, self.client_params, &self.lock, game);
    }
};

pub const IGDBRefresher = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    client: http.client.Client,
    lock: *std.Io.RwLock,

    game: *models.game.Game,
    access_token: *?[]u8,
    client_params: ClientParams,

    responses: ?std.json.Parsed([]IGDBAPIResponse) = null,

    pub fn init(io: std.Io, allocator: std.mem.Allocator, access_token: *?[]u8, client_params: ClientParams, lock: *std.Io.RwLock, game: *models.game.Game) @This() {
        const self: @This() = .{
            .allocator = allocator,
            .io = io,
            .client = .init(io, allocator),
            .client_params = .{
                .id = client_params.id,
                .secret = client_params.secret,
            },
            .access_token = access_token,
            .game = game,
            .lock = lock,
        };

        return self;
    }

    pub fn deinit(self: *@This()) void {
        self.client.deinit();

        if (self.responses) |response| {
            response.deinit();
        }

        self.* = undefined;
    }

    pub fn refreshLogo(self: *@This()) !void {
        _ = self;

        return error.LogoNotSupported;
    }

    pub fn refreshHero(self: *@This()) !void {
        const game = try self.findGame();

        if (self.game.hero) |hero| {
            self.allocator.free(hero);
        }

        var response = try self.client.get(IGDB_IMAGE_URL, .{ .image_type = "t_screenshot_huge", .image_id = game.cover.image_id }, .empty);
        defer response.deinit();

        if (response.status != .ok) {
            return error.GameNotFound;
        }

        if (self.game.hero) |hero| {
            self.allocator.free(hero);
        }

        self.game.hero = try self.allocator.dupe(u8, response.body);
    }

    pub fn refreshGrid(self: *@This()) !void {
        const game = try self.findGame();

        if (self.game.grid) |grid| {
            self.allocator.free(grid);
        }

        var response = try self.client.get(IGDB_IMAGE_URL, .{ .image_type = "t_cover_2x", .image_id = game.cover.image_id }, .empty);
        defer response.deinit();

        if (response.status != .ok) {
            return error.GameNotFound;
        }

        if (self.game.grid) |grid| {
            self.allocator.free(grid);
        }

        self.game.grid = try self.allocator.dupe(u8, response.body);
    }

    pub fn refreshIcon(self: *@This()) !void {
        _ = self;

        return error.IconNotSupported;
    }

    pub fn refreshDescription(self: *@This()) !void {
        const game = try self.findGame();

        if (self.game.description) |description| {
            self.allocator.free(description);
        }

        self.game.description = try self.allocator.dupe(u8, game.summary);
    }

    fn findGame(self: *@This()) !*const IGDBAPIResponse {
        if (self.responses) |response| {
            return &response.value[0];
        }

        const game_query = try std.fmt.allocPrint(self.allocator, IGDB_GAME_SEARCH_QUERY, .{ .game_name = self.game.name });
        defer self.allocator.free(game_query);

        var response = try self.apiCall("games", game_query);
        defer response.deinit();

        const responses = try std.json.parseFromSlice([]IGDBAPIResponse, self.allocator, response.body, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });

        if (responses.value.len < 1) {
            return error.GameNotFound;
        }

        self.responses = responses;
        return &self.responses.?.value[0];
    }

    fn apiCall(self: *@This(), endpoint: []const u8, body: []const u8) !http.response.Response {
        var response = try self.post(endpoint, body);

        log.debug("status: {}", .{response.status});

        // Try again if the access_token is invalid
        if (response.status == .unauthorized) {
            response.deinit();

            try self.refreshToken();
            response = try self.post(endpoint, body);
        }

        return response;
    }

    fn post(self: *@This(), endpoint: []const u8, body: []const u8) !http.response.Response {
        var buffer: [128]u8 = undefined;

        try self.lock.lockShared(self.io);
        defer self.lock.unlockShared(self.io);

        const accessToken = self.access_token.* orelse "";
        const authToken = try std.fmt.bufPrint(buffer[0..], "Bearer {s}", .{accessToken});

        log.debug("Fetching metadata for the game: {s}", .{self.game.name});

        return self.client.post(
            IGDB_BASE_URL,
            .{ .endpoint = endpoint },
            .{
                .body = body,
                .extra_headers = &.{
                    .{
                        .name = "Client-ID",
                        .value = self.client_params.id,
                    },
                    .{
                        .name = "Authorization",
                        .value = authToken,
                    },
                },
            },
        );
    }

    fn refreshToken(self: *@This()) !void {
        log.debug("Refreshing the access token of igdb", .{});

        var previousAccessToken: ?[]u8 = null;

        if (self.access_token.*) |accessToken| {
            try self.lock.lockShared(self.io);
            defer self.lock.unlockShared(self.io);

            previousAccessToken = accessToken;
        }

        try self.lock.lock(self.io);
        defer self.lock.unlock(self.io);

        if (self.access_token.*) |accessToken| {
            if (previousAccessToken) |prevAccessToken| {
                // The access_token may have been refreshed already here since we locked
                if (prevAccessToken.ptr != accessToken.ptr) {
                    // the access_token was already refreshed
                    return;
                }
            }
        }

        var response = try self.client.post(TWITCH_REFRESH_TOKEN, .{ .id = self.client_params.id, .secret = self.client_params.secret }, .empty);
        defer response.deinit();

        const parsed = try std.json.parseFromSlice(
            TwitchOAuth2TokenResponse,
            self.allocator,
            response.body,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();

        if (self.access_token.*) |accessToken| {
            previousAccessToken = accessToken;
        }

        self.access_token.* = try self.allocator.dupe(u8, parsed.value.access_token);

        // We have to first allocate, then free because we do not want to get the same memory address,
        // if we do, then the check for a prior refresh will not work and we do another request for nothing
        if (previousAccessToken) |prevAccessToken| {
            self.allocator.free(prevAccessToken);
        }
    }
};
