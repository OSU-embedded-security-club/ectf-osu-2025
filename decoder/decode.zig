const std = @import("std");
const root = @import("root");
const ed25519 = @import("ed25519");
const lib = @import("lib");
const secrets = @import("secrets");

const messaging = @import("messaging.zig");

pub const max_message_size = @sizeOf(@TypeOf(std.mem.zeroes(Decode).message));

const Decode = extern struct {
    channel: u32 align(1),
    timestamp: u64 align(1),
    message: [64]u8 align(1),
    signature: [64]u8 align(1),
};

pub fn execute(body: []u8) !void {
    if (body.len != @sizeOf(Decode)) {
        messaging.sendDebug("BAD LENGTH FOR DECODE: {}", .{body.len});
        return error.BadLength;
    }
    const dec: *Decode = @ptrCast(body.ptr);

    const message = body[0..@offsetOf(Decode, "signature")];
    const valid = ed25519.ed25519_verify(&dec.signature, message.ptr, message.len, &secrets.public_key);
    if (valid == 0) {
        messaging.sendDebug("Invalid signature", .{});
        return error.InvalidSignature;
    }

    if (dec.channel != 0) {
        if (dec.channel - 1 >= root.subscriptions.len) {
            messaging.sendDebug("Channel too large", .{});
            return error.ChannelTooLarge;
        }
        var subscription = &(root.subscriptions[dec.channel - 1] orelse {
            messaging.sendDebug("No subscription", .{});
            return error.NoSubscription;
        });
        if (dec.timestamp < subscription.serialized.start or subscription.serialized.end < dec.timestamp) {
            messaging.sendDebug("Not in subscription time range", .{});
            return error.NotInSubscriptionTimeRange;
        }

        const key = subscription.getKey(dec.timestamp);
        lib.crypto.decrypt(&dec.message, key);
    }

    try messaging.sendWithAcks('D', &dec.message);
}
