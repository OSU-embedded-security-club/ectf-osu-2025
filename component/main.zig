const std = @import("std");

const params = @import("params");
const shared = @import("shared");
const msdk = shared.msdk;

pub const std_options = .{
    .logFn = shared.usb_log,
};

pub const os = struct {
    pub const heap = struct {
        pub const page_allocator = std.heap.c_allocator;
    };
};

/// High level entrypoint for the component
pub fn run() !void {
    std.log.info("Initializing Component", .{});
    _ = msdk.LED_Init();

    var gpa = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true }){
        .requested_memory_limit = 0x0001e000,
    };
    const allocator = gpa.allocator();
    _ = allocator;

    msdk.LED_Off(msdk.LED1);
    msdk.LED_Off(msdk.LED2);

    while (true) {
        for (0..3) |_| {
            msdk.LED_On(msdk.LED2);
            _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(500 / 3));
            msdk.LED_Off(msdk.LED2);
            _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(500 / 3));
        }
        for (0..3) |_| {
            msdk.LED_On(msdk.LED2);
            _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(1000 / 3));
            msdk.LED_Off(msdk.LED2);
            _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(1000 / 3));
        }
        for (0..3) |_| {
            msdk.LED_On(msdk.LED2);
            _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(500 / 3));
            msdk.LED_Off(msdk.LED2);
            _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(500 / 3));
        }
        _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(2000 / 3));
    }
}

/// Entrypoint for the component
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
