const std = @import("std");
const root = @import("root");
const lib = @import("lib");
const secrets = @import("secrets");

const flash = @import("flash.zig");
const messaging = @import("messaging.zig");

pub const max_message_size = @sizeOf(SubscribeHeader) + @sizeOf(lib.Subscription.Bytes);

const SubscribeHeader = extern struct {
    start: u64 align(1),
    end: u64 align(1),
    channel: u8 align(1),
};

pub fn execute(body: []u8) !void {
    const key = secrets.subscription_key;
    std.crypto.stream.salsa.Salsa20.xor(body, body, 0, key, std.mem.zeroes([8]u8));

    const header: *const SubscribeHeader = @ptrCast(body.ptr);
    const channel_index = header.channel - 1;

    if (root.subscriptions[channel_index]) |*subscription| subscription.deinit();
    root.subscriptions[channel_index] = lib.Subscription.init(header.start, header.end, body[@sizeOf(SubscribeHeader)..]);

    try flash.saveSubscriptions(@truncate(channel_index));

    try messaging.sendWithAcks('S', &.{});
}
