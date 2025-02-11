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
    channel: u8 align(1),
};

pub fn execute(body: []u8) !void {
    const signature_header: *const SignatureHeader = @ptrCast(body.ptr);
    const message_body = body[@sizeOf(SignatureHeader)..];
    messaging.sendDebug("signature: {}", .{std.fmt.fmtSliceHexLower(&signature_header.signature)});
    messaging.sendDebug("body: {}", .{std.fmt.fmtSliceHexLower(message_body)});
    messaging.sendDebug("message_body.len: {}", .{message_body.len});
    messaging.sendDebug("pubkey: {}", .{std.fmt.fmtSliceHexLower(&secrets.public_key)});
    const valid = ed25519.ed25519_verify(&signature_header.signature, message_body.ptr, message_body.len, &secrets.public_key);
    if (valid == 0) {
        messaging.sendDebug("Invalid signature", .{});
        return error.InvalidSignature;
    }

    const key = secrets.subscription_key;
    std.crypto.stream.salsa.Salsa20.xor(message_body, message_body, 0, key, std.mem.zeroes([8]u8));

    const header: *const SubscribeHeader = @ptrCast(message_body.ptr);
    const channel_index = header.channel - 1;

    if (root.subscriptions[channel_index]) |*subscription| subscription.deinit();
    root.subscriptions[channel_index] = lib.Subscription.init(header.start, header.end, body[@sizeOf(SubscribeHeader)..]);

    try flash.saveSubscriptions(@truncate(channel_index));

    try messaging.sendWithAcks('S', &.{});
}
