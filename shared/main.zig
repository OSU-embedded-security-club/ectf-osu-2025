const std = @import("std");

/// Maxim's C SDK for the MAX78000 microcontroller automattically translated to Zig
pub const msdk = @import("msdk");

pub const layer3 = @import("layer3.zig");

comptime {
    _ = layer3;
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
            self.allocator.free(self.inner);
        }
    };
}

/// `inner` must have been allocated with `allocator.create`
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

pub fn RingBuffer(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        buffer: [capacity]T,
        head: usize = 0,
        tail: usize = 0,
        count: usize = 0,

        pub fn init() Self {
            return Self{
                .buffer = undefined,
            };
        }

        pub fn isEmpty(self: *Self) bool {
            return self.count == 0;
        }

        pub fn isFull(self: *Self) bool {
            return self.count == capacity;
        }

        pub fn push(self: *Self, item: T) !void {
            if (self.isFull()) {
                return error.BufferFull;
            }

            self.buffer[self.tail] = item;
            self.tail = @mod((self.tail + 1), capacity);
            self.count += 1;
        }

        pub fn pop(self: *Self) !T {
            if (self.isEmpty()) {
                return error.BufferEmpty;
            }

            const item = self.buffer[self.head];
            self.head = @mod((self.head) + 1, capacity);
            self.count -= 1;
            return item;
        }

        pub fn peek(self: *Self) !T {
            if (self.isEmpty()) {
                return error.BufferEmpty;
            }

            return self.buffer[self.head];
        }
    };
}

test "ring buf simple operations" {
    var rb = RingBuffer(i32, 4).init();

    try rb.push(1);
    try rb.push(2);
    try rb.push(3);

    try std.testing.expectEqual(@as(usize, 3), rb.count);
    try std.testing.expectEqual(@as(i32, 1), try rb.pop());
    try std.testing.expectEqual(@as(i32, 2), try rb.pop());

    try rb.push(4);
    try rb.push(5);

    try std.testing.expectEqual(@as(usize, 3), rb.count);
    try std.testing.expectEqual(@as(i32, 3), try rb.pop());
}

test "ring buf wrap around" {
    var rb = RingBuffer(i32, 3).init();

    try rb.push(1);
    try rb.push(2);
    try rb.push(3);

    try std.testing.expectError(error.BufferFull, rb.push(4));

    try std.testing.expectEqual(@as(i32, 1), try rb.pop());
    try rb.push(4);

    try std.testing.expectEqual(@as(i32, 2), try rb.pop());
    try std.testing.expectEqual(@as(i32, 3), try rb.pop());
    try std.testing.expectEqual(@as(i32, 4), try rb.pop());
}

test "ring buf isEmpty and isFull checks" {
    var rb = RingBuffer(u8, 2).init();

    try std.testing.expect(rb.isEmpty());
    try std.testing.expect(!rb.isFull());

    try rb.push(10);
    try std.testing.expect(!rb.isEmpty());
    try std.testing.expect(!rb.isFull());

    try rb.push(20);
    try std.testing.expect(!rb.isEmpty());
    try std.testing.expect(rb.isFull());
}

test "ring buf underflow" {
    var rb = RingBuffer(u8, 3).init();

    try std.testing.expectError(error.BufferEmpty, rb.pop());
    try std.testing.expectError(error.BufferEmpty, rb.peek());
}

test "ring buf peek operation" {
    var rb = RingBuffer(u8, 3).init();

    try rb.push(42);
    try std.testing.expectEqual(@as(u8, 42), try rb.peek());
    try std.testing.expectEqual(@as(u8, 42), try rb.pop());

    try rb.push(100);
    try rb.push(101);
    try std.testing.expectEqual(@as(u8, 100), try rb.peek());
    try std.testing.expectEqual(@as(u8, 100), try rb.pop());
    try std.testing.expectEqual(@as(u8, 101), try rb.peek());
}

test "ring buf mix push and pop" {
    var rb = RingBuffer(i32, 3).init();

    try rb.push(1);
    try rb.push(2);
    try std.testing.expectEqual(@as(i32, 1), try rb.pop());

    try rb.push(3);
    try rb.push(4);
    try std.testing.expectEqual(@as(i32, 2), try rb.pop());
    try std.testing.expectEqual(@as(i32, 3), try rb.pop());

    try rb.push(5);
    try rb.push(6);
    try std.testing.expectEqual(@as(i32, 4), try rb.pop());
    try std.testing.expectEqual(@as(i32, 5), try rb.pop());
}

const TestStruct = struct {
    id: u32,
    name: []const u8,
};

test "ring buf with struct values" {
    var rb = RingBuffer(TestStruct, 3).init();

    const item1 = TestStruct{ .id = 1, .name = "Alice" };
    const item2 = TestStruct{ .id = 2, .name = "Bob" };

    try rb.push(item1);
    try rb.push(item2);

    const result1 = try rb.pop();
    try std.testing.expectEqual(@as(u32, 1), result1.id);
    try std.testing.expectEqualStrings("Alice", result1.name);

    const result2 = try rb.pop();
    try std.testing.expectEqual(@as(u32, 2), result2.id);
    try std.testing.expectEqualStrings("Bob", result2.name);

    try std.testing.expect(rb.isEmpty());
}
