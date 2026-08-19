const std = @import("std");

const models = @import("models");
const http = @import("http");

pub const SteamStoreMetadata = @This();

client: http.client.Client,

const LOGO_URL_FORMAT = "https://cdn.cloudflare.steamstatic.com/steam/apps/{[id]s}/logo.png";
const HERO_URL_FORMAT = "https://shared.steamstatic.com/store_item_assets/steam/apps/{[id]s}/library_hero.jpg";
const GRID_URL_FORMAT = "https://shared.steamstatic.com/store_item_assets/steam/apps/{[id]s}/library_600x900.jpg";

pub fn init(io: std.Io, allocator: std.mem.Allocator) !SteamStoreMetadata {
    return .{
        .client = .init(io, allocator),
    };
}

pub fn deinit(self: *SteamStoreMetadata) void {
    self.client.deinit();

    self.* = undefined;
}

/// Retrieves the game logo from the steam metatdata api, caller is responsible for calling freeing the body
pub fn getMetadata(self: *SteamStoreMetadata, gameId: []u8) !models.extra_metadata.ExtraGameMetadata {
    const response = try self.client.get(LOGO_URL_FORMAT, .{ .id = gameId });
    _ = response;

    return .{ .id = try self.client.allocator.dupe(u8, gameId) };
}
