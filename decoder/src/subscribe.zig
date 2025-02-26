//! Update Subscription command

const std = @import("std");
const lib = @import("lib");
const secrets = @import("secrets");
const ed25519 = @import("ed25519");

const main = @import("main.zig");
const flash = @import("flash.zig");
const messaging = @import("messaging.zig");

/// The maximum size of a Subscribe body we expect
pub const max_message_size = @sizeOf(SubscribeHeader) + @sizeOf(lib.Subscription.Bytes);

/// The header of a Subscribe message
const SubscribeHeader = extern struct {
    /// Ed25519 signature over the plaintext contents
    signature: [64]u8 align(1),

    /// End timestamp
    start: u64 align(1),

    /// Start timestamp
    end: u64 align(1),

    /// The Channel ID
    channel_id: u32 align(1),

    /// Given a slice of bytes `body`, check that it is a valid Subscription
    /// message, and return a pointer to it into the body
    pub fn fromBytes(bytes: []u8) !*const SubscribeHeader {
        // Make sure that `bytes` is a reasonable size
        if (bytes.len < @sizeOf(SubscribeHeader) + @offsetOf(lib.Subscription.Bytes, "root_hashes") or bytes.len > max_message_size)
            return error.InvalidBody;

        const self: *const SubscribeHeader = @ptrCast(bytes.ptr);

        // The `start`, `end`, and `channel_id` fields are encrypted with the
        // shared `subscription_key` between the encoder and decoder.
        // Before we continue, we must decrypt the subscription. The nonce is
        // the first 8 bytes of the signature
        const nonce = self.signature[0..8];
        const message = bytes[@offsetOf(SubscribeHeader, "start")..];
        std.crypto.stream.salsa.Salsa20.xor(message, message, 0, secrets.subscription_key, nonce.*);

        // The asymmetric signature is verified over the plaintext contents.
        // This ensures that the message came from the encoder it was
        // provisioned with
        const valid = ed25519.ed25519_verify(&self.signature, message.ptr, message.len, &secrets.public_key);
        if (valid == 0) return error.InvalidSignature;

        return self;
    }
};

/// Attempt to add the subscription
pub fn execute(body: []u8) !void {
    const message = try SubscribeHeader.fromBytes(body);

    const channel_index = for (&main.subscriptions, 0..) |*subscription, i| {
        if (subscription.*) |*sub| {
            if (sub.serialized.channel_id == message.channel_id) {
                // If an old subscription for this channel existed, remove it, since we will
                // override it with a newer one
                sub.deinit();
                break i;
            }
        } else break i;
    } else return error.TooManySubscriptions;

    // Create the subscription for the channel
    main.subscriptions[channel_index] = lib.Subscription.init(
        message.channel_id,
        message.start,
        message.end,
        body[@sizeOf(SubscribeHeader)..],
    );

    try flash.saveSubscriptions(channel_index);

    messaging.sendDebug("subscribe success, sending S", .{});
    try messaging.sendWithAcks(.Subscribe, &.{});
}
