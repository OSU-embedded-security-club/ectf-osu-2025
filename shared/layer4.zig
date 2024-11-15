const std = @import("std");

const layer3 = @import("layer3.zig");

const shared = @import("main.zig");
const Owned = shared.Owned;
const toOwned = shared.toOwned;

const Flags = packed struct {
    is_ack: bool,
    _: u7 = 0,
};

// Simple packet structure with checksum
pub const Packet = extern struct {
    const data_size = 114;
    seq_num: u32 align(1),
    ack_num: u32 align(1),
    flags: Flags align(1),
    checksum: u32 align(1),
    data_len: u8 align(1),
    data: [data_size]u8 align(1),

    pub fn init() Packet {
        return .{
            .seq_num = 0,
            .ack_num = 0,
            .flags = .{ .is_ack = false },
            .checksum = 0,
            .data = [_]u8{0} ** data_size,
            .data_len = 0,
        };
    }

    pub fn calculateChecksum(self: *Packet) void {
        self.checksum = 0;
        const bytes = std.mem.asBytes(self);
        var hasher = std.hash.Crc32.init();
        hasher.update(bytes);
        self.checksum = hasher.final();
    }

    pub fn verifyChecksum(self: *const Packet) bool {
        var temp_packet = self.*;
        temp_packet.checksum = 0;
        const bytes = std.mem.asBytes(&temp_packet);
        var hasher = std.hash.Crc32.init();
        hasher.update(bytes);
        return hasher.final() == self.checksum;
    }
};

