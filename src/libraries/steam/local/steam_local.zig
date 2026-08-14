const std = @import("std");
const builtin = @import("builtin");

const playday_vdf = @import("playday_vdf");
const models = @import("./models.zig");

const native_os = builtin.target.os.tag;

const Platform = switch (builtin.target.os.tag) {
    .linux => @import("steam_linux.zig").SteamLocal,
    else => @compileError("Unsupported OS"),
};

pub const SteamLocal = struct {
    platform: Platform,
    io: std.Io,
    allocator: std.mem.Allocator,
    libraryFolders: playday_vdf.Parsed(models.LibraryFolders) = undefined,

    pub fn init(io: std.Io, allocator: std.mem.Allocator, environ_map: *std.process.Environ.Map) !SteamLocal {
        var local: SteamLocal = .{
            .platform = try Platform.init(io, allocator, environ_map),
            .io = io,
            .allocator = allocator,
        };

        local.libraryFolders = try local.getLibraryFolders();

        return local;
    }

    pub fn deinit(self: *SteamLocal) void {
        self.platform.deinit();
        self.libraryFolders.deinit();

        self.* = undefined;
    }

    /// The caller is responsible for calling deinit on the returned parsed field
    fn getLibraryFolders(self: *SteamLocal) !playday_vdf.Parsed(models.LibraryFolders) {
        const libraryFoldersContent = try self.platform.getLibraryFolders();
        defer self.allocator.free(libraryFoldersContent);

        return playday_vdf.parseFromSlice(models.LibraryFolders, self.allocator, libraryFoldersContent, .{});
    }

    pub fn getInstalledGame(self: *SteamLocal, appid: u32) !playday_vdf.Parsed(models.AppManifest) {
        var iterator = self.libraryFolders.value.libraryfolders.iterator();
        while (iterator.next()) |entry| {
            const acf = try self.platform.getAppACF(entry.value_ptr.path, appid);
            defer self.allocator.free(acf);

            const parsedAppManifest = try playday_vdf.parseFromSlice(models.AppManifest, self.allocator, acf, .{});
            if (parsedAppManifest.value.AppState.appid == appid) return parsedAppManifest;
        }

        return error.GameNotFound;
    }
};
