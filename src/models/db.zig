const std = @import("std");
const fr = @import("fridge");

const DATABASE_NAME = "playday.db";

var connection: ?fr.Session = null;

pub fn getConnection(allocator: std.mem.Allocator, io: std.Io) !*fr.Session {
    if (connection != null) {
        return &connection.?;
    }

    connection = try fr.Session.open(fr.SQLite3, allocator, io, .{ .filename = DATABASE_NAME });
    return &connection.?;
}
