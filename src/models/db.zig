const std = @import("std");
const fr = @import("fridge");

const DATABASE_NAME = "playday.db";

pub fn getConnection(allocator: std.mem.Allocator, io: std.Io) !*fr.Session {
    const session = try allocator.create(fr.Session);

    session.* = try fr.Session.open(fr.SQLite3, allocator, io, .{ .filename = DATABASE_NAME });
    return session;
}

pub fn deinit(session: *fr.Session, allocator: std.mem.Allocator) void {
    session.deinit();

    allocator.destroy(session);
}
