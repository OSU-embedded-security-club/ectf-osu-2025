//! Decode command

const std = @import("std");
const root = @import("root");
const ed25519 = @import("ed25519");
const lib = @import("lib");
const secrets = @import("secrets");

const messaging = @import("messaging.zig");

/// The maximum size of a Decode body we expect
pub const max_message_size = @sizeOf(Decode);

/// The last timestamp we have successfully decoded
var last_timestamp: ?u64 = null;

/// The decode message which
const Decode = extern struct {
    /// Ed25519 signature over the plaintext contents
    signature: [64]u8 align(1),

    channel_id: u16 align(1),
    timestamp: u64 align(1),

    /// Up to 64 byte message
    message: [64]u8 align(1),

    /// Given a slice of bytes `body`, check that it is a valid Decode message,
    /// and return a pointer to it into the body
    pub fn fromBytes(body: []u8) !*Decode {
        // Make sure that `body` is a correct size, accounting for the fact that
        // the message is variable width
        if (body.len <= @offsetOf(Decode, "message") or body.len > @sizeOf(Decode))
            return error.InvalidBody;

        const self: *Decode = @ptrCast(body.ptr);

        // The `channel_id`, `timestamp`, and `message` are encrypted with a
        // shared `metadata_key` between the encoder and decoder. Before we
        // continue, we must decrypt the metadata. The nonce is the first 8
        // bytes of the signature
        const nonce = self.signature[0..8];
        const message = body[@offsetOf(Decode, "channel_id")..];
        std.crypto.stream.salsa.Salsa20.xor(message, message, 0, secrets.metadata_key, nonce.*);

        // The asymmetric signature is verified over the plaintext contents.
        // This ensures that the message came from the encoder it was
        // provisioned with
        const valid = ed25519.ed25519_verify(&self.signature, message.ptr, message.len, &secrets.public_key);
        if (valid == 0) return error.InvalidSignature;

        return self;
    }
};

/// Attempt to decode the body. This will error if it has been tampered with or
/// would otherwise violate any security requirements
pub fn execute(body: []u8) !void {
    const decode = try Decode.fromBytes(body);

    if (last_timestamp) |t| if (decode.timestamp <= t)
        return error.DecreasingTimestamp;

    if (decode.channel_id != 0) {
        const channel_index = try root.getChannelIndex(decode.channel_id);

        // Try to get the subscription corresponding to the `channel_id` from
        // the message
        var subscription = &(root.subscriptions[channel_index] orelse return error.NoSubscription);

        if (!subscription.includes(decode.timestamp))
            return error.NotInSubscriptionTimeRange;

        const key = subscription.getKey(decode.timestamp);

        lib.crypto.decrypt(&decode.message, key);
    }

    last_timestamp = decode.timestamp;

    try messaging.sendWithAcks(.Decode, body[@offsetOf(Decode, "message")..]);
}
