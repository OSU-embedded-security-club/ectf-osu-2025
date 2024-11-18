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
    // SendTooBig,
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

        /// Receive data from an address. Returns `null` if no data is available. The returned buffer
        /// is not guaranteed to be full remaining contents of the channel, and further data may be
        /// available with subsequent calls to `recv`.
        pub inline fn recv(self: Self, from: Address) ChannelError!?Owned([]const u8) {
            return try self.inner.recv(from);
        }
    };
}

pub inline fn Channel(inner: anytype) ChannelInner(@TypeOf(inner)) {
    return .{ .inner = inner };
}

pub const MockChannel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    sendBuffer: *std.AutoHashMap(Address, std.ArrayList(u8)),
    recvBuffer: *std.AutoHashMap(Address, std.ArrayList(u8)),
    mutex: *std.Thread.Mutex,

    from: MockChannelSimplex,
    to: MockChannelSimplex,

    pub fn init(allocator: std.mem.Allocator, recv_buffer_size: usize, unreliable: bool) !Self {
        const sendBuffer = try allocator.create(std.AutoHashMap(Address, std.ArrayList(u8)));
        sendBuffer.* = std.AutoHashMap(Address, std.ArrayList(u8)).init(allocator);

        const recvBuffer = try allocator.create(std.AutoHashMap(Address, std.ArrayList(u8)));
        recvBuffer.* = std.AutoHashMap(Address, std.ArrayList(u8)).init(allocator);

        const mutex = try allocator.create(std.Thread.Mutex);
        mutex.* = .{};

        const to = try MockChannelSimplex.init(allocator, recv_buffer_size, unreliable, sendBuffer, recvBuffer, mutex);
        const from = try MockChannelSimplex.init(allocator, recv_buffer_size, unreliable, recvBuffer, sendBuffer, mutex);

        return Self{
            .to = to,
            .from = from,
            .allocator = allocator,
            .sendBuffer = sendBuffer,
            .recvBuffer = recvBuffer,
            .mutex = mutex,
        };
    }

    pub fn deinit(self: Self) void {
        var iter = self.sendBuffer.valueIterator();
        while (iter.next()) |buffer| {
            buffer.deinit();
        }

        self.sendBuffer.deinit();
        self.allocator.destroy(self.sendBuffer);

        iter = self.recvBuffer.valueIterator();
        while (iter.next()) |buffer| {
            buffer.deinit();
        }

        self.recvBuffer.deinit();
        self.allocator.destroy(self.recvBuffer);

        self.to.deinit();
        self.from.deinit();
        self.allocator.destroy(self.mutex);
    }
};

/// A mock implementation of the `Channel` interface
const MockChannelSimplex = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    sendBuffer: *std.AutoHashMap(Address, std.ArrayList(u8)),
    recvBuffer: *std.AutoHashMap(Address, std.ArrayList(u8)),
    mutex: *std.Thread.Mutex,
    recv_buffer_size: usize,

    unreliable: bool,
    n: *usize,

    pub fn init(
        allocator: std.mem.Allocator,
        recv_buffer_size: usize,
        unreliable: bool,
        sendBuffer: *std.AutoHashMap(Address, std.ArrayList(u8)),
        recvBuffer: *std.AutoHashMap(Address, std.ArrayList(u8)),
        mutex: *std.Thread.Mutex,
    ) !Self {
        const n = try allocator.create(usize);
        n.* = 0;

        return Self{
            .recv_buffer_size = recv_buffer_size,
            .allocator = allocator,
            .sendBuffer = sendBuffer,
            .recvBuffer = recvBuffer,
            .unreliable = unreliable,
            .mutex = mutex,
            .n = n,
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.destroy(self.n);
    }

    pub fn send(self: Self, data: []const u8, to: Address) ChannelError!void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // if (data.len > self.recv_buffer_size) {
        //     return ChannelError.SendTooBig;
        // }
        if (self.sendBuffer.getPtr(to)) |buffer| {
            try buffer.appendSlice(data);
        } else {
            var buffer = std.ArrayList(u8).init(self.allocator);
            errdefer buffer.deinit();
            try buffer.appendSlice(data);
            try self.sendBuffer.put(to, buffer);
        }

        self.messWithData();
    }

    fn messWithData(self: Self) void {
        if (self.unreliable) {
            var iter = self.sendBuffer.valueIterator();
            while (iter.next()) |buffer| {
                if (self.n.* % 2 == 0) {
                    buffer.items[buffer.items.len / 2] += 7;
                }
            }

            self.n.* += 1;
        }
    }

    pub fn recv(self: Self, from: Address) ChannelError!?Owned([]const u8) {
        self.mutex.lock();
        defer self.mutex.unlock();

        const buffer = self.recvBuffer.get(from) orelse return null;

        const len = @min(self.recv_buffer_size, buffer.items.len);
        const recv_buffer = try self.allocator.dupe(u8, buffer.items[0..len]);
        errdefer self.allocator.free(recv_buffer);

        if (buffer.items.len < self.recv_buffer_size) {
            buffer.deinit();
            const removed = self.recvBuffer.remove(from);
            std.debug.assert(removed);
        } else {
            var next_list = std.ArrayList(u8).init(self.allocator);
            try next_list.appendSlice(buffer.items[self.recv_buffer_size..]);
            buffer.deinit();
            try self.recvBuffer.put(from, next_list);
        }

        return toOwned(@as([]const u8, recv_buffer), self.allocator);
    }
};

