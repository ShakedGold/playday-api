const std = @import("std");
const builtin = @import("builtin");

const playday_vdf = @import("playday_vdf");
const dbModels = @import("models");
const models = @import("./models.zig");

const native_os = builtin.target.os.tag;

const Platform = switch (builtin.target.os.tag) {
    .linux => @import("steam_linux.zig").SteamLocal,
    .macos => @import("steam_macos.zig").SteamLocal,
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

    pub fn getInstalledGame(self: *SteamLocal, appid: u32) !struct { playday_vdf.Parsed(models.AppManifest), []const u8 } {
        var iterator = self.libraryFolders.value.libraryfolders.iterator();
        while (iterator.next()) |entry| {
            const acf = self.platform.getAppACF(entry.value_ptr.path, appid) catch |err| switch (err) {
                error.FileNotFound => continue,
                else => return err,
            };

            defer self.allocator.free(acf);

            const parsedAppManifest = try playday_vdf.parseFromSlice(models.AppManifest, self.allocator, acf, .{});
            if (parsedAppManifest.value.AppState.appid == appid) return .{ parsedAppManifest, entry.value_ptr.path };
        }

        return error.GameNotFound;
    }

    pub fn run(self: *SteamLocal, game: *const dbModels.game.Game) !void {
        return self.platform.run(game);
    }
};
