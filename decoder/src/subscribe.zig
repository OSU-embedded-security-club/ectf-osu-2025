//! Subscribe command

const std = @import("std");
const lib = @import("lib");
const secrets = @import("secrets");
const ed25519 = @import("ed25519");

const main = @import("main.zig");
const flash = @import("flash.zig");
const messaging = @import("messaging.zig");

pub const max_message_size = @sizeOf(SubscribeHeader) + @sizeOf(lib.Subscription.Bytes);

const SubscribeHeader = extern struct {
    signature: [64]u8 align(1),
    start: u64 align(1),
    end: u64 align(1),
    channel_id: u16 align(1),

    pub fn fromBytes(bytes: []u8) !*const SubscribeHeader {
        if (bytes.len < @sizeOf(SubscribeHeader) + @offsetOf(lib.Subscription.Bytes, "root_hashes") or bytes.len > max_message_size)
            return error.InvalidBody;

        const self: *const SubscribeHeader = @ptrCast(bytes.ptr);

        const data = bytes[@offsetOf(SubscribeHeader, "start")..];
        const nonce = self.signature[0..8];
        std.crypto.stream.salsa.Salsa20.xor(data, data, 0, secrets.subscription_key, nonce.*);

        const valid = ed25519.ed25519_verify(&self.signature, data.ptr, data.len, &secrets.public_key);
        if (valid == 0) return error.InvalidSignature;

        return self;
    }
};

pub fn execute(body: []u8) !void {
    const message = try SubscribeHeader.fromBytes(body);

    const channel_index = try main.getChannelIndex(message.channel_id);
    if (main.subscriptions[channel_index]) |*subscription| subscription.deinit();
    main.subscriptions[channel_index] = lib.Subscription.init(
        message.channel_id,
        message.start,
        message.end,
        body[@sizeOf(SubscribeHeader)..],
    );

    try flash.saveSubscriptions(@truncate(channel_index));

    try messaging.sendWithAcks(.Subscribe, &.{});
}
