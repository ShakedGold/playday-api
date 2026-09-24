const browser = @import("browser.zig");
pub const Browser = browser.Browser;
pub const Session = browser.Session;
pub const EmptyMessageResponse = browser.EmptyMessageResponse;

test {
    _ = @import("browser.zig");
}
