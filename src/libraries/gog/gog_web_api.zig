const std = @import("std");
const builtin = @import("builtin");

const browser = @import("browser");
const http = @import("http");
const models = @import("models");
const utils = @import("utils");

const log = std.log.scoped(.gog_web_api);

const GOG_AUTH_API_BASE = "https://auth.gog.com";
const GOG_API_BASE = "https://embed.gog.com";
const GOG_QUERY_PARAMS = "client_id=46899977096215655&client_secret=9d85c43b1482497dbbce61f6e4aa173a433796eeae2ca8c5f6129f2dc4de46d9";
const GOG_REDIRECT_URL = GOG_API_BASE ++ "/on_login_success?origin=client";

const chrome_path = switch (builtin.target.os.tag) {
    .linux => "chromium-browser",
    else => @compileError("Unsupported OS!"),
};

const LoginResult = struct {
    browser: browser.Browser,
    session: browser.Session,

    pub fn deinit(self: *@This(), io: std.Io, allocator: std.mem.Allocator) void {
        self.session.deinit(allocator);
        self.browser.deinit(io);
    }
};

const GOGOwnedGames = struct {
    owned: []const u32,
};
const GOGGame = struct {
    title: []const u8,
    backgroundImage: []const u8,
};
const ParsedGOGGames = struct {
    games: std.ArrayList(std.json.Parsed(GOGGame)),

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        for (self.games.items) |game| {
            game.deinit();
        }

        self.games.deinit(allocator);

        self.* = undefined;
    }
};

fn gotoLoginPage(session: *browser.Session, allocator: std.mem.Allocator) !void {
    const GOG_AUTH_URL = GOG_AUTH_API_BASE ++
        \\/auth
        \\?client_id=46899977096215655
        \\&redirect_uri=https%3A%2F%2Fembed.gog.com%2Fon_login_success%3Forigin%3Dclient
        \\&response_type=code
        \\&layout=client2
    ;

    _ = try session.sendMessage(
        allocator,
        .{ .page = .enable },
        .{},
        null,
        browser.EmptyMessageResponse,
    );

    _ = try session.sendMessage(
        allocator,
        .{ .page = .navigate },
        .{ .url = GOG_AUTH_URL },
        null,
        browser.EmptyMessageResponse,
    );
}

fn getCodeFromSession(session: *const browser.Session, allocator: std.mem.Allocator) ![]const u8 {
    const FrameNavigatedResult = struct {
        params: struct {
            frame: struct {
                id: []const u8,
                url: []const u8,
            },
        },
    };

    var code: []const u8 = &.{};
    while (code.len == 0) {
        const frame_event = try session.getEvent(
            allocator,
            .{ .page = .frameNavigated },
            FrameNavigatedResult,
        );

        if (frame_event) |event| {
            defer event.deinit();

            const is_correct_url = std.mem.startsWith(
                u8,
                event.value.params.frame.url,
                "https://embed.gog.com/on_login_success",
            );

            if (is_correct_url) {
                const CODE_LITERAL = "code=";
                const code_index = std.mem.find(u8, event.value.params.frame.url, CODE_LITERAL);
                if (code_index) |index| {
                    code = try allocator.dupe(u8, event.value.params.frame.url[(index + CODE_LITERAL.len)..]);
                }
            }
        }
    }

    return code;
}

/// Prompts the user with a gog auth login and returns the auth code. caller owns the memory and needs to free the code.
fn login(io: std.Io, allocator: std.mem.Allocator) ![]const u8 {
    var login_browser: browser.Browser = .init(chrome_path);
    defer login_browser.deinit(io);

    try login_browser.launch(io, allocator);

    var session = try login_browser.createSession(allocator);
    defer session.deinit(allocator);

    try gotoLoginPage(&session, allocator);

    const code = try getCodeFromSession(&session, allocator);
    return code;
}

const RefreshParams = union(enum) {
    first: struct {
        code: []const u8,
        redirect_uri: []const u8,
    },
    refresh: struct {
        refresh_token: []const u8,
    },
};

const TokenResponse = struct {
    refresh_token: []const u8,
    access_token: []const u8,
};

