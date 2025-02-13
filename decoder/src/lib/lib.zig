//! Shared library which implements functions that do not require interaction
//! with the physical hardware. This module has unit tests which run on x86_64

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
    /// No Error, success
    E_NO_ERROR = 0,

    /// Pointer is NULL
    E_NULL_PTR = -1,

    /// No such device
    E_NO_DEVICE = -2,

    /// Parameter not acceptable
    E_BAD_PARAM = -3,

    /// Value not valid or allowed
    E_INVALID = -4,

    /// Module not initialized
    E_UNINITIALIZED = -5,

    /// Busy now, try again later
    E_BUSY = -6,

    /// Operation not allowed in current state
    E_BAD_STATE = -7,

    /// Generic error
    E_UNKNOWN = -8,

    /// General communications error
    E_COMM_ERR = -9,

    /// Operation timed out
    E_TIME_OUT = -10,

    /// Expected response did not occur
    E_NO_RESPONSE = -11,

    /// Operations resulted in unexpected overflow
    E_OVERFLOW = -12,

    /// Operations resulted in unexpected underflow
    E_UNDERFLOW = -13,

    /// Data or resource not available at this time
    E_NONE_AVAIL = -14,

    /// Event was shutdown
    E_SHUTDOWN = -15,

    /// Event was aborted
    E_ABORT = -16,

    /// The requested operation is not supported
    E_NOT_SUPPORTED = -17,

    /// The requested operation is failed
    E_FAIL = -255,
};

/// Zig error codes corresponding to the MSDK's error codes
pub const MSDKError = error{
    /// No Error, success
    NO_ERROR,

    /// Pointer is NULL
    NULL_PTR,

    /// No such device
    NO_DEVICE,

    /// Parameter not acceptable
    BAD_PARAM,

    /// Value not valid or allowed
    INVALID,

    /// Module not initialized
    UNINITIALIZED,

    /// Busy now, try again later
    BUSY,

    /// Operation not allowed in current state
    BAD_STATE,

    /// Generic error
    UNKNOWN,

    /// General communications error
    COMM_ERR,

    /// Operation timed out
    TIME_OUT,

    /// Expected response did not occur
    NO_RESPONSE,

    /// Operations resulted in unexpected overflow
    OVERFLOW,

    /// Operations resulted in unexpected underflow
    UNDERFLOW,

    /// Data or resource not available at this time
    NONE_AVAIL,

    /// Event was shutdown
    SHUTDOWN,

    /// Event was aborted
    ABORT,

    /// The requested operation is not supported
    NOT_SUPPORTED,

    /// The requested operation is failed
    FAIL,
};

/// Return a Zig error if an MSDK function returned an error
pub fn msdkTry(err: c_int) MSDKError!void {
    switch (@as(MXCError, @enumFromInt(err))) {
        MXCError.E_NO_ERROR => return,
        MXCError.E_NULL_PTR => return error.NULL_PTR,
        MXCError.E_NO_DEVICE => return error.NO_DEVICE,
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
