const std = @import("std");
pub const msdk = @import("msdk");

const WriteError = error{};

pub fn usb_log(comptime level: std.log.Level, comptime scope: @TypeOf(.EnumLiteral), comptime format: []const u8, args: anytype) void {
    const scope_name = @tagName(scope);
    const level_name = level.asText();
    try usb_writer.print("[{s}] ({s}): ", .{ level_name, scope_name });
    try usb_writer.print(format, args);
    try usb_writer.print("\n", args);
}

const usb_writer: std.io.GenericWriter(void, WriteError, usb_print) = .{
    .context = undefined,
};

fn usb_print(_: void, text: []const u8) WriteError!usize {
    for (text) |b| {
        _ = msdk.putchar(b);
    }
    return text.len;
}
