const std = @import("std");

pub fn uuidV4(io: std.Io) [36]u8 {
    var uuid: [16]u8 = undefined;
    io.random(&uuid);

    // UUID v4 version bits.
    uuid[6] = (uuid[6] & 0x0f) | 0x40;

    // RFC variant bits.
    uuid[8] = (uuid[8] & 0x3f) | 0x80;

    var result: [36]u8 = undefined;
    const hex = "0123456789abcdef";
    var index: usize = 0;

    for (uuid, 0..) |byte, i| {
        if (i == 4 or i == 6 or i == 8 or i == 10) {
            result[index] = '-';
            index += 1;
        }

        result[index] = hex[byte >> 4];
        result[index + 1] = hex[byte & 0x0f];
        index += 2;
    }

    return result;
}