pub const GOGWebAPI = struct {
    client: http.client.Client,
    tokens: ?std.json.Parsed(TokenResponse) = null,

    pub fn init(client: http.client.ClientType) @This() {
        return .{ .client = .init(client) };
    }

    pub fn deinit(self: *@This()) void {
        if (self.tokens) |tokens| {
            tokens.deinit();
        }

        self.client.deinit();
    }

    fn refreshToken(self: *@This(), allocator: std.mem.Allocator, params: RefreshParams) !std.json.Parsed(TokenResponse) {
        const refreshType = switch (params) {
            .first => "authorization_code",
            .refresh => "refresh_token",
        };

        const other_params = switch (params) {
            .first => |first| try std.fmt.allocPrint(allocator, "code={s}&redirect_uri={s}", .{ first.code, first.redirect_uri }),
            .refresh => |refresh| try std.fmt.allocPrint(allocator, "refresh_token={s}", .{refresh.refresh_token}),
        };
        defer allocator.free(other_params);

        var response = try self.client.get(GOG_AUTH_API_BASE ++ "/token?" ++ GOG_QUERY_PARAMS ++ "&grant_type={s}&{s}", .{ refreshType, other_params }, .empty);
        defer response.deinit();

        const tokens = try std.json.parseFromSlice(TokenResponse, allocator, response.body, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
        return tokens;
    }

    fn retrieveNewTokens(self: *@This(), io: std.Io, allocator: std.mem.Allocator) !void {
        if (self.tokens) |_| {
            return error.AlreadyLoggedIn;
        }

        // TODO: have a way to store the auth code in a file/db so it can be re-used later without login every time.
        const code = try login(io, allocator);
        defer allocator.free(code);

        self.tokens = try self.refreshToken(
            allocator,
            .{ .first = .{ .code = code, .redirect_uri = GOG_REDIRECT_URL } },
        );
    }

    fn newRefreshToken(self: *@This(), allocator: std.mem.Allocator) !void {
        const tokens = self.tokens orelse return error.RefreshTokensDoNotExist;
        // Freeing the old tokens
        defer tokens.deinit();

        self.tokens = try self.refreshToken(
            allocator,
            .{ .refresh = .{ .refresh_token = tokens.value.refresh_token } },
        );
    }

    fn refreshTokens(self: *@This(), io: std.Io, allocator: std.mem.Allocator) !void {
        if (self.tokens) |_| {
            return self.newRefreshToken(allocator);
        }

        return self.retrieveNewTokens(io, allocator);
    }

    fn fetch(self: *@This(), comptime method: std.http.Method, comptime endpoint: []const u8, params: anytype, allocator: std.mem.Allocator) !http.response.Response {
        const tokens = self.tokens orelse return error.TokensDoNotExist;

        const authorization_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{tokens.value.access_token});
        defer allocator.free(authorization_header);

        return self.client.fetch(
            method,
            GOG_API_BASE ++ endpoint,
            params,
            .{
                .extra_headers = &.{
                    .{
                        .name = "Authorization",
                        .value = authorization_header,
                    },
                },
            },
        );
    }

    /// Returns the list of game ids from gog, caller owns the memory, need to call `deinit`
    fn getGameIDs(self: *@This(), allocator: std.mem.Allocator) !std.json.Parsed(GOGOwnedGames) {
        var response = try self.fetch(.GET, "/user/data/games", .{}, allocator);
        defer response.deinit();

        return std.json.parseFromSlice(GOGOwnedGames, allocator, response.body, .{ .allocate = .alloc_always });
    }

    fn getGameFromID(self: *@This(), gameID: u32, allocator: std.mem.Allocator) !std.json.Parsed(GOGGame) {
        var response = try self.fetch(.GET, "/account/gameDetails/{d}.json", .{gameID}, allocator);
        defer response.deinit();

        if (std.mem.eql(u8, response.body, "[]")) {
            return error.GameNotFound;
        }

        return std.json.parseFromSlice(GOGGame, allocator, response.body, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    }

    /// Returns a slice of GOGGame's. caller owns memory and needs to call `deinit`
    pub fn getGames(self: *@This(), io: std.Io, allocator: std.mem.Allocator) !ParsedGOGGames {
        if (self.tokens == null) {
            try self.refreshTokens(io, allocator);
        }

        const gameIDs = try self.getGameIDs(allocator);
        defer gameIDs.deinit();

        var parsedGogGames: ParsedGOGGames = .{ .games = try .initCapacity(allocator, gameIDs.value.owned.len) };
        errdefer parsedGogGames.deinit(allocator);

        for (gameIDs.value.owned) |gameID| {
            const game = self.getGameFromID(gameID, allocator) catch |err| switch (err) {
                error.GameNotFound => {
                    log.warn("Game not found: id={d}", .{gameID});
                    continue;
                },
                else => return err,
            };

            parsedGogGames.games.appendAssumeCapacity(game);
        }

        // Report that no games have been found

        const amountOfFoundGames = parsedGogGames.games.items.len;
        const amountOfRequestedGames = gameIDs.value.owned.len;

        if (amountOfRequestedGames != 0 and amountOfFoundGames == 0) {
            return error.NoGamesFound;
        }

        return parsedGogGames;
    }
};

test "Fetch Games - 0 games" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var mock_client = http.mock_client.init(io, allocator, .default);

    const owned_games: GOGOwnedGames = .{ .owned = &.{} };
    const formatted_body = std.json.fmt(owned_games, .{});

    // will get freed in `web_api`
    const response: http.response.Response = .{
        .allocator = allocator,
        .body = try std.fmt.allocPrint(allocator, "{f}", .{formatted_body}),
        .status = .ok,
    };

    try mock_client.registerMockResponse(.GET, "https://embed.gog.com/user/data/games", .{}, response);

    var web_api: GOGWebAPI = .init(mock_client);
    defer web_api.deinit();

    var parsedGames = try web_api.getGames(io, allocator);
    defer parsedGames.deinit(allocator);

    try std.testing.expectEqual(0, parsedGames.games.len);
}

