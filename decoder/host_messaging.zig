const std = @import("std");
const msdk = @import("msdk");
const ed25519 = @import("ed25519");

const shared = @import("shared");

const secrets = @import("secrets");

const flash = @import("flash.zig");
const uart = @import("uart.zig");
const root = @import("root");

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
    var listChannelResponse = ListChannelResponse{ .num_channels = 0 };

    var channelIndex: usize = 0;
    for (root.subscriptions, 0..) |subscription, i| {
        if (subscription) |sub| {
            listChannelResponse.subscriptions[channelIndex] = SubscriptionEntry{ .channel_id = i + 1, .start = sub.start, .end = sub.end };
            channelIndex += 1;
        }
    }
    listChannelResponse.num_channels = channelIndex;

    const body = listChannelResponse.asBytes();

    try sendMessageWithAcks('L', body);
}

const Decode = extern struct {
    channel: u32 align(1),
    timestamp: u64 align(1),
    message: [64]u8 align(1),
    signature: [64]u8 align(1),
};

pub fn decode(body: []u8) !void {
    if (body.len != @sizeOf(Decode)) {
        debugMessage("BAD LENGTH FOR DECODE: {}", .{body.len});
        return error.BadLength;
    }
    const dec: *Decode = @ptrCast(body.ptr);

    const message = body[0..@offsetOf(Decode, "signature")];
    const good = ed25519.ed25519_verify(&dec.signature, message.ptr, message.len, &secrets.publicKey);
    if (good == 0) {
        debugMessage("Invalid signature", .{});
        return error.InvalidSignature;
    }

    if (dec.channel != 0) {
        if (dec.channel - 1 >= root.subscriptions.len) {
            debugMessage("Channel too large", .{});
            return error.ChannelTooLarge;
        }
        const subscription: Subscription = root.subscriptions[dec.channel - 1] orelse {
            debugMessage("No subscription", .{});
            return error.NoSubscription;
        };
        if (dec.timestamp < subscription.start or subscription.end < dec.timestamp) {
            debugMessage("Not in subscription time range", .{});
            return error.NotInSubscriptionTimeRange;
        }
        var roots: [126]shared.hashtree.RootPosition = undefined;
        _ = shared.hashtree.getRootPositions(subscription.start, subscription.end, &roots);
        var key: [16]u8 = undefined;
        shared.hashtree.getKey(&roots, &subscription.hashes, dec.timestamp, &key);

        shared.crypto.decrypt(&dec.message, key);
    }

    try sendMessageWithAcks('D', &dec.message);
}

pub const SubscribeHeader = extern struct {
    start: u64 align(1),
    end: u64 align(1),
    channel: u8 align(1),
};

pub const Subscription = extern struct {
    start: u64,
    end: u64,
    hashes: [126][16]u8 = undefined,
};

pub fn subscribe(body: []u8) !void {
    const key = secrets.subscriptionKey;
    std.crypto.stream.salsa.Salsa20.xor(body, body, 0, key, std.mem.zeroes([8]u8));

    const header: *const SubscribeHeader = @ptrCast(body.ptr);
    const sub = &root.subscriptions[header.channel - 1];

    sub.* = .{
        .start = header.start,
        .end = header.end,
    };

    var iter = std.mem.window(u8, body[@sizeOf(SubscribeHeader)..], 16, 16);
    var i: usize = 0;
    while (iter.next()) |hash| {
        @memcpy(&sub.*.?.hashes[i], hash);
        i += 1;
    }

    try flash.saveSubscriptions(@truncate(header.channel - 1));

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
