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

pub fn getChannelIndex(channel_id: u16) !u3 {
    inline for (secrets.channel_ids, 0..) |id, i| {
        if (channel_id == id) return i;
    }
    return error.UNKNOWN;
}

const max_message_size = @max(list.max_message_size, subscribe.max_message_size, decode.max_message_size);
var message_body_buffer: [max_message_size]u8 = undefined;

/// High level entrypoint for the decoder
fn run() !void {
    try uart.init();
    try flash.init();

    msdk.LED_Off(msdk.LED1);
    msdk.LED_Off(msdk.LED3);
    msdk.LED_On(msdk.LED2);

    var n: usize = 0;
    while (true) : (n += 1) {
        process() catch |err| {
            messaging.sendDebug("caught err: {}", .{err});
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
            if (length > 0) {
                messaging.sendDebug("Error: list command has body", .{});
                return error.ABORT;
            }

            messaging.sendAck();
            try list.execute();
            return;
        },
        else => {
            messaging.sendDebug("Error: invalid opcode", .{});
            return error.ABORT;
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

    var errored = false;
    run() catch |err| {
        messaging.sendDebug("Fatal error {}", .{err});
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