pub fn Connection(comptime ChannelImpl: type) type {
    return struct {
        const Self = @This();

        channel: layer3.ChannelInner(ChannelImpl),
        address: layer3.Address,

        next_seq_num: u32,
        expected_seq_num: u32,
        unacked_packets: std.ArrayList(UnackedPacket),
        allocator: std.mem.Allocator,
        buffer: std.ArrayList(u8),
        recvbuffer: std.ArrayList(u8),

        const UnackedPacket = struct {
            packet: Packet,
            last_sent: i64,
            retries: u32,
        };

        pub fn init(allocator: std.mem.Allocator, channel: ChannelImpl, address: layer3.Address) Self {
            return .{
                .channel = layer3.Channel(channel),
                .address = address,

                .next_seq_num = 0,
                .expected_seq_num = 0,
                .allocator = allocator,
                .unacked_packets = std.ArrayList(UnackedPacket).init(allocator),
                .buffer = std.ArrayList(u8).init(allocator),
                .recvbuffer = std.ArrayList(u8).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.unacked_packets.deinit();
            self.buffer.deinit();
            self.recvbuffer.deinit();
        }

        pub fn send(self: *Self, data: anytype) !void {
            const bytes = std.mem.toBytes(data);
            var iter = std.mem.window(u8, &bytes, Packet.data_size, Packet.data_size);
            while (iter.next()) |chunk| {
                try self.sendBytes(chunk);
            }
        }

        fn sendBytes(self: *Self, data: []const u8) !void {
            var packet = Packet.init();
            packet.seq_num = self.next_seq_num;
            packet.data_len = @intCast(data.len);
            @memcpy(packet.data[0..data.len], data);

            try self.unacked_packets.append(.{
                .packet = packet,
                .last_sent = std.time.milliTimestamp(),
                .retries = 0,
            });

            self.next_seq_num += 1;
            try self.sendPacket(&packet);
        }

        fn sendAck(self: *Self, seq_num: u32) !void {
            var ack_packet = Packet.init();
            ack_packet.flags.is_ack = true;
            ack_packet.ack_num = seq_num;

            try self.sendPacket(&ack_packet);
        }

        fn sendPacket(self: *Self, packet: *Packet) !void {
            packet.calculateChecksum();
            const bytes = std.mem.asBytes(packet);
            try self.channel.send(bytes, self.address);

            std.debug.print("Sending packet: seq={}, ack={}, is_ack={}\n", .{
                packet.seq_num,
                packet.ack_num,
                packet.flags.is_ack,
            });
        }

        pub fn recv(self: *Self, comptime T: type) !?Owned(*T) {
            if (try self.channel.recv(self.address)) |data| {
                errdefer data.deinit();
                try self.buffer.appendSlice(data.inner);
                data.deinit();
                if (self.buffer.items.len >= @sizeOf(Packet)) {
                    const packet = self.buffer.items[0..@sizeOf(Packet)];
                    const packet_pointer: *Packet = @ptrCast(packet.ptr);
                    var packet_struct = packet_pointer.*;

                    var newBuffer = std.ArrayList(u8).init(self.allocator);
                    try newBuffer.appendSlice(self.buffer.items[@sizeOf(Packet)..]);
                    self.buffer.deinit();
                    self.buffer = newBuffer;

                    if (packet_struct.verifyChecksum()) {
                        const maybe_packet = self.recvPacket(&packet_struct) catch return null;
                        if (maybe_packet) |packet_data| {
                            try self.recvbuffer.appendSlice(packet_data);
                            if (self.recvbuffer.items.len >= @sizeOf(T)) {
                                const t: *T = @ptrCast(self.recvbuffer.items[0..@sizeOf(T)].ptr);
                                const result = try self.allocator.create(T);
                                errdefer self.allocator.destroy(result);
                                result.* = t.*;

                                var newRecvBuffer = std.ArrayList(u8).init(self.allocator);
                                try newRecvBuffer.appendSlice(self.recvbuffer.items[@sizeOf(T)..]);
                                self.recvbuffer.deinit();
                                self.recvbuffer = newRecvBuffer;

                                return toOwned(result, self.allocator);
                            }
                        }
                    }
                }
            }

            return null;
        }

        fn recvPacket(self: *Self, packet: *Packet) !?[]const u8 {
            if (packet.flags.is_ack) {
                const ack_num = packet.ack_num;
                var i: usize = 0;
                while (i < self.unacked_packets.items.len) : (i += 1) {
                    if (self.unacked_packets.items[i].packet.seq_num == ack_num) {
                        _ = self.unacked_packets.orderedRemove(i);
                        break;
                    }
                }
                return null;
            } else if (packet.seq_num == self.expected_seq_num) {
                try self.sendAck(packet.seq_num);
                self.expected_seq_num += 1;

                return packet.data[0..packet.data_len];
            }

            return error.UnexpectedPacket;
        }

        pub fn handleRetransmissions(self: *Self) !void {
            const current_time = std.time.milliTimestamp();
            const timeout = 1000;
            const max_retries = 5;

            var i: usize = 0;
            while (i < self.unacked_packets.items.len) : (i += 1) {
                var unacked = &self.unacked_packets.items[i];
                if (current_time - unacked.last_sent > timeout) {
                    if (unacked.retries >= max_retries) {
                        return error.MaxRetriesExceeded;
                    }
                    try self.sendPacket(&unacked.packet);
                    unacked.last_sent = current_time;
                    unacked.retries += 1;
                }
            }
        }
    };
}

const MyObject = extern struct {
    hello: u32 align(1),
};

const BigObject = extern struct {
    hello: [Packet.data_size + 1]u8 align(1),
};

test "connection" {
    std.debug.print("connection\n", .{});
    const mock = layer3.MockChannel.init(std.testing.allocator, 80, false) catch unreachable;
    defer mock.deinit();
    const channel = layer3.Channel(mock);

    const addr = layer3.Address.from(11);

    const obj1 = MyObject{ .hello = 123 };
    var conn1 = Connection(@TypeOf(channel)).init(std.testing.allocator, channel, addr);
    defer conn1.deinit();
    try conn1.send(obj1);

    var conn2 = Connection(@TypeOf(channel)).init(std.testing.allocator, channel, addr);
    defer conn2.deinit();
    var obj2 = try conn2.recv(MyObject);
    while (obj2 == null) : (obj2 = try conn2.recv(MyObject)) {
        try conn1.handleRetransmissions();
    }
    const cobj2 = obj2.?;
    defer cobj2.deinit();
    try std.testing.expectEqualDeep(obj1, cobj2.inner.*);
}

test "connection over unreliable channel" {
    std.debug.print("connection over unreliable channel\n", .{});
    const mock = layer3.MockChannel.init(std.testing.allocator, 80, true) catch unreachable;
    defer mock.deinit();
    const channel = layer3.Channel(mock);

    const addr = layer3.Address.from(11);

    const obj1 = MyObject{ .hello = 123 };
    var conn1 = Connection(@TypeOf(channel)).init(std.testing.allocator, channel, addr);
    defer conn1.deinit();
    try conn1.send(obj1);

    var conn2 = Connection(@TypeOf(channel)).init(std.testing.allocator, channel, addr);
    defer conn2.deinit();
    var obj2 = try conn2.recv(MyObject);
    while (obj2 == null) : (obj2 = try conn2.recv(MyObject)) {
        try conn1.handleRetransmissions();
    }
    const cobj2 = obj2.?;
    defer cobj2.deinit();
    try std.testing.expectEqualDeep(obj1, cobj2.inner.*);
}

test "big T" {
    std.debug.print("connection\n", .{});
    const mock = layer3.MockChannel.init(std.testing.allocator, 80, false) catch unreachable;
    defer mock.deinit();
    const channel = layer3.Channel(mock);

    const addr = layer3.Address.from(11);

    const obj1: BigObject = undefined;
    var conn1 = Connection(@TypeOf(channel)).init(std.testing.allocator, channel, addr);
    defer conn1.deinit();
    try conn1.send(obj1);

    var conn2 = Connection(@TypeOf(channel)).init(std.testing.allocator, channel, addr);
    defer conn2.deinit();
    var obj2 = try conn2.recv(BigObject);
    while (obj2 == null) : (obj2 = try conn2.recv(BigObject)) {
        try conn1.handleRetransmissions();
    }
    const cobj2 = obj2.?;
    defer cobj2.deinit();
    try std.testing.expectEqualDeep(obj1, cobj2.inner.*);
}

test "packet checksum" {
    var packet = Packet.init();
    packet.calculateChecksum();
    try std.testing.expect(packet.verifyChecksum());
}

test "corrupted packet checksum" {
    var packet = Packet.init();
    packet.calculateChecksum();
    packet.checksum += 1;
    try std.testing.expect(!packet.verifyChecksum());
}

test "sizes" {
    try std.testing.expectEqual(128, @sizeOf(Packet));
}
