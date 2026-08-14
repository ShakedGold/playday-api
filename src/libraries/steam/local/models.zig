const std = @import("std");

const LibraryFolder = struct {
    path: []u8,
};

pub const LibraryFolders = struct {
    libraryfolders: std.StringHashMap(LibraryFolder),
};

const AppState = struct {
    appid: u32,
};

pub const AppManifest = struct {
    AppState: AppState,
};
