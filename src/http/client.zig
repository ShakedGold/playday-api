const std = @import("std");
const builtin = @import("builtin");

const http_client = @import("http_client.zig");
const mock_client = @import("mock_client.zig");
const response = @import("response.zig");

const log = std.log.scoped(.client);

pub const HTTPOptions = struct {
    extra_headers: []const std.http.Header = &.{},
    body: ?[]const u8 = null,
    redirect_behavior: ?std.http.Client.Request.RedirectBehavior = null,

    pub const empty: HTTPOptions = .{};
};

pub const ClientType = if (builtin.is_test) mock_client.MockClient else http_client.HTTPClient;

pub const Client = struct {
    client: ClientType,

    pub fn init(client: ClientType) @This() {
        return .{ .client = client };
    }

    /// The response needs to be `.deinit()` by the caller
    pub fn fetch(self: *@This(), comptime method: std.http.Method, comptime format: []const u8, args: anytype, options: HTTPOptions) !response.Response {
        return self.client.fetch(method, format, args, options);
    }

    pub fn get(self: *@This(), comptime format: []const u8, args: anytype, options: HTTPOptions) !response.Response {
        return self.client.get(format, args, options);
    }

    pub fn post(self: *@This(), comptime format: []const u8, args: anytype, options: HTTPOptions) !response.Response {
        return self.client.post(format, args, options);
    }

    pub fn deinit(self: *@This()) void {
        self.client.deinit();
    }
};
