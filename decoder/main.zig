const std = @import("std");

const shared = @import("shared");
const msdk = @import("msdk");
const ed25519 = @import("ed25519");

const uart = @import("uart.zig");
const messaging = @import("host_messaging.zig");

pub const std_options: std.Options = .{
    .logFn = usb_log,
};

pub const os = struct {
    pub const heap = struct {
        pub const page_allocator = std.heap.c_allocator;
    };
};

/// Used to override Zig's default log function to work on the embedded, `freestanding` platform. Normally, Zig has a hard dependency on posix.
///
/// ```zig
/// const shared = @import("shared");
///
/// // set the `std_options` global to bind this custom log function
/// pub const std_options = .{
///   .logFn = shared.usb_log,
/// };
/// ```
pub fn usb_log(comptime level: std.log.Level, comptime scope: @TypeOf(.EnumLiteral), comptime format: []const u8, args: anytype) void {
    const scope_name = @tagName(scope);
    const level_name = level.asText();
    try usb_writer.print("[{s}] ({s}): ", .{ level_name, scope_name });
    try usb_writer.print(format, args);
    try usb_writer.print("\n", .{});
}

const WriteError = error{};

const usb_writer: std.io.GenericWriter(void, WriteError, usb_print) = .{
    .context = undefined,
};

fn usb_print(_: void, text: []const u8) WriteError!usize {
    for (text) |b| {
        _ = msdk.putchar(b);
    }
    return text.len;
}

/// High level entrypoint for the decoder
pub fn run() !void {
    try uart.init();

    messaging.debugMessage("Initialized UART", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true }){
        .requested_memory_limit = 0x0001e000,
    };
    const allocator = gpa.allocator();
    const arr = try allocator.alloc(i32, 10);
    _ = arr; // autofix

    msdk.LED_Off(msdk.LED1);
    msdk.LED_Off(msdk.LED3);

    msdk.LED_On(msdk.LED2);

    var subscriptions = [8]?messaging.Subscription{ null, null, null, null, null, null, null, null };

    var n: usize = 0;
    while (true) : (n += 1) {
        process(&subscriptions) catch continue;
    }
}

fn process(subscriptions: *[8]?messaging.Subscription) !void {
    while (try uart.readByte() != messaging.Magic) {}
    const opcode = try uart.readByte();
    const length: u16 = (try uart.readByte()) + (@as(u16, try uart.readByte()) << 8);

    messaging.debugMessage("opcode={c}, length={}", .{ opcode, length });

    switch (opcode) {
        'D', 'S' => messaging.ack(),
        'L' => {
            if (length > 0) {
                messaging.debugMessage("Error: list command has body", .{});
                return error.ABORT;
            }

            messaging.ack();
            try messaging.list(subscriptions);
            return;
        },
        else => {
            messaging.debugMessage("Error: invalid opcode", .{});
            return error.ABORT;
        },
    }

    var rawBuffer: [std.math.maxInt(@TypeOf(length))]u8 = undefined;
    var body = rawBuffer[0..length];
    var i: usize = 0;
    while (i < length) : (i += 256) {
        uart.readBytes(body[i..@min(i + 256, length)]);
        messaging.ack();
    }

    switch (opcode) {
        'D' => try messaging.decode(body),
        'S' => try messaging.subscribe(body, subscriptions),
        else => unreachable,
    }
}

/// Entrypoint for the decoder
pub export fn main() noreturn {
    _ = msdk.LED_Init();

    var errored = false;
    run() catch |err| {
        std.log.err("Top level fatal error: {}", .{err});
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
