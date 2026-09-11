pub const LibraryData = @This();

game_id: []const u8,
library: Library,

const Library = union(enum) {
    steam: SteamData,
};

const SteamData = struct {};
