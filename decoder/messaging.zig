const std = @import("std");
const root = @import("root");
const msdk = @import("msdk");

const flash = @import("flash.zig");
const uart = @import("uart.zig");

pub const magic = '%';

const Header = extern struct {
    opcode: u8,
    length: u16 = 0,

    pub fn asBytes(self: Header) [4]u8 {
        const len: u16 = @truncate(self.length);
        return [4]u8{ '%', self.opcode, @truncate(len), @truncate(len >> 8) };
    }
};

fn waitForAck() !void {
    while (true) {
        while (try uart.readByte() != magic) {}

        const opcode = try uart.readByte();
        if (opcode != 'A') continue;

        const higher_length = try uart.readByte();
        if (higher_length != 0) continue;

        const lower_length = try uart.readByte();
        if (lower_length != 0) continue;

        break;
    }
}

pub fn sendWithAcks(opcode: u8, bytes: []const u8) !void {
    var header = Header{ .opcode = opcode, .length = @intCast(bytes.len) };

    uart.writeBytes(&header.asBytes());
    try waitForAck();

    if (bytes.len > 0) {
        var iter = std.mem.window(u8, bytes, 256, 256);
        while (iter.next()) |window| {
            uart.writeBytes(window);
            try waitForAck();
        }
    }
}

pub fn sendAck() void {
    const packet = Header{ .opcode = 'A' };
    uart.writeBytes(&packet.asBytes());
}

var message_buffer: [256]u8 = undefined;

pub fn sendDebug(comptime format: []const u8, args: anytype) void {
    const text = std.fmt.bufPrint(message_buffer[4..], format, args) catch @panic("Message too big");

    const len: u16 = @truncate(text.len);
    message_buffer[0] = '%';
    message_buffer[1] = 'G';
    message_buffer[2] = @truncate(len);
    message_buffer[3] = @truncate(len >> 8);

    uart.writeBytes(message_buffer[0 .. len + 4]);
}

pub fn sendError(comptime format: []const u8, args: anytype) void {
    const text = std.fmt.bufPrint(message_buffer[4..], format, args) catch @panic("Message too big");

    const len: u16 = @truncate(text.len);
    message_buffer[0] = '%';
    message_buffer[1] = 'E';
    message_buffer[2] = @truncate(len);
    message_buffer[3] = @truncate(len >> 8);

    uart.writeBytes(message_buffer[0 .. len + 4]);
}
