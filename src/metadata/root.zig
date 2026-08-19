const std = @import("std");

const models = @import("models");

const SteamStoreProvider = @import("steam_store.zig");

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

    pub fn getMetadata(
        self: *MetadataProvider,
        id: []u8,
    ) !models.extra_metadata.ExtraGameMetadata {
        return switch (self.*) {
            inline else => |*tag| {
                return tag.getMetadata(id);
            },
        };
    }
};
