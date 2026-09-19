const std = @import("std");

const models = @import("models");
const steam = @import("steam");

pub const Library = union(enum) {
    steam: steam.library.SteamLibrary,

    pub fn init(
        provider_type: std.meta.Tag(Library),
        args: anytype,
    ) Library {
        return switch (provider_type) {
            inline else => |tag| {
                const name = @tagName(tag);
                const LibraryNameType = @FieldType(Library, name);

                return @unionInit(
                    Library,
                    name,
                    @call(.auto, LibraryNameType.init, args),
                );
            },
        };
    }

    pub fn deinit(self: *Library) void {
        switch (self.*) {
            inline else => |*library| library.deinit(),
        }
    }

    pub fn getGames(
        self: *Library,
        io: std.Io,
        allocator: std.mem.Allocator,
    ) ![]?models.game.Game {
        return switch (self.*) {
            inline else => |*library| library.getGames(io, allocator),
        };
    }
};
