const std = @import("std");

const http_client = @import("http_client.zig");
const response = @import("response.zig");
const wrapper_client = @import("client.zig");

const log = std.log.scoped(.mock_client);

pub const MockClient = @This();

const MockRequest = struct {
    method: std.http.Method,
    url: []const u8,
    response: response.Response,
};

pub fn MockJsonResponse(comptime PayloadType: type) type {
    return struct {
        value: PayloadType,
        status: std.http.Status = .ok,

        pub fn getResponse(self: @This(), allocator: std.mem.Allocator) response.Response {
            const formatted_body = std.json.fmt(self.value, .{});
            const body =
                std.fmt.allocPrint(allocator, "{f}", .{formatted_body}) catch
                    std.debug.panic("Cannot format body of {s}, data: {any}", .{ @typeName(PayloadType), self.value });

            return .{
                .allocator = allocator,
                .body = body,
                .status = self.status,
            };
        }
    };
}

allocator: std.mem.Allocator,
io: std.Io,
mockResponses: std.ArrayList(MockRequest),
client: ?http_client.HTTPClient = null,

pub const MockClientOptions = struct {
    create_client: bool = false,

    pub const default: @This() = .{ .create_client = true };
};

pub fn init(io: std.Io, allocator: std.mem.Allocator, options: MockClientOptions) @This() {
    return .{
        .allocator = allocator,
        .io = io,
        .mockResponses = .empty,
        .client = if (options.create_client) .init(io, allocator, .{}) else null,
    };
}

pub fn registerMockResponse(self: *@This(), method: std.http.Method, comptime format: []const u8, args: anytype, resp: response.Response) !void {
    const url = try std.fmt.allocPrint(self.allocator, format, args);

    const request: MockRequest = .{ .url = url, .method = method, .response = resp };
    return self.mockResponses.append(self.allocator, request);
}

/// The response needs to be `.deinit()` by the caller
pub fn fetch(self: *@This(), comptime method: std.http.Method, comptime format: []const u8, args: anytype, options: wrapper_client.HTTPOptions) !response.Response {
    const url = try std.fmt.allocPrint(self.allocator, format, args);
    defer self.allocator.free(url);

    std.debug.print("[fetch] url={s}\n", .{url});

    for (self.mockResponses.items, 0..) |mock_request, index| {
        if (method != mock_request.method) {
            continue;
        }

        if (std.mem.find(u8, url, mock_request.url) == null) {
            continue;
        }

        // Remove from list, since the response will most likely be deinit-ed
        const removed = self.mockResponses.swapRemove(index);
        self.allocator.free(removed.url);

        return mock_request.response;
    }

    // No request match has been found
    if (self.client) |*client| {
        return client.fetch(method, format, args, options);
    }

    std.debug.panic("Unmatched request! method={s}, URL={s}", .{ @tagName(method), url });
}

pub fn get(self: *@This(), comptime format: []const u8, args: anytype, options: wrapper_client.HTTPOptions) !response.Response {
    return self.fetch(.GET, format, args, options);
}

pub fn post(self: *@This(), comptime format: []const u8, args: anytype, options: wrapper_client.HTTPOptions) !response.Response {
    var opts = options;

    // On a POST requst, a body is required
    if (opts.body == null) {
        opts.body = &.{};
    }

    return self.fetch(.POST, format, args, opts);
}

pub fn deinit(self: *@This()) void {
    for (self.mockResponses.items) |request| {
        self.allocator.free(request.url);
    }
    self.mockResponses.deinit(self.allocator);

    if (self.client) |*client| {
        client.deinit();
    }

    self.* = undefined;
}
