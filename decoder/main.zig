const std = @import("std");
const msdk = @import("msdk");
const lib = @import("lib");
const secrets = @import("secrets");

const flash = @import("flash.zig");
const uart = @import("uart.zig");
const messaging = @import("messaging.zig");
const list = @import("list.zig");
const subscribe = @import("subscribe.zig");
const decode = @import("decode.zig");

pub var subscriptions = [8]?lib.Subscription{ null, null, null, null, null, null, null, null };

pub fn getChannelIndex(channel_id: u16) DecoderError!u3 {
    inline for (secrets.channel_ids, 0..) |id, i| {
        if (channel_id == id) return i;
    }
    return error.UnknownChannelId;
}

const max_message_size = @max(list.max_message_size, subscribe.max_message_size, decode.max_message_size);
var message_body_buffer: [max_message_size]u8 = undefined;

const DecoderError = error{
    /// The body is invalid for the given message kind attempting to be decoded
    InvalidBody,

    /// The message has an opcode which is not defined in the Functional Requirements
    /// https://rules.ectf.mitre.org/2025/specs/detailed_specs.html#decoder-interface
    InvalidOpcode,

    /// A cryptographic signature has failed to verify. This suggests either a bit flip over UART, or critical tampering
    InvalidSignature,

    /// The decoder does not have a subscription to the channel ID
    NoSubscription,

    /// The frame trying to be decoded has a timestamp which is not within the subscription's interval for the channel
    NotInSubscriptionTimeRange,

    /// The decoder has been presented with a channel ID which it was not provisioned for
    UnknownChannelId,

    /// The decoder has already decoded a frame with a timestamp larger than the current frame's timestamp
    DecreasingTimestamp,
};

/// High level entrypoint for the decoder
fn run() !void {
    try uart.init();
    try flash.init();

    msdk.LED_Off(msdk.LED1);
    msdk.LED_Off(msdk.LED3);
    msdk.LED_On(msdk.LED2);

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

fn process() !void {
    while (try uart.readByte() != messaging.magic) {}
    const opcode = try uart.readByte();
    const length: u16 = @min(message_body_buffer.len, (try uart.readByte()) + (@as(u16, try uart.readByte()) << 8));

    switch (opcode) {
        'D', 'S' => messaging.sendAck(),
        'L' => {
            if (length > 0) return error.InvalidBody;

            messaging.sendAck();
            try list.execute();
            return;
        },
        else => {
            return error.InvalidOpcode;
        },
    }

    var body = message_body_buffer[0..length];
    var i: usize = 0;
    while (i < length) : (i += 256) {
        uart.readBytes(body[i..@min(i + 256, length)]);
        messaging.sendAck();
    }

    switch (opcode) {
        'D' => try decode.execute(body),
        'S' => try subscribe.execute(body),
        else => unreachable,
    }
}

/// Entrypoint for the decoder
export fn main() noreturn {
    _ = msdk.LED_Init();

    msdk.LED_On(msdk.LED3);

    // Wait for some time before we start processing to help prevent brute force attacks
    // https://rules.ectf.mitre.org/faq.html#can-we-add-intentional-delays-during-boot-to-make-it-more-difficult-for-an-attacker-to-collect-large-numbers-of-observations
    _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(4500));

    msdk.LED_Off(msdk.LED3);

    var errored = false;
    run() catch |err| {
        messaging.sendError("Fatal {}", .{err});
        errored = true;
    };

    const led: c_uint = if (errored) msdk.LED1 else msdk.LED2;

    while (true) {
        msdk.LED_On(led);
        _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(100));
        msdk.LED_Off(led);
        _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(100));
    }
}
