//! Entrypoint and main loop

const std = @import("std");
const msdk = @import("msdk");
const secrets = @import("secrets");
pub const lib = @import("lib");

pub const flash = @import("flash.zig");
pub const uart = @import("uart.zig");
pub const messaging = @import("messaging.zig");
pub const list = @import("list.zig");
pub const subscribe = @import("subscribe.zig");
pub const decode = @import("decode.zig");
pub const hardware = @import("hardware.zig");

/// Global list of up to 8 subscriptions
pub var subscriptions = [8]?lib.Subscription{ null, null, null, null, null, null, null, null };

/// The size of the biggest possible message we expect
const max_message_size = @max(subscribe.max_message_size, decode.max_message_size);

/// The buffer which messages are written into and used while processing. It is
/// the size of the biggest possible message we expect, `max_message_size`
var message_body_buffer: []u8 = undefined;

const DecoderError = error{
    /// The body is invalid for the given message kind attempting to be decoded
    InvalidBody,

    /// The message has an opcode which is not defined in the Functional
    /// Requirements
    /// https://rules.ectf.mitre.org/2025/specs/detailed_specs.html#decoder-interface
    InvalidOpcode,

    /// A cryptographic signature has failed to verify. This suggests either a
    /// bit flip over UART, or critical tampering
    InvalidSignature,

    /// The decoder does not have a subscription to the channel ID
    NoSubscription,

    /// The frame trying to be decoded has a timestamp which is not within the
    /// subscription's interval for the channel
    NotInSubscriptionTimeRange,

    /// The decoder has been presented with a channel ID which it was not
    /// provisioned for
    UnknownChannelId,

    /// The decoder has already decoded a frame with a timestamp larger than the
    /// current frame's timestamp
    DecreasingTimestamp,

    /// The decoder has already reached the maximum number of subscriptions it
    /// can support (8), and another subscription is trying to be added
    TooManySubscriptions,
};

/// High level entrypoint for the decoder
fn run() !void {
    try uart.init();
    try flash.init();

    hardware.mpu();

    // Turn on the green LED to indicate we are successfully processing
    msdk.LED_On(msdk.LED2);

    message_body_buffer = try std.heap.c_allocator.alloc(u8, max_message_size);
    defer std.heap.c_allocator.free(message_body_buffer);

    // Process messages forever. On error, send it to the host, and continue processing messages
    while (true) {
        process() catch |err| {
            // A major error has bubbled up to here, suggesting an unrecoverable state and that we are possibly under attack.
            // We halt for 5 seconds for a small amount of brute-force attack prevention.
            // https://rules.ectf.mitre.org/faq.html#can-we-add-intentional-delays-during-boot-to-make-it-more-difficult-for-an-attacker-to-collect-large-numbers-of-observations
            _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(2450));
            messaging.sendError("{}", .{err});
            _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(2450));
        };
    }
}

/// Read until we get one message, then process it
fn process() !void {
    // Spin until we get to the magic byte
    while (try uart.readByte() != messaging.magic) {}

    // Read the rest of the header in the message
    // https://rules.ectf.mitre.org/2025/specs/detailed_specs.html#decoder-interface
    const opcode = try messaging.RecvOpcode.fromByte(try uart.readByte());
    const length: u16 = @min(message_body_buffer.len, (try uart.readByte()) + (@as(u16, try uart.readByte()) << 8));

    // Valid opcodes need their header to be ACKed
    messaging.sendAck();

    switch (opcode) {
        .List => {
            // The list command has no body
            if (length > 0) return error.InvalidBody;
            try list.execute();
        },
        .Decode => {
            const body = try readBody(length);
            try decode.execute(body);
        },
        .Subscribe => {
            const body = try readBody(length);
            try subscribe.execute(body);
        },
        .Ack => {},
    }
}

/// Read in up to `length` bytes into the global `message_body_buffer` while
/// ACKing every 256 bytes, and return a slice into `message_body_buffer`
fn readBody(length: u16) ![]u8 {
    // The length of the body that the host plans on sending should not be
    // bigger than the buffer that we read it into
    if (length >= message_body_buffer.len) return error.InvalidBody;

    var body = message_body_buffer[0..length];

    // ACK between reading in every 256 bytes
    var i: usize = 0;
    while (i < length) : (i += 256) {
        uart.readBytes(body[i..@min(i + 256, length)]);
        messaging.sendAck();
    }
    return body;
}

/// Entrypoint for the decoder
export fn main() callconv(.C) noreturn {
    hardware.disable();

    _ = msdk.LED_Init();

    // Turn on blue LED to indicate we have not started yet
    msdk.LED_On(msdk.LED3);

    // Wait for some time before we start processing to help prevent brute force attacks
    // https://rules.ectf.mitre.org/faq.html#can-we-add-intentional-delays-during-boot-to-make-it-more-difficult-for-an-attacker-to-collect-large-numbers-of-observations
    _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(4500));

    // Turn off the blue LED and start the startup process
    msdk.LED_Off(msdk.LED3);

    // Wrap our idiomatic Zig entrypoint `run` to catch its error
    var errored = false;
    run() catch |err| {
        messaging.sendError("Fatal {}", .{err});
        errored = true;
    };

    // The program is done executing now. If we errored, blink red. If we ended
    // successfully, blink green. Note that it should not be possible to end
    // successfully, because the decoder should be running constantly in `run`,
    // but we still need to satisfy the `noreturn` of this function we are in
    const led: c_uint = if (errored) msdk.LED1 else msdk.LED2;
    while (true) {
        msdk.LED_On(led);
        _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(100));
        msdk.LED_Off(led);
        _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(100));
    }
}