test "Fetch Games - Game not found" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const fake_game_id = 1;

    var mock_client = http.mock_client.init(io, allocator, .default);
    const owned_games: GOGOwnedGames = .{ .owned = &.{fake_game_id} };
    const formatted_body = std.json.fmt(owned_games, .{});

    // will get freed in `web_api`
    const response: http.response.Response = .{
        .allocator = allocator,
        .body = try std.fmt.allocPrint(allocator, "{f}", .{formatted_body}),
        .status = .ok,
    };

    try mock_client.registerMockResponse(.GET, "https://embed.gog.com/user/data/games", .{}, response);

    var web_api: GOGWebAPI = .init(mock_client);
    defer web_api.deinit();

    try std.testing.expectError(error.NoGamesFound, web_api.getGames(io, allocator));
}

test "Fetch Games - 1 game" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    // `curl -L 'https://www.gog.com/en/game/astro_burn_demo' 2>/dev/null | grep '"sku":.*' | grep -o "[0-9]*"` - make sure you own this game (it is free)
    const owned_game: u32 = 1182721388;

    var mock_client = http.mock_client.init(io, allocator, .default);
    const owned_games: GOGOwnedGames = .{ .owned = &.{owned_game} };
    const formatted_body = std.json.fmt(owned_games, .{});

    // will get freed in `web_api`
    const response: http.response.Response = .{
        .allocator = allocator,
        .body = try std.fmt.allocPrint(allocator, "{f}", .{formatted_body}),
        .status = .ok,
    };

    try mock_client.registerMockResponse(.GET, "https://embed.gog.com/user/data/games", .{}, response);

    var web_api: GOGWebAPI = .init(mock_client);
    defer web_api.deinit();

    var parsedGames = try web_api.getGames(io, allocator);
    defer parsedGames.deinit(allocator);

    try std.testing.expectEqual(1, parsedGames.games.len);
}

test "Fetch Games - some owned" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    // `curl -L 'https://www.gog.com/en/game/astro_burn_demo' 2>/dev/null | grep '"sku":.*' | grep -o "[0-9]*"` - make sure you own this game (it is free)
    const owned_game: u32 = 1182721388;
    const fake_game_id: u32 = 1;

    var mock_client = http.mock_client.init(io, allocator, .default);
    const owned_games: GOGOwnedGames = .{ .owned = &.{ owned_game, fake_game_id } };
    const formatted_body = std.json.fmt(owned_games, .{});

    // will get freed in `web_api`
    const response: http.response.Response = .{
        .allocator = allocator,
        .body = try std.fmt.allocPrint(allocator, "{f}", .{formatted_body}),
        .status = .ok,
    };

    try mock_client.registerMockResponse(.GET, "https://embed.gog.com/user/data/games", .{}, response);

    var web_api: GOGWebAPI = .init(mock_client);
    defer web_api.deinit();

    var parsedGames = try web_api.getGames(io, allocator);
    defer parsedGames.deinit(allocator);

    try std.testing.expectEqual(1, parsedGames.games.items.len);
}
