const std = @import("std");

pub const Response = @This();

body: []u8,
status: std.http.Status,
allocator: std.mem.Allocator,

pub fn deinit(self: *Response) void {
    self.allocator.free(self.body);

    self.* = undefined;
}

pub fn statusName(status: std.http.Status) ?[]const u8 {
    const enum_info = @typeInfo(std.http.Status).@"enum";
    const value = @intFromEnum(status);

    inline for (enum_info.fields) |field| {
        if (field.value == value) {
            return field.name;
        }
    }

    return null;
}
