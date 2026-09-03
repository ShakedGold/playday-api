const std = @import("std");

const response = @import("response.zig");

const log = std.log.scoped(.http_client);

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

const HttpOptions = struct {
    extra_headers: []const std.http.Header,
    body: ?[]const u8 = null,

    pub const empty: HttpOptions = .{
        .extra_headers = &.{},
    };
};

/// The response needs to be `.deinit()` by the caller
pub fn fetch(self: *Client, method: std.http.Method, comptime format: []const u8, args: anytype, options: HttpOptions) !response.Response {
    log.debug("Fetching: " ++ format, args);

    var body = std.Io.Writer.Allocating.init(self.allocator);
    defer body.deinit();

    const url = try std.fmt.allocPrint(self.allocator, format, args);
    defer self.allocator.free(url);

    const uri = try std.Uri.parse(url);

    const clientResponse = try self.client.fetch(.{
        .method = method,
        .location = .{ .uri = uri },
        .response_writer = &body.writer,
        .payload = options.body,
        .extra_headers = options.extra_headers,
    });
    try body.writer.flush();

    const slice = try body.toOwnedSlice();

    return .{
        .body = slice,
        .status = clientResponse.status,
        .allocator = self.allocator,
    };
}

pub fn get(self: *Client, comptime format: []const u8, args: anytype, options: HttpOptions) !response.Response {
    return self.fetch(.GET, format, args, options);
}

pub fn post(self: *Client, comptime format: []const u8, args: anytype, options: HttpOptions) !response.Response {
    var opts = options;

    // On a POST requst, a body is required
    if (opts.body == null) {
        opts.body = &.{};
    }

    return self.fetch(.POST, format, args, opts);
}

pub fn deinit(self: *Client) void {
    self.client.deinit();

    self.* = undefined;
}
