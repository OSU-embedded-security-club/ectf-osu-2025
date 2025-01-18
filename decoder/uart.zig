const shared = @import("shared");
const msdk = @import("msdk");
const std = @import("std");

pub fn init() !void {
    try shared.msdkTry(msdk.MXC_UART_Init(msdk.MXC_UART_GET_UART(msdk.CONSOLE_UART), msdk.CONSOLE_BAUD, msdk.MXC_UART_IBRO_CLK));
}

pub fn readByte() !u8 {
    const data = msdk.MXC_UART_ReadCharacter(msdk.MXC_UART_GET_UART(msdk.CONSOLE_UART));
    if (data < 0) {
        try shared.msdkTry(data);
    }
    return @intCast(data);
}

pub fn readBytes(data: []u8) void {
    var i: usize = 0;
    while (i < data.len) {
        i += msdk.MXC_UART_ReadRXFIFO(msdk.MXC_UART_GET_UART(msdk.CONSOLE_UART), data.ptr + i, data.len - i);
    }
}

pub fn writeBytes(data: []const u8) void {
    var i: usize = 0;
    while (i < data.len) {
        i += msdk.MXC_UART_WriteTXFIFO(msdk.MXC_UART_GET_UART(msdk.CONSOLE_UART), data.ptr + i, data.len - i);
    }
}
