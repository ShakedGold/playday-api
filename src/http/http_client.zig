const std = @import("std");

const client_wrapper = @import("client.zig");
const response = @import("response.zig");

const log = std.log.scoped(.http_client);

pub const HTTPClient = @This();

client: std.http.Client,
allocator: std.mem.Allocator,
io: std.Io,

pub fn init(io: std.Io, allocator: std.mem.Allocator) @This() {
    return .{
        .client = std.http.Client{ .allocator = allocator, .io = io },
        .allocator = allocator,
        .io = io,
    };
}

/// The response needs to be `.deinit()` by the caller
pub fn fetch(self: *@This(), comptime method: std.http.Method, comptime format: []const u8, args: anytype, options: client_wrapper.HTTPOptions) !response.Response {
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
        .redirect_behavior = options.redirect_behavior,
    });
    try body.writer.flush();

    const slice = try body.toOwnedSlice();

    return .{
        .body = slice,
        .status = clientResponse.status,
        .allocator = self.allocator,
    };
}

pub fn get(self: *@This(), comptime format: []const u8, args: anytype, options: client_wrapper.HTTPOptions) !response.Response {
    return self.fetch(.GET, format, args, options);
}

pub fn post(self: *@This(), comptime format: []const u8, args: anytype, options: client_wrapper.HTTPOptions) !response.Response {
    var opts = options;

    // On a POST requst, a body is required
    if (opts.body == null) {
        opts.body = &.{};
    }

    return self.fetch(.POST, format, args, opts);
}

pub fn deinit(self: *@This()) void {
    self.client.deinit();

    self.* = undefined;
}
