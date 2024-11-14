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

/// Entrypoint for the application processor
pub export fn main() noreturn {
    _ = msdk.printf("Initializing AP\n");
    _ = msdk.LED_Init();

    // _ = std.heap.c_allocator;
    // var gpa = @import("gpa.zig").GeneralPurposeAllocator(.{
    //     .enable_memory_limit = true,
    // }){
    //     .requested_memory_limit = 0x00020000,
    // };
    // const ptr = @as([*]u8, @ptrFromInt(0x20000000));
    // const heap = ptr[0..0x00020000];
    // var fba = std.heap.FixedBufferAllocator.init(heap);
    // const fba_allocator = fba.allocator();
    // const gpa_t = std.heap.GeneralPurposeAllocator(.{
    //     .enable_memory_limit = true,
    //     .thread_safe = false,
    // });
    // const MemoryPool = @TypeOf(@field(@as(gpa_t, undefined), "bucket_node_pool"));
    // var gpa = gpa_t{
    //     .backing_allocator = c_allocator,
    //     .bucket_node_pool = MemoryPool.init(c_allocator),
    //     .requested_memory_limit = 0x00020000,
    // };
    // _ = gpa;
    // _ = gpa.allocator();

    var gpa = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true }){
        .requested_memory_limit = 0x0001e000,
    };
    const allocator = gpa.allocator();
    _ = allocator.alloc(i32, 10) catch unreachable;

    // const x: u128 = 2;
    // const y: u128 = 2;
    // const z = x * y;
    // std.log.info("{}", .{z});

    // _ = std.fmt.allocPrintZ(allocator, "{any} {s}", .{ 3, "hi" }) catch unreachable;
    // _ = msdk.printf("buf: %s\n", buf.ptr);

    initI2C() catch {
        msdk.LED_On(msdk.LED1);
        _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(5000));
    };
    msdk.LED_Off(msdk.LED1);

    // sendI2C("Hello, world!") catch {
    //     msdk.LED_On(msdk.LED3);
    //     _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(5000));
    // };

    msdk.LED_Off(msdk.LED1);
    msdk.LED_Off(msdk.LED2);

    var n: usize = 0;
    while (true) : (n += 1) {
        std.log.info("2 + 3 = {any}", .{2 + 3});
        msdk.LED_Off(msdk.LED3);
        msdk.LED_On(msdk.LED1);
        _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(1000));
        msdk.LED_Off(msdk.LED1);
        msdk.LED_On(msdk.LED2);
        _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(1000));
        msdk.LED_Off(msdk.LED2);
        msdk.LED_On(msdk.LED3);
        _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(1000));

        // if (n % @as(usize, 10) == 0) {
        //     _ = msdk.printf("Total requested bytes: %d\n", gpa.total_requested_bytes);
        // }

        // if (gpa.detectLeaks()) {
        //     _ = msdk.printf("Memory leak detected!\n");
        //     continue;
        // }
    }
}

const I2CError = error{
    InitFailed,
    SendFailed,
};

const I2C_ADDR = 0x50;
const I2C_INTERFACE = msdk.MXC_I2C1;
const I2C_SPEED = 100000;

/// Initializes the I2C interface. Should be called exactly once
pub fn initI2C() !void {
    msdk.MXC_ICC_Enable(msdk.MXC_ICC0);

    var err = msdk.MXC_SYS_Clock_Select(msdk.MXC_SYS_CLOCK_IPO);
    if (err != msdk.E_SUCCESS) {
        _ = msdk.printf("MXC_SYS_Clock_Select failed: %d\n", err);
        return I2CError.InitFailed;
    }

    err = msdk.MXC_I2C_Init(I2C_INTERFACE, 1, 0);
    if (err != msdk.E_SUCCESS) {
        _ = msdk.printf("MXC_I2C_Init failed: %d\n", err);
        return I2CError.InitFailed;
    }

    err = msdk.MXC_I2C_SetFrequency(I2C_INTERFACE, I2C_SPEED);
    if (err < 0) {
        _ = msdk.printf("MXC_I2C_SetFrequency failed: %d\n", err);
        return I2CError.InitFailed;
    }

    msdk.MXC_I2C_SetTimeout(I2C_INTERFACE, 100);
}

/// Requires `initI2C` to have already been called
pub fn sendI2C(data: []const u8) !void {
    const request = msdk.mxc_i2c_req_t{
        .i2c = I2C_INTERFACE,
        .addr = I2C_ADDR,
        .tx_buf = @constCast(data.ptr),
        .rx_len = data.len,
    };
    const success = msdk.MXC_I2C_MasterTransaction(@constCast(&request));
    if (success != msdk.E_SUCCESS) {
        return I2CError.SendFailed;
    }
}
