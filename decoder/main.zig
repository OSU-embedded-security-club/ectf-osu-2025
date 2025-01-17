const std = @import("std");

const shared = @import("shared");
const msdk = @import("msdk");

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

/// High level entrypoint for the application processor
pub fn run() !void {
    std.log.info("Initializing Decoder", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true }){
        .requested_memory_limit = 0x0001e000,
    };
    const allocator = gpa.allocator();
    const arr = try allocator.alloc(i32, 10);
    std.log.info("{any}", .{arr});

    msdk.LED_Off(msdk.LED1);
    msdk.LED_Off(msdk.LED2);

    var n: usize = 0;
    while (true) : (n += 1) {
        msdk.LED_Off(msdk.LED3);
        msdk.LED_On(msdk.LED1);
        _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(1000));
        msdk.LED_Off(msdk.LED1);
        msdk.LED_On(msdk.LED2);
        _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(1000));
        msdk.LED_Off(msdk.LED2);
        msdk.LED_On(msdk.LED3);
        _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(1000));

        if (n % @as(usize, 10) == 0) {
            std.log.info("Total requested bytes: {}", .{gpa.total_requested_bytes});
        }
    }
}

/// Entrypoint for the application processor
pub export fn main() noreturn {
    _ = msdk.LED_Init();

    var errored = false;
    run() catch |err| {
        std.log.err("Top level fatal error: {}", .{err});
        errored = true;
    };

    const led: c_uint = if (errored) msdk.LED3 else msdk.LED2;

    while (true) {
        msdk.LED_On(led);
        _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(1000));
        msdk.LED_Off(led);
        _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(1000));
    }
}
