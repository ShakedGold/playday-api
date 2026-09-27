const std = @import("std");

pub const library = @import("gog_library.zig");
pub const web_api = @import("gog_web_api.zig");

test {
    std.testing.refAllDecls(@This());
}
