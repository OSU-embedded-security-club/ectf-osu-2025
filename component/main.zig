const std = @import("std");
const shared = @import("shared");
const msdk = shared.msdk;
const params = @import("params");

pub const std_options = .{
    .logFn = shared.usb_log,
};

pub const os = struct {
    pub const heap = struct {
        pub const page_allocator = std.heap.c_allocator;
    };
};

/// Entrypoint for the component
pub export fn main() noreturn {
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
