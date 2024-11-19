const std = @import("std");

const layer3 = @import("layer3.zig");

const shared = @import("main.zig");
const Owned = shared.Owned;
const toOwned = shared.toOwned;

pub const ConnectionError = error{
    Timeout,
    UnexpectedPacket,
    MaxRetriesExceeded,
    StopTheCount,
} || layer3.ChannelError;

const Flags = packed struct {
    is_ack: bool,
    _: u7 = 0,
};

// Simple packet structure with checksum
pub const Packet = extern struct {
    const data_size = 110;
    seq_num: u32 align(1),
    ack_num: u32 align(1),
    index: u32 align(1),
    flags: Flags align(1),
    checksum: u32 align(1),
    data_len: u8 align(1),
    data: [data_size]u8 align(1),

    pub fn init() Packet {
        return .{
            .seq_num = 0,
            .ack_num = 0,
            .index = 0,
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

/// Reliable connection over an unreliable channel. Can send arbitrarily large data over the channel.
pub fn Connection(comptime ChannelImpl: type) type {
    return struct {
        const Self = @This();
        const num_unacked_packets = 10;
        const num_retries = 3;
        const global_timeout = 5 * 1000;

        channel: layer3.ChannelInner(ChannelImpl),
        address: layer3.Address,

        allocator: std.mem.Allocator,
        seq_num: u32 = 0,

        unacked_packets: [num_unacked_packets]UnackedPacket = undefined,
        unacked_packets_tail_index: usize = 0,
        unacked_packets_head_index: usize = 0,

        buffer: [@sizeOf(Packet)]u8 = undefined,
        buffer_size: usize = 0,

        const UnackedPacket = struct {
            packet: Packet,
            last_sent: i64,
            retries: u32 = 0,
        };

        pub fn init(allocator: std.mem.Allocator, channel: ChannelImpl, address: layer3.Address) Self {
            return .{
                .channel = layer3.Channel(channel),
                .address = address,
                .allocator = allocator,
            };
        }

        /// Blocks until all data is sent and successfully acknowledged by the receiver.
        /// Will return early if there is an error or the connection times out.
        pub fn send(self: *Self, data: anytype) ConnectionError!void {
            const T = @TypeOf(data);
            const bytes = std.mem.asBytes(&data);

            var remaining: usize = @sizeOf(T) / Packet.data_size;
            if (@mod(@sizeOf(T), Packet.data_size) != 0) remaining += 1;

            var offset: usize = 0;
            var index: u32 = 0;

            var timeout: i64 = 0;
            while (true) {
                if (remaining == 0 and timeout == 0) {
                    std.debug.print("SENDER: sent all packets, starting timeout\n", .{});
                    // if we ware done sending, start a timeout
                    timeout = std.time.milliTimestamp();
                }
                if (remaining > 0 and self.unacked_packets_head_index - self.unacked_packets_tail_index < num_unacked_packets) {
                    remaining -= 1;
                    // only send a chunk if we have room in our unacked packets
                    const end = @min(offset + Packet.data_size, bytes.len);
                    const chunk = bytes[offset..end];
                    offset += chunk.len;

                    var packet = Packet.init();
                    packet.seq_num = self.seq_num;
                    packet.index = index;
                    packet.data_len = @intCast(chunk.len);
                    @memcpy(packet.data[0..chunk.len], chunk);

                    self.unacked_packets[@mod(self.unacked_packets_head_index, num_unacked_packets)] = .{
                        .packet = packet,
                        .last_sent = std.time.milliTimestamp(),
                    };
                    self.unacked_packets_head_index += 1;

                    self.seq_num += 1;
                    index += 1;
                    std.debug.print("SEND len={}, seq_num={}, index={}\n", .{ packet.data_len, packet.seq_num, packet.index });
                    try self.sendPacket(&packet);
                } else if (timeout == 0) {
                    std.debug.print("SENDER: not receiving acks, starting timeout\n", .{});
                    // receiver might have disconnected
                    timeout = std.time.milliTimestamp();
                }

                if (try self.recvPacket()) |packet| {
                    if (!packet.flags.is_ack) return error.UnexpectedPacket;

                    // find the packet to ack
                    var pos: usize = self.unacked_packets_tail_index;
                    while (pos < self.unacked_packets_head_index) : (pos += 1) {
                        const i = @mod(pos, num_unacked_packets);
                        if (self.unacked_packets[i].packet.seq_num == packet.ack_num) {
                            const last_tail = @mod(self.unacked_packets_tail_index, num_unacked_packets);
                            if (last_tail != i) self.unacked_packets[i] = self.unacked_packets[last_tail];

                            self.unacked_packets_tail_index += 1;
                            if (self.unacked_packets_tail_index >= num_unacked_packets) {
                                self.unacked_packets_tail_index -= num_unacked_packets;
                                self.unacked_packets_head_index -= num_unacked_packets;
                            }

                            timeout = std.time.milliTimestamp();
                            std.debug.print("ACKN ack_num={}\n", .{packet.ack_num});
                            break;
                        }
                    }
                }

                const current_time = std.time.milliTimestamp();

                if (timeout != 0 and current_time - timeout > global_timeout) {
                    return;
                }

                var pos: usize = self.unacked_packets_tail_index;
                while (pos < self.unacked_packets_head_index) : (pos += 1) {
                    const i = @mod(pos, num_unacked_packets);
                    const unacked = &self.unacked_packets[i];
                    if (current_time - unacked.last_sent > 1000) {
                        if (unacked.retries >= num_retries) {
                            return error.MaxRetriesExceeded;
                        }
                        std.debug.print("RETX seq_num={}\n", .{unacked.packet.seq_num});
                        try self.sendPacket(&unacked.packet);
                        unacked.last_sent = current_time;
                        unacked.retries += 1;
                    }
                }

                if (remaining == 0 and self.unacked_packets_head_index == self.unacked_packets_tail_index) {
                    return;
                }
            }
        }

        /// Blocks until all data is received. Will return early if there is an error or the connection times out.
        pub fn recv(self: *Self, comptime T: type) ConnectionError!Owned(*T) {
            const result = try self.allocator.create(T);
            errdefer self.allocator.destroy(result);
            const result_bytes = std.mem.asBytes(result);
            var remaining: usize = @sizeOf(T) / Packet.data_size;
            if (@mod(@sizeOf(T), Packet.data_size) != 0) remaining += 1;
            var num_received_bytes: usize = 0;

            std.debug.print("RECEIVER: remaining={}\n", .{remaining});

            var timeout = std.time.milliTimestamp();

            while (remaining > 0) {
                const currentTime = std.time.milliTimestamp();
                if (try self.recvPacket()) |packet| {
                    if (packet.flags.is_ack) return error.UnexpectedPacket;

                    std.debug.print("RECV len={}, seq_num={}, index={}\n", .{ packet.data_len, packet.seq_num, packet.index });

                    var ack_packet = Packet.init();
                    ack_packet.flags.is_ack = true;
                    ack_packet.ack_num = packet.seq_num;
                    try self.sendPacket(&ack_packet);

                    const offset = packet.index * Packet.data_size;
                    const len = @min(Packet.data_size, packet.data_len);
                    if (offset + len > @sizeOf(T)) {
                        return error.StopTheCount;
                    }

                    @memcpy(result_bytes[offset .. offset + len], packet.data[0..len]);
                    remaining -= 1;
                    num_received_bytes += len;

                    timeout = currentTime;
                }

                if (currentTime - timeout > global_timeout) {
                    return error.Timeout;
                }
            }

            if (num_received_bytes != @sizeOf(T)) {
                return error.StopTheCount;
            }

            return toOwned(result, self.allocator);
        }

        fn sendPacket(self: *Self, packet: *Packet) !void {
            packet.calculateChecksum();
            const bytes = std.mem.asBytes(packet);
            try self.channel.send(bytes, self.address);

            // std.debug.print("Sending packet: seq={}, ack={}, is_ack={}\n", .{
            //     packet.seq_num,
            //     packet.ack_num,
            //     packet.flags.is_ack,
            // });
        }

        fn recvPacket(self: *Self) !?Packet {
            if (try self.channel.recv(self.address)) |data| {
                std.debug.assert(data.inner.len <= @sizeOf(Packet));
                defer data.deinit();

                const remaining_bytes = @sizeOf(Packet) - self.buffer_size;
                if (data.inner.len < remaining_bytes) {
                    @memcpy(self.buffer[self.buffer_size .. self.buffer_size + data.inner.len], data.inner);
                    self.buffer_size += data.inner.len;
                    return null;
                }

                @memcpy(self.buffer[self.buffer_size..@sizeOf(Packet)], data.inner[0..remaining_bytes]);
                const packet_ptr: *Packet = @ptrCast(&self.buffer[0]);
                const packet = packet_ptr.*;

                self.buffer_size = data.inner.len - remaining_bytes;
                @memcpy(self.buffer[0..self.buffer_size], data.inner[remaining_bytes..]);

                if (!packet.verifyChecksum()) {
                    std.debug.print("DROP packet failed checksum seq_num={}\n", .{packet.seq_num});
                    return null;
                }

                return packet;
            }
            return null;
        }
    };
}

fn initBytes(num_bytes: comptime_int) [num_bytes]u8 {
    var result: [num_bytes]u8 = undefined;
    for (&result, 0..) |*b, i| {
        b.* = @truncate(i);
    }
    return result;
}

test "connection" {
    std.debug.print("\nTEST: connection\n", .{});
    const mocks = try layer3.MockChannel.init(std.testing.allocator, 80, false);
    defer mocks.deinit();

    const addr = layer3.Address.from(11);

    const channel1 = layer3.Channel(mocks.to);
    const obj1 = initBytes(1);
    var conn1 = Connection(@TypeOf(channel1)).init(std.testing.allocator, channel1, addr);

    const thread = try std.Thread.spawn(.{}, struct {
        fn run(conn: *@TypeOf(conn1), obj: *const @TypeOf(obj1)) void {
            conn.send(obj.*) catch @panic("failed to send");
        }
    }.run, .{ &conn1, &obj1 });
    defer thread.join();

    const channel2 = layer3.Channel(mocks.from);
    var conn2 = Connection(@TypeOf(channel2)).init(std.testing.allocator, channel2, addr);
    const obj2 = try conn2.recv(@TypeOf(obj1));
    defer obj2.deinit();
    try std.testing.expectEqualDeep(obj1, obj2.inner.*);
}

test "connection over big T" {
    std.debug.print("\nTEST: connection over big T\n", .{});
    const mocks = try layer3.MockChannel.init(std.testing.allocator, 80, false);
    defer mocks.deinit();

    const addr = layer3.Address.from(11);
    const obj1 = initBytes(Packet.data_size * 111 + 1);

    const channel1 = layer3.Channel(mocks.to);
    var conn1 = Connection(@TypeOf(channel1)).init(std.testing.allocator, channel1, addr);

    const thread = try std.Thread.spawn(.{}, struct {
        fn run(conn: *@TypeOf(conn1), obj: *const @TypeOf(obj1)) void {
            conn.send(obj.*) catch @panic("failed to send");
        }
    }.run, .{ &conn1, &obj1 });
    defer thread.join();

    const channel2 = layer3.Channel(mocks.from);
    var conn2 = Connection(@TypeOf(channel2)).init(std.testing.allocator, channel2, addr);
    const obj2 = try conn2.recv(@TypeOf(obj1));
    defer obj2.deinit();
    try std.testing.expectEqualDeep(obj1, obj2.inner.*);
}

test "connection over unreliable channel" {
    std.debug.print("\nTEST: connection over unreliable channel\n", .{});
    const mocks = try layer3.MockChannel.init(std.testing.allocator, 80, true);
    defer mocks.deinit();

    const addr = layer3.Address.from(11);
    const obj1 = initBytes(2048);

    const channel1 = layer3.Channel(mocks.to);
    var conn1 = Connection(@TypeOf(channel1)).init(std.testing.allocator, channel1, addr);

    const thread = try std.Thread.spawn(.{}, struct {
        fn run(conn: *@TypeOf(conn1), obj: *const @TypeOf(obj1)) void {
            conn.send(obj.*) catch @panic("failed to send");
        }
    }.run, .{ &conn1, &obj1 });
    defer thread.join();

    const channel2 = layer3.Channel(mocks.from);
    var conn2 = Connection(@TypeOf(channel2)).init(std.testing.allocator, channel2, addr);
    const obj2 = try conn2.recv(@TypeOf(obj1));
    defer obj2.deinit();
    try std.testing.expectEqualDeep(obj1, obj2.inner.*);
}

test "connection transmitting multiple Ts" {
    std.debug.print("\nTEST: connection transmitting multiple Ts\n", .{});
    const mocks = try layer3.MockChannel.init(std.testing.allocator, 80, false);
    defer mocks.deinit();

    const addr = layer3.Address.from(11);

    const channel1 = layer3.Channel(mocks.to);
    var conn1 = Connection(@TypeOf(channel1)).init(std.testing.allocator, channel1, addr);

    const obj1 = initBytes(12);
    const obj2 = initBytes(123);

    const thread = try std.Thread.spawn(.{}, struct {
        fn run(conn: *@TypeOf(conn1), a: *const @TypeOf(obj1), b: *const @TypeOf(obj2)) void {
            conn.send(a.*) catch @panic("failed to send (a)");
            conn.send(b.*) catch @panic("failed to send (b)");
        }
    }.run, .{ &conn1, &obj1, &obj2 });
    defer thread.join();

    const channel2 = layer3.Channel(mocks.from);
    var conn2 = Connection(@TypeOf(channel2)).init(std.testing.allocator, channel2, addr);

    const obj1r = try conn2.recv(@TypeOf(obj1));
    defer obj1r.deinit();
    try std.testing.expectEqualDeep(obj1, obj1r.inner.*);

    const obj12r = try conn2.recv(@TypeOf(obj2));
    defer obj12r.deinit();
    try std.testing.expectEqualDeep(obj2, obj12r.inner.*);
}

test "connection send with no receiver" {
    std.debug.print("\nTEST: connection send with no receiver\n", .{});
    const mocks = try layer3.MockChannel.init(std.testing.allocator, 80, false);
    defer mocks.deinit();

    const addr = layer3.Address.from(11);

    const channel = layer3.Channel(mocks.to);
    var conn = Connection(@TypeOf(channel)).init(std.testing.allocator, channel, addr);

    const obj = initBytes(12);
    const result = conn.send(obj);
    try std.testing.expectError(error.MaxRetriesExceeded, result);
}

test "connection receive with no sender" {
    std.debug.print("\nTEST: connection receive with no sender\n", .{});
    const mocks = try layer3.MockChannel.init(std.testing.allocator, 80, false);
    defer mocks.deinit();

    const addr = layer3.Address.from(11);

    const channel = layer3.Channel(mocks.from);
    var conn = Connection(@TypeOf(channel)).init(std.testing.allocator, channel, addr);

    const result = conn.recv(u32);
    try std.testing.expectError(error.Timeout, result);
}

test "packet checksum" {
    var packet = Packet.init();
    packet.calculateChecksum();
    try std.testing.expect(packet.verifyChecksum());
}

test "corrupted packet checksum" {
    var packet = Packet.init();
    packet.calculateChecksum();
    packet.data[13] += 2;
    try std.testing.expect(!packet.verifyChecksum());
}

test "sizes" {
    try std.testing.expectEqual(128, @sizeOf(Packet));
}
