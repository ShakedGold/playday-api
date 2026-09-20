const web_api = @import("gog_web_api.zig");

pub const GOGLibrary = struct {
    gog_web_api: web_api.GOGWebAPI,
};
