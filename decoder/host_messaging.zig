const std = @import("std");
const msdk = @import("msdk");

const uart = @import("uart.zig");

pub const Magic = '%';

pub const Header = extern struct {
    opcode: u8,
    length: u16 = 0,

    pub fn asBytes(self: Header) [4]u8 {
        const len: u16 = @truncate(self.length);
        return [4]u8{ '%', self.opcode, @truncate(len), @truncate(len >> 8) };
    }
};

fn waitForAck() !void {
    while (true) {
        while (try uart.readByte() != Magic) {}

        const opcode = try uart.readByte();
        if (opcode != 'A') continue;

        const higherLength = try uart.readByte();
        if (higherLength != 0) continue;

        const lowerLength = try uart.readByte();
        if (lowerLength != 0) continue;

        break;
    }
}

pub fn sendMessageWithAcks(opcode: u8, bytes: []const u8) !void {
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

pub const SubscriptionEntry = extern struct {
    channel_id: u32 align(1),
    start: u64 align(1),
    end: u64 align(1),
};

const ListChannelResponse = extern struct {
    num_channels: u32 align(1),
    subscriptions: [8]SubscriptionEntry align(1) = undefined,

    fn asBytes(self: *ListChannelResponse) []const u8 {
        const size = @sizeOf(@TypeOf(self.num_channels)) + @sizeOf(SubscriptionEntry) * self.num_channels;
        return std.mem.asBytes(self)[0..size];
    }
};

pub fn list() !void {
    var listChannelResponse = ListChannelResponse{ .num_channels = 2 };
    listChannelResponse.subscriptions[0] = SubscriptionEntry{ .channel_id = 1, .start = 1, .end = 2 };
    listChannelResponse.subscriptions[1] = SubscriptionEntry{ .channel_id = 2, .start = 3, .end = 4 };

    const body = listChannelResponse.asBytes();

    try sendMessageWithAcks('L', body);
}

pub fn decode(body: []const u8) !void {
    debugMessage("Decode got body {any}", .{body});
    try sendMessageWithAcks('D', body);
}

pub fn subscribe(body: []const u8) !void {
    debugMessage("Subscribe got body {any}", .{body});
    try sendMessageWithAcks('S', &.{});
}

pub fn ack() void {
    const packet = Header{ .opcode = 'A' };
    uart.writeBytes(&packet.asBytes());
}

var debugMessageBuffer: [65536]u8 = undefined;

pub fn debugMessage(comptime format: []const u8, args: anytype) void {
    const text = std.fmt.bufPrint(debugMessageBuffer[4..], format, args) catch unreachable;

    const len: u16 = @truncate(text.len);
    debugMessageBuffer[0] = '%';
    debugMessageBuffer[1] = 'G';
    debugMessageBuffer[2] = @truncate(len);
    debugMessageBuffer[3] = @truncate(len >> 8);

    uart.writeBytes(debugMessageBuffer[0 .. len + 4]);
}
