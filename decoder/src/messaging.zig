//! Host messaging tools
//!
//! This implements the decoder interface to be able to interact with the host
//! tools as specified by:
//! https://rules.ectf.mitre.org/2025/specs/detailed_specs.html#decoder-interface

const std = @import("std");
const msdk = @import("msdk");

const main = @import("main.zig");
const flash = @import("flash.zig");
const uart = @import("uart.zig");

/// Magic byte as specified by the decoder interface
pub const magic = '%';

/// Opcodes the decoder needs to handle which come from the host tools
pub const RecvOpcode = enum {
    Decode,
    Subscribe,
    List,
    Ack,

    /// Convert a raw byte into a `RecvOpcode`, or error if it is invalid
    pub inline fn fromByte(byte: u8) !RecvOpcode {
        return switch (byte) {
            'D' => RecvOpcode.Decode,
            'S' => RecvOpcode.Subscribe,
            'L' => RecvOpcode.List,
            'A' => RecvOpcode.Ack,
            else => return error.InvalidOpcode,
        };
    }
};

/// Opcodes the decoder needs to send to the host
pub const SendOpcode = enum {
    Decode,
    Subscribe,
    List,
    Ack,
    Error,
    Debug,

    /// Serialize this opcode into a raw byte per the specification
    inline fn toByte(self: SendOpcode) u8 {
        return switch (self) {
            .Decode => 'D',
            .Subscribe => 'S',
            .List => 'L',
            .Ack => 'A',
            .Error => 'E',
            .Debug => 'G',
        };
    }
};

/// Representation of a header in the host messaging format
const Header = struct {
    opcode: SendOpcode,
    length: u16 = 0,

    /// Serialize this header into the wire format
    pub fn asBytes(self: Header) [4]u8 {
        const len: u16 = @truncate(self.length);
        return [4]u8{ magic, self.opcode.toByte(), @truncate(len), @truncate(len >> 8) };
    }
};

/// Block until we receive an ACK from the host
fn waitForAck() !void {
    while (true) {
        while (try uart.readByte() != magic) {}

        const opcode = try RecvOpcode.fromByte(try uart.readByte());
        if (opcode != .Ack) continue;

        const higher_length = try uart.readByte();
        if (higher_length != 0) continue;

        const lower_length = try uart.readByte();
        if (lower_length != 0) continue;

        break;
    }
}

/// Send a message of kind `opcode` to the host with a body of `bytes`, ACKing
/// every 256 bytes
pub fn sendWithAcks(opcode: SendOpcode, bytes: []const u8) !void {
    var header = Header{ .opcode = opcode, .length = @intCast(bytes.len) };
    uart.writeBytes(&header.asBytes());
    try waitForAck();

    var i: usize = 0;
    while (i < bytes.len) : (i += 256) {
        uart.writeBytes(bytes[i..@min(i + 256, bytes.len)]);
        try waitForAck();
    }
}

/// Send a single ACK to the host
pub fn sendAck() void {
    sendDebug("about to ACK", .{});

    const packet = Header{ .opcode = .Ack };
    uart.writeBytes(&packet.asBytes());
}

/// Temporary buffer for the formatter to write to for `sendDebug` and `sendError`
var message_buffer: [64]u8 = undefined;

/// Send a Debug message to the host
pub fn sendDebug(comptime format: []const u8, args: anytype) void {
    const text = std.fmt.bufPrint(&message_buffer, format, args) catch @panic("Message too big");

    const header = Header{ .opcode = .Debug, .length = @truncate(text.len) };
    uart.writeBytes(&header.asBytes());

    uart.writeBytes(text);
}

/// Send an Error message to the host
pub fn sendError(comptime format: []const u8, args: anytype) void {
    const text = std.fmt.bufPrint(&message_buffer, format, args) catch @panic("Message too big");

    sendWithAcks(.Error, text) catch @panic("Error while sending error");
}
