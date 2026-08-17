const std = @import("std");
const models = @import("models");
const log = std.log.scoped(.steam_macos);

/// The caller is reponsible to deallocate the path they receive
fn getSteamInstallationDir(io: std.Io, allocator: std.mem.Allocator, environment: *std.process.Environ.Map) !std.Io.Dir {
    const home_dir = environment.get("HOME") orelse return error.HomeDoesNotExist;
    const paths = [_][]const u8{ home_dir, "Library", "Application Support", "Steam" };

    const steam_path = try std.fs.path.join(allocator, &paths);
    defer allocator.free(steam_path);

    return std.Io.Dir.openDirAbsolute(io, steam_path, .{});
}

pub const SteamLocal = struct {
    environment: *std.process.Environ.Map,
    installed_path: std.Io.Dir,
    allocator: std.mem.Allocator,
    io: std.Io,

    pub fn init(io: std.Io, allocator: std.mem.Allocator, environ_map: *std.process.Environ.Map) !SteamLocal {
        return .{
            .environment = environ_map,
            .installed_path = try getSteamInstallationDir(io, allocator, environ_map),
            .allocator = allocator,
            .io = io,
        };
    }

    /// Returns the content of the libraryfolders.vdf file. allocates memory, the caller is responsible for freeing it.
    pub fn getLibraryFolders(self: *SteamLocal) ![]u8 {
        var libraryFoldersFile = try self.installed_path.openFile(self.io, "steamapps/libraryfolders.vdf", .{ .mode = .read_only });

        const stats = try libraryFoldersFile.stat(self.io);
        const fileBuffer = try self.allocator.alloc(u8, stats.size);

        const readAmount = try libraryFoldersFile.readPositionalAll(self.io, fileBuffer, 0);

        if (readAmount != stats.size) {
            return error.DidNotReadFullFile;
        }

        return fileBuffer;
    }

    pub fn deinit(self: *SteamLocal) void {
        self.* = undefined;
    }

    /// Returns an acf file using the appid and library path. allocates memory, the caller must call free
    pub fn getAppACF(self: *SteamLocal, libraryPath: []const u8, appid: u32) ![]u8 {
        const appManifestPath = try std.fmt.allocPrint(self.allocator, "steamapps/appmanifest_{d}.acf", .{appid});
        defer self.allocator.free(appManifestPath);

        log.debug("Reading: {s}/{s}", .{ libraryPath, appManifestPath });

        const directory = try std.Io.Dir.openDirAbsolute(self.io, libraryPath, .{});
        const appManifestFile = try directory.openFile(self.io, appManifestPath, .{ .mode = .read_only });

        const stats = try appManifestFile.stat(self.io);
        const fileBuffer = try self.allocator.alloc(u8, stats.size);

        const readAmount = try appManifestFile.readPositionalAll(self.io, fileBuffer, 0);

        if (readAmount != stats.size) {
            return error.DidNotReadFullFile;
        }

        return fileBuffer;
    }

    pub fn run(self: *SteamLocal, game: *const models.game.Game) !void {
        const game_url = try std.fmt.allocPrint(
            self.allocator,
            "steam://run/{s}",
            .{game.id},
        );
        defer self.allocator.free(game_url);

        var child = try std.process.spawn(self.io, .{
            .argv = &.{
                "open",
                game_url,
            },
            .stderr = .ignore,
            .stdin = .ignore,
            .stdout = .ignore,
        });

        _ = try child.wait(self.io);
    }
};
