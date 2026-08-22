const std = @import("std");

const http = @import("http");
const models = @import("models");

const metadata = @import("root.zig");

const log = std.log.scoped(.steam_store_metadata);

pub const SteamStoreMetadata = @This();

const LOGO_URL_FORMAT = "https://cdn.cloudflare.steamstatic.com/steam/apps/{[id]s}/logo.png";
const HERO_URL_FORMAT = "https://shared.steamstatic.com/store_item_assets/steam/apps/{[id]s}/library_hero.jpg";
const GRID_URL_FORMAT = "https://shared.steamstatic.com/store_item_assets/steam/apps/{[id]s}/library_600x900.jpg";
const STORE_PAGE_FORMAT = "https://store.steampowered.com/api/appdetails?appids={[id]s}&cc=us&l=en";

client: http.client.Client,

const SteamStoreResponse = struct {
    short_description: []const u8,
};

const SteamStoreRefresher = struct {
    client: *http.client.Client,
    game: *models.game.Game,
    allocator: std.mem.Allocator,
    io: std.Io,
    game_page: ?std.json.Parsed(SteamStoreResponse) = null,

    pub fn init(self: *@This()) metadata.MetadataRefresher {
        return .{
            .game = self.game,
            .io = self.io,
            .allocator = self.allocator,
            .client = self.client,
            .this = @ptrCast(self),

            .refreshDescriptionFn = refreshDescription,
            .refreshGridFn = refreshGrid,
            .refreshHeroFn = refreshHero,
            .refreshLogoFn = refreshLogo,
            .refreshIconFn = refreshIcon,
            .deinitFn = deinitFunc,
        };
    }

    pub fn deinitFunc(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        if (self.game_page) |game_page| game_page.deinit();

        self.allocator.destroy(self);
    }

    pub fn refreshLogo(ctx: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        var response = self.client.get(LOGO_URL_FORMAT, .{ .id = self.game.id }) catch return error.RequestFailed;

        if (response.status == .ok) {
            if (self.game.logo) |logo| self.allocator.free(logo);
            self.game.logo = response.body;
        } else {
            response.deinit();
        }
    }

    pub fn refreshHero(ctx: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        var response = self.client.get(HERO_URL_FORMAT, .{ .id = self.game.id }) catch return error.RequestFailed;

        if (response.status == .ok) {
            if (self.game.hero) |hero| self.allocator.free(hero);
            self.game.hero = response.body;
        } else {
            response.deinit();
        }
    }

    pub fn refreshGrid(ctx: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        var response = self.client.get(GRID_URL_FORMAT, .{ .id = self.game.id }) catch return error.RequestFailed;

        if (response.status == .ok) {
            if (self.game.grid) |grid| self.allocator.free(grid);
            self.game.grid = response.body;
        } else {
            response.deinit();
        }
    }

    pub fn refreshIcon(ctx: *anyopaque) !void {
        _ = ctx; // autofix
        return error.NotSupported;
    }

    fn refreshGamePage(self: *SteamStoreRefresher) !void {
        var response = self.client.get(STORE_PAGE_FORMAT, .{ .id = self.game.id }) catch return error.RequestFailed;
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

        const app = root.value.object.get(self.game.id) orelse {
            log.err("Game id not found in json object ({s})", .{self.game.id});

            return error.NotFound;
        };

        if (!app.object.get("success").?.bool) {
            log.err("Steam responded with success != true (success == {}) for game: {s}", .{ app.object.get("success").?, self.game.name });

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

    pub fn refreshDescription(ctx: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        if (self.game_page == null) {
            try self.refreshGamePage();
        }

        if (self.game.description) |description| {
            self.allocator.free(description);
        }

        self.game.description = self.allocator.dupe(u8, self.game_page.?.value.short_description) catch |err| {
            log.err("Failed to dupe description: {}", .{err});

            return error.NotFound;
        };
    }
};

pub fn init(io: std.Io, allocator: std.mem.Allocator) !SteamStoreMetadata {
    return .{
        .client = .init(io, allocator),
    };
}

pub fn deinit(self: *SteamStoreMetadata) void {
    self.client.deinit();

    self.* = undefined;
}

pub fn Refresher(parent: *SteamStoreMetadata, game: *models.game.Game, io: std.Io, allocator: std.mem.Allocator) metadata.MetadataRefresher {
    const refresher = allocator.create(SteamStoreRefresher) catch @panic("Failed to allocate SteamStoreRefresher");
    refresher.* = .{
        .allocator = allocator,
        .game = game,
        .io = io,
        .client = &parent.client,
    };

    return refresher.init();
}
