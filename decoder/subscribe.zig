const std = @import("std");
const root = @import("root");
const lib = @import("lib");
const secrets = @import("secrets");
const ed25519 = @import("ed25519");

const flash = @import("flash.zig");
const messaging = @import("messaging.zig");

pub const max_message_size = @sizeOf(SignatureHeader) + @sizeOf(SubscribeHeader) + @sizeOf(lib.Subscription.Bytes);

const SignatureHeader = extern struct {
    signature: [64]u8 align(1),
};

const SubscribeHeader = extern struct {
    start: u64 align(1),
    end: u64 align(1),
    channel_id: u16 align(1),
};

pub fn execute(body: []u8) !void {
    const signature_header: *const SignatureHeader = @ptrCast(body.ptr);
    const message_body = body[@sizeOf(SignatureHeader)..];

    std.crypto.stream.salsa.Salsa20.xor(message_body, message_body, 0, secrets.subscription_key, signature_header.signature[0..8].*);
    const header: *const SubscribeHeader = @ptrCast(message_body.ptr);

    const valid = ed25519.ed25519_verify(&signature_header.signature, message_body.ptr, message_body.len, &secrets.public_key);
    if (valid == 0) {
        messaging.sendDebug("Invalid signature", .{});
        return error.InvalidSignature;
    }

    const channel_index = try root.getChannelIndex(header.channel_id);
    if (root.subscriptions[channel_index]) |*subscription| subscription.deinit();
    root.subscriptions[channel_index] = lib.Subscription.init(
        header.channel_id,
        header.start,
        header.end,
        message_body[@sizeOf(SubscribeHeader)..],
    );

    try messaging.sendWithAcks('S', &.{});

    try flash.saveSubscriptions(@truncate(channel_index));
}
