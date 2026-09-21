const std = @import("std");
/// An empty response for the `sendMessage` method, if provided, a free is unnecessary
pub const EmptyMessageResponse = std.json.Value;
const builtin = @import("builtin");

const websocket = @import("websocket");

pub const browser_local = switch (builtin.target.os.tag) {
    .linux => @import("browser_linux.zig"),
    else => @compileError("Unsupported OS"),
};

const log = std.log.scoped(.browser);
pub const Browser = @This();

path: []const u8,
process: ?std.process.Child,
client: ?websocket.Client,
id: usize,

const CDPBrowserMethod = enum { getVersion };
const CDPPageMethod = enum { navigate, enable, frameNavigated, navigatedWithinDocument, frameStartedNavigating };
const CDPTargetMethod = enum { createTarget, attachToTarget, closeTarget };

const CDPMethod = union(enum) {
    browser: CDPBrowserMethod,
    page: CDPPageMethod,
    target: CDPTargetMethod,

    pub fn format(self: *const @This(), writer: *std.Io.Writer) !void {
        return switch (self.*) {
            inline else => |method| {
                const methodType = @tagName(std.meta.activeTag(self.*));
                try writer.print("{c}{s}", .{ std.ascii.toUpper(methodType[0]), methodType[1..] });

                switch (method) {
                    inline else => |tag| try writer.print(".{s}", .{@tagName(tag)}),
                }
            },
        };
    }
};

const CDPSession = struct {
    id: *usize,
    sessionId: []const u8,
    client: *?websocket.Client,

    pub fn sendMessage(
        self: *@This(),
        allocator: std.mem.Allocator,
        method: CDPMethod,
        params: anytype,
        response_method: ?CDPMethod,
        ResultType: type,
    ) !?std.json.Parsed(ResultType) {
        var buffer: [1024]u8 = undefined;
        var client = self.client.* orelse
            return error.UninitializedClient;

        var requestMessage: []u8 = undefined;
        if (@TypeOf(params) == @TypeOf(.{})) {
            requestMessage = try std.fmt.bufPrint(
                &buffer,
                \\{{"id":{d},"method":"{f}","sessionId":"{s}","params":{{}}}}
            ,
                .{ self.id.*, method, self.sessionId },
            );
        } else {
            requestMessage = try std.fmt.bufPrint(
                &buffer,
                \\{{"id":{d},"method":"{f}","sessionId":"{s}","params":{f}}}
            ,
                .{ self.id.*, method, self.sessionId, std.json.fmt(params, .{}) },
            );
        }

        return sendAndReceive(&client, self.id, requestMessage, response_method, allocator, ResultType);
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
    }

    pub fn getEvent(self: *@This(), allocator: std.mem.Allocator, response_method: ?CDPMethod, ResultType: type) !?std.json.Parsed(ResultType) {
        if (self.client.*) |*client| {
            return receive(client, allocator, response_method, ResultType);
        }

        return error.ClientNotInitialized;
    }
};

pub fn init(path: []const u8) @This() {
    return .{
        .id = 0,
        .path = path,
        .process = null,
        .client = null,
    };
}

pub fn launch(self: *@This(), io: std.Io, allocator: std.mem.Allocator) !void {
    log.debug("Launching chrome: {s}", .{self.path});
    self.process = try browser_local.launch(io, self.path);

    log.debug("Connecting to the CDP in", .{});
    self.client = try browser_local.connect(io, allocator);
}

pub fn close(self: *@This(), io: std.Io) void {
    var process = self.process orelse return;

    process.kill(io);
}

pub fn deinit(self: *@This(), io: std.Io) void {
    if (self.process) |_| {
        self.close(io);
    }

    if (self.client) |*client| {
        client.deinit();
    }
}

fn parseCDPMessage(client: *websocket.Client, allocator: std.mem.Allocator, message: websocket.Message, response_method: ?CDPMethod, ResultType: type) !?std.json.Parsed(ResultType) {
    log.debug("Message received: {s}", .{message.data});

    blk: switch (message.type) {
        .text, .binary => {
            // Validate errors
            const parsedError = std.json.parseFromSlice(
                struct {
                    id: usize,
                    @"error": struct { code: i32, message: []const u8 },
                },
                allocator,
                message.data,
                .{ .ignore_unknown_fields = true },
            ) catch null;

            if (parsedError) |err| {
                log.err("Error in request[id={d},code={d}]: {s}", .{ err.value.id, err.value.@"error".code, err.value.@"error".message });
                return error.ResponseError;
            }

            if (ResultType == EmptyMessageResponse) {
                return null;
            }

            // We need to first parse it
            const json_value = try std.json.parseFromSlice(
                std.json.Value,
                allocator,
                message.data,
                .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
            );
            defer json_value.deinit();

            const received_method = json_value.value.object.get("method");

            if (response_method) |r_method| {
                if (received_method) |method| {
                    const method_string = try std.fmt.allocPrint(allocator, "{f}", .{r_method});
                    defer allocator.free(method_string);

                    if (!std.mem.eql(u8, method.string, method_string)) {
                        return null;
                    }
                } else {
                    return null;
                }
            }

            return try std.json.parseFromSlice(
                ResultType,
                allocator,
                message.data,
                .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
            );
        },
        .ping => {
            try client.writePong(message.data);
            const nextMessage = try client.read() orelse return error.NoResponseInNextMessage;

            continue :blk nextMessage.type;
        },
        .pong => {},
        .close => {
            try client.close(.{});
            return error.ConnectionClosed;
        },
    }

    return null;
}

