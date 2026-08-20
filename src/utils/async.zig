const std = @import("std");

pub fn BoundedConcurrency(comptime T: type) type {
    return struct {
        batch_size: usize,
        items: []T,

        pub fn processRange(self: BoundedConcurrency(T), io: std.Io, function: anytype, args: anytype, range: struct { start: usize = 0, length: usize = std.math.maxInt(usize) }) !void {
            var start = @max(0, range.start);
            const length = @min(self.items.len, range.length);

            if (start > self.items.len or length < 0) {
                return error.InvalidRange;
            }

            while (start < length) {
                const end = @min(start + self.batch_size, length);

                var group: std.Io.Group = .init;
                errdefer group.cancel(io);

                for (self.items[start..end], 0..) |*item, index| {
                    try group.concurrent(io, function, args ++ .{ item, start + index });
                }

                try group.await(io);

                start = end;
            }
        }

        pub fn processAll(self: BoundedConcurrency(T), io: std.Io, function: anytype, args: anytype) !void {
            try self.processRange(io, function, args, .{});
        }
    };
}
