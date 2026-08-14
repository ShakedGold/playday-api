const std = @import("std");

pub const Response = @This();

body: []u8,
status: std.http.Status,
allocator: std.mem.Allocator,

pub fn deinit(self: *Response) void {
    self.allocator.free(self.body);

    self.* = undefined;
}
