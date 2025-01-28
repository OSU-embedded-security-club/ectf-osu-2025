const std = @import("std");

const shared = @import("shared");
const msdk = @import("msdk");
const ed25519 = @import("ed25519");

const flash = @import("flash.zig");
const uart = @import("uart.zig");
const messaging = @import("host_messaging.zig");

pub var subscriptions = [8]?messaging.Subscription{ null, null, null, null, null, null, null, null };
const MAXIMUM_MESSAGE_SIZE = @sizeOf(messaging.SubscribeHeader) + @sizeOf(messaging.Subscription);
var message_body_buffer: [MAXIMUM_MESSAGE_SIZE]u8 = undefined;

/// High level entrypoint for the decoder
pub fn run() !void {
    try uart.init();
    messaging.debugMessage("Initialized UART", .{});

    try flash.init();

    msdk.LED_Off(msdk.LED1);
    msdk.LED_Off(msdk.LED3);

    msdk.LED_On(msdk.LED2);

    var n: usize = 0;
    while (true) : (n += 1) {
        process() catch |err| {
            messaging.debugMessage("caught err: {}", .{err});
        };
    }
}

fn process() !void {
    while (try uart.readByte() != messaging.Magic) {}
    const opcode = try uart.readByte();
    const length: u16 = @min(message_body_buffer.len, (try uart.readByte()) + (@as(u16, try uart.readByte()) << 8));

    messaging.debugMessage("opcode={c}, length={}", .{ opcode, length });

    switch (opcode) {
        'D', 'S' => messaging.ack(),
        'L' => {
            if (length > 0) {
                messaging.debugMessage("Error: list command has body", .{});
                return error.ABORT;
            }

            messaging.ack();
            try messaging.list();
            return;
        },
        else => {
            messaging.debugMessage("Error: invalid opcode", .{});
            return error.ABORT;
        },
    }

    var body = message_body_buffer[0..length];
    var i: usize = 0;
    while (i < length) : (i += 256) {
        uart.readBytes(body[i..@min(i + 256, length)]);
        messaging.ack();
    }

    switch (opcode) {
        'D' => try messaging.decode(body),
        'S' => try messaging.subscribe(body),
        else => unreachable,
    }
}

/// Entrypoint for the decoder
pub export fn main() noreturn {
    _ = msdk.LED_Init();

    var errored = false;
    run() catch |err| {
        messaging.debugMessage("Fatal error {}", .{err});
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
