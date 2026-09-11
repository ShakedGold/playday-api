const std = @import("std");

const fridge = @import("fridge");

const db = @import("root.zig");
const LibraryData = @import("library_data.zig");
const Metadata = @import("metadata.zig");

pub const Game = @This();

id: []u8,
name: []u8,
playtime: u32,
last_played: ?u64,
installed_location: ?[]u8 = null,

fn getMetadata(self: *@This(), session: fridge.Session) !?Metadata {
    return session.query(Metadata).get(self.id);
}

fn getLibraryData(self: *@This(), session: fridge.Session) !?LibraryData {
    return session.query(LibraryData).get(self.id);
}
