const std = @import("std");

/// Maxim's C SDK for the MAX78000 microcontroller automattically translated to Zig
pub const msdk = @import("msdk");

pub const layer3 = @import("layer3.zig");
pub const layer4 = @import("layer4.zig");
pub const sugma = @import("sugma.zig");

comptime {
    _ = layer3;
    _ = layer4;
    _ = sugma;
}

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

/// An allocated value and its `deinit` function
pub fn Owned(comptime T: type) type {
    return struct {
        const Self = @This();

        inner: T,
        allocator: std.mem.Allocator,

        pub fn deinit(self: Self) void {
            switch (@typeInfo(T)) {
                .Array => self.allocator.free(self.inner),
                .Vector => self.allocator.free(self.inner),
                .Pointer => |info| switch (info.size) {
                    .One => self.allocator.destroy(self.inner),
                    .Many, .C, .Slice => self.allocator.free(self.inner),
                },
                .Struct => self.inner.deinit(),
                else => unreachable,
            }
        }
    };
}

/// `inner` must have been allocated with `allocator`
pub fn toOwned(inner: anytype, allocator: std.mem.Allocator) Owned(@TypeOf(inner)) {
    return .{
        .inner = inner,
        .allocator = allocator,
    };
}

///
/// See Libraries/PeriphDrivers/MAX78000/mxc_errors.h
///
const MXCErrors = enum(c_int) {
    E_NO_ERROR = 0,
    E_SUCCESS = 0,
    E_NULL_PTR = -1,
    E_BAD_PARAM = -3,
    E_INVALID = -4,
    E_UNINITIALIZED = -5,
    E_BUSY = -6,
    E_BAD_STATE = -7,
    E_UNKNOWN = -8,
    E_COMM_ERR = -9,
    E_TIME_OUT = -10,
    E_NO_RESPONSE = -11,
    E_OVERFLOW = -12,
    E_UNDERFLOW = -13,
    E_NONE_AVAIL = -14,
    E_SHUTDOWN = -15,
    E_ABORT = -16,
    E_NOT_SUPPORTED = -17,
    E_FAIL = -255,
};
