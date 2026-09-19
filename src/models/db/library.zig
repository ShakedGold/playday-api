const std = @import("std");

const fr = @import("fridge");
const libraries = @import("libraries");

const db = @import("root.zig");

pub const LibraryData = @This();

id: []const u8,
library: Library,

pub fn insert(self: *@This(), io: std.Io, allocator: std.mem.Allocator) !void {
    var connection = try db.getConnection(allocator, io);
    defer db.deinit(connection, allocator);

    try ensureTable(connection);

    _ = try connection.insert(@This(), self.*);
}

pub fn update(self: *@This(), io: std.Io, allocator: std.mem.Allocator) !void {
    const connection = try db.getConnection(allocator, io);
    defer db.deinit(connection, allocator);

    try ensureTable(connection);

    var query = try connection.query(@This()).where("id", self.id).update(self.*).prepare();
    defer query.deinit();

    try query.exec();
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    self.library.deinit(allocator);
}

pub fn ensureTable(connection: *fr.Session) !void {
    try connection.conn.execAll(
        \\ CREATE TABLE IF NOT EXISTS library(
        \\ id TEXT PRIMARY KEY,
        \\ library JSON
        \\ );
    );
}

pub fn clone(self: *const @This(), allocator: std.mem.Allocator) !@This() {
    return .{
        .id = self.id,
        .library = try self.library.clone(allocator),
    };
}

// Because this is a tagged union and each field can have different fields within it.
// The way we save it to the sqlite db is via JSON, this sucks. we probably need to migrate
// to a No-SQL db in the future to allow this flexibility
// NOTE: currently because this IS still just json in the DB, we cannot save blobs of data
// (such as images) in here since it will tank the performance while loading
const Library = union(enum) {
    steam: SteamLibrary,

    pub fn clone(self: *const @This(), allocator: std.mem.Allocator) !@This() {
        return switch (self.*) {
            inline else => |payload, tag| @unionInit(@This(), @tagName(tag), try payload.clone(allocator)),
        };
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        return switch (self.*) {
            inline else => |*tag| tag.deinit(allocator),
        };
    }

    pub fn run(self: *const @This(), io: std.Io, allocator: std.mem.Allocator) !void {
        switch (self.*) {
            inline else => |tag| try tag.run(io, allocator),
        }
    }
};

const SteamLibrary = struct {
    appid: []u8,

    pub fn clone(self: *const @This(), allocator: std.mem.Allocator) !@This() {
        return .{
            .appid = try allocator.dupe(u8, self.appid),
        };
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.appid);

        self.* = undefined;
    }

    pub fn run(self: *const @This(), io: std.Io, allocator: std.mem.Allocator) !void {
        try libraries.steam.local.SteamLocalType.run(io, allocator, self.appid);
    }
};
