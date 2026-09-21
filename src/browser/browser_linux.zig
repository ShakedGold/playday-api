const std = @import("std");

const http = @import("http");
const websocket = @import("websocket");

const log = std.log.scoped(.browser_linux);

const CHROME_PORT = 9222;
const CHROME_ARGS: []const []const u8 = &.{
    std.fmt.comptimePrint("--remote-debugging-port={d}", .{CHROME_PORT}),
    "--user-data-dir=/tmp/chrome-cdp",
};
const CHROME_CDP_SETUP_URL = std.fmt.comptimePrint("http://127.0.0.1:{d}/json/version", .{CHROME_PORT});

const HTTPResponseCDP = struct {
    webSocketDebuggerUrl: []const u8,
};

fn suffixAfterHost(url: []const u8) ![]const u8 {
    const scheme_end = std.mem.indexOf(u8, url, "://") orelse
        return error.InvalidUrl;

    const authority_start = scheme_end + 3;

    const slash_index = std.mem.indexOfScalarPos(
        u8,
        url,
        authority_start,
        '/',
    ) orelse return error.MissingPath;

    return url[slash_index..];
}

pub fn launch(io: std.Io, path: []const u8) !std.process.Child {
    return std.process.spawn(io, .{
        .argv = .{path} ++ CHROME_ARGS,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
}

/// Connect a web socket client to the open browser, caller owns the client and should call .deinit o it
pub fn connect(io: std.Io, allocator: std.mem.Allocator) !websocket.Client {
    var client: http.client.Client = .init(io, allocator);
    defer client.deinit();

    var connected: bool = false;
    var response: http.response.Response = undefined;
    defer response.deinit();

    while (!connected) {
        response = client.get(CHROME_CDP_SETUP_URL, .{}, .empty) catch |err| switch (err) {
            std.http.Client.ConnectError.ConnectionRefused => continue,
            else => return err,
        };

        connected = true;
    }

    if (response.status != .ok) {
        log.err("response failed with status: {any}({d})", .{ http.response.statusName(response.status), response.status });
        return error.CDPRequestFailed;
    }

    const parsedHTTPResponse = try std.json.parseFromSlice(
        HTTPResponseCDP,
        allocator,
        response.body,
        .{ .ignore_unknown_fields = true },
    );
    defer parsedHTTPResponse.deinit();

    log.debug("WebSocket Url: {s}", .{parsedHTTPResponse.value.webSocketDebuggerUrl});

    const ws_path = try suffixAfterHost(parsedHTTPResponse.value.webSocketDebuggerUrl);
    var ws_client: websocket.Client = try .init(io, allocator, .{
        .port = CHROME_PORT,
        .host = "127.0.0.1",
    });
    try ws_client.handshake(ws_path, .{});

    return ws_client;
}