/// Creates a browser session, caller owns memory. should call `deinit`
pub fn createSession(self: *@This(), allocator: std.mem.Allocator) !CDPSession {
    const CreateTargetResponse = struct {
        result: struct {
            targetId: []const u8,
        },
    };

    const createTargetResponse = try self.sendMessage(
        allocator,
        .{ .target = .createTarget },
        .{ .url = "about:blank" },
        null,
        CreateTargetResponse,
    ) orelse return error.FailedToCreateTarget;
    defer createTargetResponse.deinit();

    const AttachTargetResponse = struct {
        params: struct {
            sessionId: []const u8,
        },
    };
    const attachTargetResponse = try self.sendMessage(
        allocator,
        .{ .target = .attachToTarget },
        .{
            .targetId = createTargetResponse.value.result.targetId,
            .flatten = true,
        },
        null,
        AttachTargetResponse,
    ) orelse return error.FailedToAttachToTarget;
    defer attachTargetResponse.deinit();

    self.id += 1;

    return .{
        .id = &self.id,
        .sessionId = try allocator.dupe(u8, attachTargetResponse.value.params.sessionId),
        .client = &self.client,
    };
}

fn receive(client: *websocket.Client, allocator: std.mem.Allocator, response_method: ?CDPMethod, ResultType: type) !?std.json.Parsed(ResultType) {
    const response = try client.read() orelse return error.NoResponse;
    defer client.done(response);

    return parseCDPMessage(client, allocator, response, response_method, ResultType);
}

fn sendAndReceive(client: *websocket.Client, id: *usize, message: []u8, response_method: ?CDPMethod, allocator: std.mem.Allocator, ResultType: type) !?std.json.Parsed(ResultType) {
    log.debug("Sending message: {s}", .{message});
    try client.write(message);

    id.* += 1;

    return receive(client, allocator, response_method, ResultType);
}

pub fn sendMessage(
    self: *@This(),
    allocator: std.mem.Allocator,
    method: CDPMethod,
    params: anytype,
    response_method: ?CDPMethod,
    ResultType: type,
) !?std.json.Parsed(ResultType) {
    var buffer: [1024]u8 = undefined;
    var client = self.client orelse
        return error.UninitializedClient;

    const requestMessage = try std.fmt.bufPrint(
        &buffer,
        \\{{"id":{d},"method":"{f}","params":{f}}}
    ,
        .{ self.id, method, std.json.fmt(params, .{}) },
    );

    return sendAndReceive(&client, &self.id, requestMessage, response_method, allocator, ResultType);
}

test "Launching the browser and connecting" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var browser: Browser = .init("/usr/bin/chromium-browser");
    defer browser.deinit(io);

    try browser.launch(io, allocator);
}

test "Sending a message to the browser" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var browser: Browser = .init("/usr/bin/chromium-browser");
    defer browser.deinit(io);

    try browser.launch(io, allocator);

    const GetVersionResponse = struct {
        result: struct {
            protocolVersion: []const u8,
            userAgent: []const u8,
        },
    };

    const response = try browser.sendMessage(allocator, .{ .browser = .getVersion }, .{}, null, GetVersionResponse) orelse unreachable;
    defer response.deinit();
}

test "Create a new session" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var browser: Browser = .init("/usr/bin/chromium-browser");
    defer browser.deinit(io);

    try browser.launch(io, allocator);

    var session = try browser.createSession(allocator);
    defer session.deinit(allocator);

    _ = try session.sendMessage(
        allocator,
        .{ .page = .enable },
        .{},
        null,
        EmptyMessageResponse,
    );

    _ = try session.sendMessage(
        allocator,
        .{ .page = .navigate },
        .{ .url = "https://google.com" },
        null,
        EmptyMessageResponse,
    );
}

test "Detect redirections" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const GOG_AUTH_URL =
        \\https://auth.gog.com/auth
        \\?client_id=46899977096215655
        \\&redirect_uri=https%3A%2F%2Fembed.gog.com%2Fon_login_success%3Forigin%3Dclient
        \\&response_type=code
        \\&layout=client2
    ;
    const timeout = std.Io.Duration.fromSeconds(25);

    var browser: Browser = .init("/usr/bin/chromium-browser");
    defer browser.deinit(io);

    try browser.launch(io, allocator);

    var session = try browser.createSession(allocator);
    defer session.deinit(allocator);

    _ = try session.sendMessage(
        allocator,
        .{ .page = .enable },
        .{},
        null,
        EmptyMessageResponse,
    );

    _ = try session.sendMessage(
        allocator,
        .{ .page = .navigate },
        .{ .url = GOG_AUTH_URL },
        null,
        EmptyMessageResponse,
    );

    const FrameNavigatedResult = struct {
        params: struct {
            frame: struct {
                id: []const u8,
                url: []const u8,
            },
        },
    };

    const start = std.Io.Timestamp.now(io, .awake);
    while (true) {
        const elapsed = start.untilNow(io, .awake);

        if (timeout.toMilliseconds() - elapsed.toMilliseconds() < 0) {
            return error.Timeout;
        }

        const frame_event = try session.getEvent(
            allocator,
            .{ .page = .frameNavigated },
            FrameNavigatedResult,
        );

        if (frame_event) |event| {
            defer event.deinit();

            if (std.mem.startsWith(
                u8,
                event.value.params.frame.url,
                "https://embed.gog.com/on_login_success",
            )) {
                break;
            }
        }
    }
}
