const std = @import("std");

const http = @import("http");
const models = @import("models");

const igdb = @import("igdb.zig");
const steam_store = @import("steam_store.zig");

const Refresher = union(enum) {
    steam_store: steam_store.SteamStoreRefresher,
    igdb: igdb.IGDBRefresher,

    pub fn deinit(self: *@This()) void {
        switch (self.*) {
            inline else => |*tag| {
                tag.deinit();
            },
        }
    }

    pub fn refreshLogo(self: *@This()) !void {
        switch (self.*) {
            inline else => |*tag| {
                try tag.refreshLogo();
                try tag.game.update(tag.io, tag.allocator);
            },
        }
    }

    pub fn refreshHero(self: *@This()) !void {
        switch (self.*) {
            inline else => |*tag| {
                try tag.refreshHero();
                try tag.game.update(tag.io, tag.allocator);
            },
        }
    }

    pub fn refreshGrid(self: *@This()) !void {
        switch (self.*) {
            inline else => |*tag| {
                try tag.refreshGrid();
                try tag.game.update(tag.io, tag.allocator);
            },
        }
    }

    pub fn refreshIcon(self: *@This()) !void {
        switch (self.*) {
            inline else => |*tag| {
                try tag.refreshIcon();
                try tag.game.update(tag.io, tag.allocator);
            },
        }
    }

    pub fn refreshDescription(self: *@This()) !void {
        switch (self.*) {
            inline else => |*tag| {
                try tag.refreshDescription();
                try tag.game.update(tag.io, tag.allocator);
            },
        }
    }
};

pub const MetadataProvider = union(enum) {
    steam_store: steam_store.SteamStore,
    igdb: igdb.IGDB,

    pub fn init(
        io: std.Io,
        allocator: std.mem.Allocator,
        comptime provider_type: std.meta.Tag(MetadataProvider),
        params: Params(provider_type),
    ) @This() {
        return switch (provider_type) {
            inline else => |comptime_tag| {
                const name = @tagName(comptime_tag);
                const Provider = @FieldType(@This(), name);

                return @unionInit(
                    @This(),
                    name,
                    Provider.init(io, allocator, params),
                );
            },
        };
    }

    pub fn deinit(self: *@This()) void {
        return switch (self.*) {
            inline else => |*tag| {
                return tag.deinit();
            },
        };
    }

    pub fn refresher(self: *@This(), game: *models.game.Game) Refresher {
        return switch (self.*) {
            inline else => |*provider, tag| {
                return @unionInit(
                    Refresher,
                    @tagName(tag),
                    provider.refresher(game),
                );
            },
        };
    }

    fn Params(comptime provider_type: std.meta.Tag(MetadataProvider)) type {
        const name = @tagName(provider_type);
        const Provider = @FieldType(@This(), name);

        return Provider.Params;
    }
};
