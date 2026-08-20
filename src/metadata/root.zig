const std = @import("std");

const http = @import("http");
const models = @import("models");

const SteamStoreProvider = @import("steam_store.zig");

pub const MetadataRefresher = struct {
    game: *models.game.Game,
    allocator: std.mem.Allocator,
    io: std.Io,
    client: *http.client.Client,
    this: *anyopaque,

    refreshLogoFn: *const fn (self: *anyopaque) error{ RequestFailed, NotSupported, NotFound }!void,
    refreshHeroFn: *const fn (self: *anyopaque) error{ RequestFailed, NotSupported, NotFound }!void,
    refreshGridFn: *const fn (self: *anyopaque) error{ RequestFailed, NotSupported, NotFound }!void,
    refreshIconFn: *const fn (self: *anyopaque) error{ RequestFailed, NotSupported, NotFound }!void,
    refreshDescriptionFn: *const fn (self: *anyopaque) error{ RequestFailed, NotSupported, NotFound }!void,
    deinitFn: *const fn (self: *anyopaque) void,

    pub fn refreshLogo(self: *MetadataRefresher) !void {
        try self.refreshLogoFn(self.this);
    }
    pub fn refreshHero(self: *MetadataRefresher) !void {
        try self.refreshHeroFn(self.this);
    }
    pub fn refreshGrid(self: *MetadataRefresher) !void {
        try self.refreshGridFn(self.this);
    }
    pub fn refreshIcon(self: *MetadataRefresher) !void {
        try self.refreshIconFn(self.this);
    }
    pub fn refreshDescription(self: *MetadataRefresher) !void {
        try self.refreshDescriptionFn(self.this);
    }
    pub fn deinit(self: *MetadataRefresher) void {
        self.deinitFn(self.this);
    }
};

pub const MetadataProvider = union(enum) {
    steam_store: SteamStoreProvider,

    pub fn init(
        io: std.Io,
        allocator: std.mem.Allocator,
        provider_type: std.meta.Tag(MetadataProvider),
    ) !MetadataProvider {
        return switch (provider_type) {
            inline else => |comptime_tag| {
                const name = @tagName(comptime_tag);
                const Provider = @FieldType(MetadataProvider, name);

                return @unionInit(
                    MetadataProvider,
                    name,
                    try Provider.init(io, allocator),
                );
            },
        };
    }

    pub fn deinit(self: *MetadataProvider) void {
        return switch (self.*) {
            inline else => |*tag| {
                return tag.deinit();
            },
        };
    }

    pub fn refresher(
        self: *MetadataProvider,
        game: *models.game.Game,
        io: std.Io,
        allocator: std.mem.Allocator,
    ) MetadataRefresher {
        return switch (self.*) {
            inline else => |*provider| provider.Refresher(game, io, allocator),
        };
    }
};
