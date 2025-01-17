const std = @import("std");

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

/// See Libraries/PeriphDrivers/MAX78000/mxc_errors.h in the MSDK
pub const MXCErrors = enum(c_int) {
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

test "sugma tests" {
    std.debug.print("sugma testing\n", .{});
}
