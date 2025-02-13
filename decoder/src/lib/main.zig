//! Shared library which implements common

const std = @import("std");

pub const Subscription = @import("subscription.zig").Subscription;
pub const crypto = @import("crypto.zig");

// Zig needs comptime imports to not optimize out our unit tests
comptime {
    _ = @import("subscription.zig");
}

/// Zig translation of the MSDK's error macros
/// https://github.com/analogdevicesinc/msdk/blob/4f0d3d320b29c455153ea16dc34a08d87ddd85a8/Libraries/PeriphDrivers/Include/MAX78000/mxc_errors.h
const MXCError = enum(c_int) {
    E_NO_ERROR = 0,
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

/// Zig error codes corresponding to the MSDK's error codes
pub const MSDKError = error{
    NO_ERROR,
    NULL_PTR,
    BAD_PARAM,
    INVALID,
    UNINITIALIZED,
    BUSY,
    BAD_STATE,
    UNKNOWN,
    COMM_ERR,
    TIME_OUT,
    NO_RESPONSE,
    OVERFLOW,
    UNDERFLOW,
    NONE_AVAIL,
    SHUTDOWN,
    ABORT,
    NOT_SUPPORTED,
    FAIL,
};

/// Return a Zig error if an MSDK function returned an error
pub fn msdkTry(err: c_int) MSDKError!void {
    switch (@as(MXCError, @enumFromInt(err))) {
        MXCError.E_NO_ERROR => return,
        MXCError.E_NULL_PTR => return error.NULL_PTR,
        MXCError.E_BAD_PARAM => return error.BAD_PARAM,
        MXCError.E_INVALID => return error.INVALID,
        MXCError.E_UNINITIALIZED => return error.UNINITIALIZED,
        MXCError.E_BUSY => return error.BUSY,
        MXCError.E_BAD_STATE => return error.BAD_STATE,
        MXCError.E_UNKNOWN => return error.UNKNOWN,
        MXCError.E_COMM_ERR => return error.COMM_ERR,
        MXCError.E_TIME_OUT => return error.TIME_OUT,
        MXCError.E_NO_RESPONSE => return error.NO_RESPONSE,
        MXCError.E_OVERFLOW => return error.OVERFLOW,
        MXCError.E_UNDERFLOW => return error.UNDERFLOW,
        MXCError.E_NONE_AVAIL => return error.NONE_AVAIL,
        MXCError.E_SHUTDOWN => return error.SHUTDOWN,
        MXCError.E_ABORT => return error.ABORT,
        MXCError.E_NOT_SUPPORTED => return error.NOT_SUPPORTED,
        MXCError.E_FAIL => return error.FAIL,
    }
}
