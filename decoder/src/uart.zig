//! High level Zig wrapper over the MSDK to interact with UART on the MAX78000

const std = @import("std");
const msdk = @import("msdk");
const lib = @import("lib");

/// Initialize UART
pub fn init() lib.MSDKError!void {
    try lib.msdkTry(msdk.MXC_UART_Init(msdk.MXC_UART_GET_UART(msdk.CONSOLE_UART), msdk.CONSOLE_BAUD, msdk.MXC_UART_IBRO_CLK));
}

/// Read in a single byte over UART
pub fn readByte() lib.MSDKError!u8 {
    const data = msdk.MXC_UART_ReadCharacter(msdk.MXC_UART_GET_UART(msdk.CONSOLE_UART));
    if (data < 0) {
        try lib.msdkTry(data);
    }
    return @intCast(data);
}

/// Block and keep reading from UART into `data` until all of `data` has been filled
pub fn readBytes(data: []u8) void {
    var i: usize = 0;
    while (i < data.len) {
        i += msdk.MXC_UART_ReadRXFIFO(msdk.MXC_UART_GET_UART(msdk.CONSOLE_UART), data.ptr + i, data.len - i);
    }
}

/// Block until all of `data` bytes has been written to UART
pub fn writeBytes(data: []const u8) void {
    var i: usize = 0;
    while (i < data.len) {
        i += msdk.MXC_UART_WriteTXFIFO(msdk.MXC_UART_GET_UART(msdk.CONSOLE_UART), data.ptr + i, data.len - i);
    }
}
