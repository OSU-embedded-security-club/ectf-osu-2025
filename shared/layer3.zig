const std = @import("std");

const shared = @import("main.zig");
const Owned = shared.Owned;
const toOwned = shared.toOwned;

pub const Address = enum(u10) {
    _,

    /// The general call addresses all devices on the bus using the I2C address 0.
    pub const general_call: Address = @enumFromInt(0x00);

    pub fn from(addr: u10) Address {
        return @as(Address, @enumFromInt(addr));
    }
};

pub const ChannelError = error{
    SendFailed,
    RecvFailed,
} || std.mem.Allocator.Error;

/// Interface for sending data over a remote connection
pub fn ChannelInner(comptime T: type) type {
    return struct {
        const Self = @This();

        inner: T,

        /// Send data to an address
        pub inline fn send(self: Self, data: []const u8, to: Address) ChannelError!void {
            try self.inner.send(data, to);
        }

        /// Receive data from an address. Returns `null` if no data is available.
        pub inline fn recv(self: Self, from: Address) ChannelError!?Owned([]const u8) {
            return try self.inner.recv(from);
        }
    };
}

pub inline fn Channel(inner: anytype) ChannelInner(@TypeOf(inner)) {
    return .{ .inner = inner };
}

/// A mock implementation of the `Channel` interface
pub const MockChannel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    buffers: *std.AutoHashMap(Address, std.ArrayList(u8)),
    recv_buffer_size: usize,

    pub fn init(allocator: std.mem.Allocator, recv_buffer_size: usize) !Self {
        const buffers = try allocator.create(std.AutoHashMap(Address, std.ArrayList(u8)));
        buffers.* = std.AutoHashMap(Address, std.ArrayList(u8)).init(allocator);

        return Self{
            .recv_buffer_size = recv_buffer_size,
            .allocator = allocator,
            .buffers = buffers,
        };
    }

    pub fn deinit(self: Self) void {
        var iter = self.buffers.valueIterator();
        while (iter.next()) |buffer| {
            buffer.deinit();
        }

        self.buffers.deinit();
        self.allocator.destroy(self.buffers);
    }

    pub fn send(self: Self, data: []const u8, to: Address) ChannelError!void {
        if (self.buffers.getPtr(to)) |buffer| {
            try buffer.appendSlice(data);
        } else {
            var list = std.ArrayList(u8).init(self.allocator);
            errdefer list.deinit();
            try list.appendSlice(data);
            try self.buffers.put(to, list);
        }
    }

    pub fn recv(self: Self, from: Address) ChannelError!?Owned([]const u8) {
        const buffer = self.buffers.get(from) orelse return null;

        const len = @min(self.recv_buffer_size, buffer.items.len);
        const recv_buffer = try self.allocator.dupe(u8, buffer.items[0..len]);
        errdefer self.allocator.free(recv_buffer);

        if (buffer.items.len < self.recv_buffer_size) {
            buffer.deinit();
            const removed = self.buffers.remove(from);
            std.debug.assert(removed);
        } else {
            var next_list = std.ArrayList(u8).init(self.allocator);
            try next_list.appendSlice(buffer.items[self.recv_buffer_size..]);
            buffer.deinit();
            try self.buffers.put(from, next_list);
        }

        return toOwned(@as([]const u8, recv_buffer), self.allocator);
    }
};

test "basic channel" {
    const mock = MockChannel.init(std.testing.allocator, 80) catch unreachable;
    defer mock.deinit();
    const channel = Channel(mock);

    const addrA = Address.from(11);

    const data = "hello, world!";
    try channel.send(data, addrA);

    const recv = (try channel.recv(addrA)).?;
    defer recv.deinit();
    try std.testing.expectEqualSlices(u8, data, recv.inner);
}

test "channel large buffer" {
    const recv_buffer_size = 80;
    const mock = try MockChannel.init(std.testing.allocator, recv_buffer_size);
    defer mock.deinit();
    const channel = Channel(mock);

    const addrA = Address.from(11);

    const data = try std.testing.allocator.alloc(u8, recv_buffer_size + 1);
    defer std.testing.allocator.free(data);
    try channel.send(data, addrA);

    const recv = (try channel.recv(addrA)).?;
    defer recv.deinit();
    try std.testing.expectEqualSlices(u8, data[0..recv_buffer_size], recv.inner);

    const recv2 = (try channel.recv(addrA)).?;
    defer recv2.deinit();
    try std.testing.expectEqualSlices(u8, data[recv_buffer_size .. recv_buffer_size + 1], recv2.inner);
}

test "channel multiple addresses" {
    const mock = MockChannel.init(std.testing.allocator, 80) catch unreachable;
    defer mock.deinit();
    const channel = Channel(mock);

    const addrA = Address.from(11);
    const addrB = Address.from(12);

    const dataA = "data A";
    try channel.send(dataA, addrA);

    const dataB = "data B";
    try channel.send(dataB, addrB);

    const recvB = (try channel.recv(addrB)).?;
    defer recvB.deinit();
    try std.testing.expectEqualSlices(u8, dataB, recvB.inner);

    const recvA = (try channel.recv(addrA)).?;
    defer recvA.deinit();
    try std.testing.expectEqualSlices(u8, dataA, recvA.inner);
}

test "channel recv nothing" {
    const mock = MockChannel.init(std.testing.allocator, 80) catch unreachable;
    defer mock.deinit();
    const channel = Channel(mock);

    const addr = Address.from(11);

    const recv = try channel.recv(addr);
    try std.testing.expectEqual(recv, null);
}

test "channel send nothing" {
    const mock = MockChannel.init(std.testing.allocator, 80) catch unreachable;
    defer mock.deinit();
    const channel = Channel(mock);

    const addr = Address.from(11);

    const data = ([_]u8{})[0..0];
    try std.testing.expectEqual(0, data.len);
    try channel.send(data, addr);
}
