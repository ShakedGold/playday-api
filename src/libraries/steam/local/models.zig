const std = @import("std");

const LibraryFolder = struct {
    path: []u8,
};

pub const LibraryFolders = struct {
    libraryfolders: std.StringHashMap(LibraryFolder),
};

const AppState = struct {
    appid: u32,
    installdir: []const u8,
    LastPlayed: u64,
};

pub const AppManifest = struct {
    AppState: AppState,

    pub fn getInstallFullPath(self: *AppManifest, allocator: std.mem.Allocator, directory: []const u8) ![]u8 {
        return std.fmt.allocPrint(allocator, "{s}/steamapps/common/{s}", .{ directory, self.AppState.installdir });
    }
};
