const std = @import("std");

const http = @import("http");
const models = @import("models");

const metadata = @import("root.zig");

const log = std.log.scoped(.steam_store_metadata);

const LOGO_URL_FORMAT = "https://cdn.cloudflare.steamstatic.com/steam/apps/{[id]s}/logo.png";
const HERO_URL_FORMAT = "https://shared.steamstatic.com/store_item_assets/steam/apps/{[id]s}/library_hero.jpg";
const GRID_URL_FORMAT = "https://shared.steamstatic.com/store_item_assets/steam/apps/{[id]s}/library_600x900.jpg";
const STORE_PAGE_FORMAT = "https://store.steampowered.com/api/appdetails?appids={[id]s}&cc=us&l=en";
const STORE_PAGE_SEARCH_FORMAT = "https://store.steampowered.com/api/storesearch/?term={[name]s}&cc=us&l=en";

fn isUnreserved(c: u8) bool {
    return switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '-', '.', '_', '~' => true,
        else => false,
    };
}

io: std.Io,
allocator: std.mem.Allocator,
client: http.client.Client,

const SteamStoreResponse = struct {
    short_description: []const u8,
};

pub const SteamStore = struct {
    pub const Params = struct {};

    io: std.Io,
    allocator: std.mem.Allocator,
    client: http.client.Client,

    pub fn init(io: std.Io, allocator: std.mem.Allocator, params: Params) @This() {
        _ = params;

        return .{
            .io = io,
            .allocator = allocator,
            .client = .init(io, allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.client.deinit();
        self.* = undefined;
    }

    pub fn refresher(self: *@This(), game: *models.game.Game) SteamStoreRefresher {
        return .init(self.io, self.allocator, game);
    }
};

pub const SteamStoreRefresher = struct {
    allocator: std.mem.Allocator,
    io: std.Io,

    game: *models.game.Game,
    client: http.client.Client,
    game_page: ?std.json.Parsed(SteamStoreResponse) = null,

    pub fn init(
        io: std.Io,
        allocator: std.mem.Allocator,
        game: *models.game.Game,
    ) @This() {
        return .{
            .io = io,
            .allocator = allocator,
            .client = .init(io, allocator),
            .game = game,
        };
    }

    pub fn deinit(self: *@This()) void {
        if (self.game_page) |game_page| game_page.deinit();
        self.client.deinit();

        self.* = undefined;
    }

    fn getGameIdByName(self: *@This(), allocator: std.mem.Allocator) ![]u8 {
        var buf: [256]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buf);

        try std.Uri.Component.percentEncode(
            &writer,
            self.game.name,
            isUnreserved,
        );

        const encoded = writer.buffered();

        var response = try self.client.get(STORE_PAGE_SEARCH_FORMAT, .{ .name = encoded }, .empty);
        defer response.deinit();

        const root = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            response.body,
            .{},
        );
        defer root.deinit();

        const items = root.value.object.get("items") orelse {
            log.err("'items' not found in json object of store search ({s})", .{self.game.name});
            return error.NotFound;
        };

        if (items.array.items.len == 0) {
            log.err("{s} is not found in the steam store", .{self.game.name});
            return error.NotFound;
        }

        const itemId = items.array.items[0].object.get("id") orelse {
            log.err("item id for {s} is not found in the steam store", .{self.game.name});
            return error.NotFound;
        };

        return std.fmt.allocPrint(allocator, "{d}", .{itemId.integer});
    }

    fn getGameId(self: *@This(), allocator: std.mem.Allocator) ![]u8 {
        const tag = std.meta.activeTag(self.game.library.library);

        if (tag == .steam) {
            return allocator.dupe(u8, self.game.library.library.steam.appid);
        }

        return self.getGameIdByName(allocator);
    }

    pub fn refreshLogo(self: *@This()) !void {
        const id = try self.getGameId(self.allocator);
        defer self.allocator.free(id);

        var response = try self.client.get(LOGO_URL_FORMAT, .{ .id = id }, .empty);

        if (response.status == .ok) {
            if (self.game.metadata.logo) |logo| self.allocator.free(logo);
            self.game.metadata.logo = response.body;
        } else {
            response.deinit();
        }
    }

    pub fn refreshHero(self: *@This()) !void {
        const id = try self.getGameId(self.allocator);
        defer self.allocator.free(id);

        var response = try self.client.get(HERO_URL_FORMAT, .{ .id = id }, .empty);

        if (response.status == .ok) {
            if (self.game.metadata.hero) |hero| self.allocator.free(hero);
            self.game.metadata.hero = response.body;
        } else {
            response.deinit();
        }
    }

    pub fn refreshGrid(self: *@This()) !void {
        const id = try self.getGameId(self.allocator);
        defer self.allocator.free(id);

        var response = try self.client.get(GRID_URL_FORMAT, .{ .id = id }, .empty);

        if (response.status == .ok) {
            if (self.game.metadata.grid) |grid| self.allocator.free(grid);
            self.game.metadata.grid = response.body;
        } else {
            response.deinit();
        }
    }

    pub fn refreshIcon(self: *@This()) !void {
        _ = self; // autofix
        return error.NotSupported;
    }

    fn refreshGamePage(self: *@This()) !void {
        const id = try self.getGameId(self.allocator);
        defer self.allocator.free(id);

        var response = try self.client.get(STORE_PAGE_FORMAT, .{ .id = id }, .empty);
        defer response.deinit();

        if (response.status != .ok) {
            return error.RequestFailed;
        }

        const root = std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            response.body,
            .{},
        ) catch |err| {
            log.err("Failed parsing the json response from the steam store, {}", .{err});

            return error.NotFound;
        };
        defer root.deinit();

        const app = root.value.object.get(id) orelse {
            log.err("Game id not found in json object ({s})", .{id});

            return error.NotFound;
        };

        if (!app.object.get("success").?.bool) {
            log.err("Steam responded with success != true (success == {}) for game: {s}", .{ app.object.get("success").?.bool, self.game.game.name });

            return error.NotFound;
        }

        const data = app.object.get("data") orelse
            {
                log.err("Error while retrieving data on the app json object", .{});

                return error.NotFound;
            };

        const parsed = std.json.parseFromValue(
            SteamStoreResponse,
            self.allocator,
            data,
            .{ .ignore_unknown_fields = true },
        ) catch |err| {
            log.err("Failed parsing the steam store response from the app json object, {}", .{err});

            return error.NotFound;
        };

        self.game_page = parsed;
    }

    pub fn refreshDescription(self: *@This()) !void {
        if (self.game_page == null) {
            try self.refreshGamePage();
        }

        if (self.game.metadata.description) |description| {
            self.allocator.free(description);
        }

        self.game.metadata.description = self.allocator.dupe(u8, self.game_page.?.value.short_description) catch |err| {
            log.err("Failed to dupe description: {}", .{err});

            return error.NotFound;
        };
    }
};
