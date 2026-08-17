const std = @import("std");

const response = @import("response.zig");

pub const Client = @This();

client: std.http.Client,
allocator: std.mem.Allocator,
io: std.Io,

pub fn init(io: std.Io, allocator: std.mem.Allocator) Client {
    return .{
        .client = std.http.Client{ .allocator = allocator, .io = io },
        .allocator = allocator,
        .io = io,
    };
}

/// The response needs to be `.deinit()` by the caller
pub fn fetch(self: *Client, method: std.http.Method, comptime format: []const u8, args: anytype) !response.Response {
    var body = std.Io.Writer.Allocating.init(self.allocator);
    defer body.deinit();

    const url = try std.fmt.allocPrint(self.allocator, format, args);
    defer self.allocator.free(url);

    const uri = try std.Uri.parse(url);

    const clientResponse = try self.client.fetch(.{
        .method = method,
        .location = .{ .uri = uri },
        .response_writer = &body.writer,
    });
    try body.writer.flush();

    const slice = try body.toOwnedSlice();

    return .{
        .body = slice,
        .status = clientResponse.status,
        .allocator = self.allocator,
    };
}

pub fn get(self: *Client, comptime format: []const u8, args: anytype) !response.Response {
    return try self.fetch(.GET, format, args);
}

pub fn deinit(self: *Client) void {
    self.client.deinit();

    self.* = undefined;
}
