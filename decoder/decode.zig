const std = @import("std");
const root = @import("root");
const ed25519 = @import("ed25519");
const lib = @import("lib");
const secrets = @import("secrets");

const messaging = @import("messaging.zig");

pub const max_message_size = @sizeOf(@TypeOf(std.mem.zeroes(Decode).message));

var last_timestamp: u64 = 0;

const Decode = extern struct {
    signature: [64]u8 align(1),
    channel: u16 align(1),
    timestamp: u64 align(1),
    message: [64]u8 align(1),
};

pub fn execute(body: []u8) !void {
    if (body.len <= @offsetOf(Decode, "message") and body.len >= @sizeOf(Decode)) {
        return error.InvalidBody;
    }

    const dec: *Decode = @ptrCast(body.ptr);

    std.crypto.stream.salsa.Salsa20.xor(body[@offsetOf(Decode, "channel")..], body[@offsetOf(Decode, "channel")..], 0, secrets.metadata_key, dec.signature[0..8].*);

    const message = body[@offsetOf(Decode, "channel")..];
    const valid = ed25519.ed25519_verify(&dec.signature, message.ptr, message.len, &secrets.public_key);
    if (valid == 0) {
        return error.InvalidSignature;
    }

    if (dec.channel != 0) {
        const channel_index = try root.getChannelIndex(dec.channel);
        var subscription = &(root.subscriptions[channel_index] orelse {
            return error.NoSubscription;
        });
        if (dec.timestamp < subscription.serialized.start or subscription.serialized.end < dec.timestamp) {
            return error.NotInSubscriptionTimeRange;
        }

        if (dec.timestamp <= last_timestamp) {
            return error.DecreasingTimestamp;
        }

        last_timestamp = dec.timestamp;

        const key = subscription.getKey(dec.timestamp);
        lib.crypto.decrypt(&dec.message, key);
    }

    try messaging.sendWithAcks('D', dec.message[0 .. body.len - @offsetOf(Decode, "message")]);
}
