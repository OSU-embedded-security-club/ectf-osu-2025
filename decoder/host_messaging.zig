const std = @import("std");
const msdk = @import("msdk");

const shared = @import("shared");
const crypto = shared.crypto;

const secrets = @import("secrets");

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

pub fn list(subscriptions: *[8]?Subscription) !void {
    var listChannelResponse = ListChannelResponse{ .num_channels = 0 };

    var channelIndex: usize = 0;
    for (subscriptions, 0..) |subscription, i| {
        if (subscription) |sub| {
            listChannelResponse.subscriptions[channelIndex] = SubscriptionEntry{ .channel_id = i + 1, .start = sub.start, .end = sub.end };
            channelIndex += 1;
        }
    }
    listChannelResponse.num_channels = channelIndex;

    const body = listChannelResponse.asBytes();

    try sendMessageWithAcks('L', body);
}

pub fn decode(body: []const u8) !void {
    debugMessage("Decode got body {any}", .{body});
    try sendMessageWithAcks('D', body);
}

const SubscribeHeader = extern struct {
    start: u64 align(1),
    end: u64 align(1),
    channel: u8 align(1),
};

pub const Subscription = struct {
    start: u64,
    end: u64,
    num_hashes: u7,
    hashes: [126][16]u8 = undefined,
};

pub fn subscribe(body: []u8, subscriptions: *[8]?Subscription) !void {
    const key = secrets.subscriptionKey;
    std.crypto.stream.salsa.Salsa20.xor(body, body, 0, key, std.mem.zeroes([8]u8));

    const header: *const SubscribeHeader = @ptrCast(body.ptr);
    const sub = &subscriptions[header.channel - 1];

    sub.* = .{
        .start = header.start,
        .end = header.end,
        .num_hashes = @truncate((body.len - @sizeOf(SubscribeHeader)) / 16),
    };

    var iter = std.mem.window(u8, body[@sizeOf(SubscribeHeader)..], 16, 16);
    var i: usize = 0;
    while (iter.next()) |hash| {
        @memcpy(&sub.*.?.hashes[i], hash);
        i += 1;
    }

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