test "basic channel" {
    const mocks = try MockChannel.init(std.testing.allocator, 80, false);
    defer mocks.deinit();

    const toChannel = Channel(mocks.to);
    const fromChannel = Channel(mocks.from);

    const addrA = Address.from(11);

    const data = "hello, world!";
    try toChannel.send(data, addrA);

    const recv = (try fromChannel.recv(addrA)).?;
    defer recv.deinit();

    try std.testing.expectEqualSlices(u8, data, recv.inner);
}

test "channel large buffer" {
    const recv_buffer_size = 80;
    const mocks = try MockChannel.init(std.testing.allocator, recv_buffer_size, false);
    defer mocks.deinit();

    const toChannel = Channel(mocks.to);
    const fromChannel = Channel(mocks.from);

    const addrA = Address.from(11);

    const data = try std.testing.allocator.alloc(u8, recv_buffer_size + 1);
    defer std.testing.allocator.free(data);
    try toChannel.send(data, addrA);

    const recv = (try fromChannel.recv(addrA)).?;
    defer recv.deinit();
    try std.testing.expectEqualSlices(u8, data[0..recv_buffer_size], recv.inner);

    const recv2 = (try fromChannel.recv(addrA)).?;
    defer recv2.deinit();
    try std.testing.expectEqualSlices(u8, data[recv_buffer_size .. recv_buffer_size + 1], recv2.inner);
}

test "channel multiple addresses" {
    const mocks = try MockChannel.init(std.testing.allocator, 80, false);
    defer mocks.deinit();

    const toChannel = Channel(mocks.to);
    const fromChannel = Channel(mocks.from);

    const addrA = Address.from(11);
    const addrB = Address.from(12);

    const dataA = "data A";
    try toChannel.send(dataA, addrA);

    const dataB = "data B";
    try toChannel.send(dataB, addrB);

    const recvB = (try fromChannel.recv(addrB)).?;
    defer recvB.deinit();
    try std.testing.expectEqualSlices(u8, dataB, recvB.inner);

    const recvA = (try fromChannel.recv(addrA)).?;
    defer recvA.deinit();
    try std.testing.expectEqualSlices(u8, dataA, recvA.inner);
}

test "channel recv nothing" {
    const mocks = try MockChannel.init(std.testing.allocator, 80, false);
    defer mocks.deinit();

    const fromChannel = Channel(mocks.from);

    const addr = Address.from(11);

    const recv = try fromChannel.recv(addr);
    try std.testing.expectEqual(recv, null);
}

test "channel send nothing" {
    const mocks = try MockChannel.init(std.testing.allocator, 80, false);
    defer mocks.deinit();

    const toChannel = Channel(mocks.to);

    const addr = Address.from(11);

    const data = ([_]u8{})[0..0];
    try std.testing.expectEqual(0, data.len);
    try toChannel.send(data, addr);
}

test "unreliable channel" {
    const recv_buffer_size = 80;
    const mocks = try MockChannel.init(std.testing.allocator, recv_buffer_size, true);
    defer mocks.deinit();

    const toChannel = Channel(mocks.to);
    const fromChannel = Channel(mocks.from);

    const addrA = Address.from(11);

    const data = try std.testing.allocator.alloc(u8, recv_buffer_size * 10);
    defer std.testing.allocator.free(data);
    try toChannel.send(data, addrA);

    var unequal = false;
    for (0..10) |_| {
        const recv = (try fromChannel.recv(addrA)).?;
        defer recv.deinit();
        unequal = !std.mem.eql(u8, data[0..recv_buffer_size], recv.inner);
        if (unequal) {
            break;
        }
    }

    try std.testing.expect(unequal);
}
