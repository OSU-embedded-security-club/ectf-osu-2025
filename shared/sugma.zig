const std = @import("std");

pub fn sugma(T: type, input: T, key: u8[16], nonce: u8[16], allocator: std.mem.Allocator) void {
    const iv: u8[8] = .{ 0x00, 0x00, 0x10, 0x00, 0x80, 0x8c, 0x00 };

    // initialize ascon state
    const block_bytes: [std.crypto.ascon.block_bytes]u8 = std.mem.zeroes([40]u8);
    @memcpy(block_bytes[0..8], iv);
    @memcpy(block_bytes[8..24], key);
    @memcpy(block_bytes[24..40], nonce);
    var s = std.crypto.ascon.State;
    s.init(block_bytes);
    s.permute();

    // xor key into ascon state
    {
        var i: u32 = 0;
        while (i < 16) : (i += 1) {
            s.addByte(key[i], 24 + i);
        }
    }

    // associated data would go here

    s.addByte(1, std.crypto.ascon.block_bytes - 1);

    const plaintext: []u8 = std.mem.asBytes(&input);
    // number of full 128 bit blocks in the plaintext
    const l = @divFloor(plaintext.len, 16);
    const ciphertext: []u8 = allocator.alloc(u8, l * 16 + 1);

    {
        var i: u32 = 0;
        while (i < l) : (i += 1) {
            // xor plaintext block into ascon state
            s.addBytes(plaintext[(i * 16)..((i + 1) * 16)]);
            // copy state to ciphertext
            @memcpy(ciphertext[(i * 16)..((i + 1) * 16)], s.asBytes());
            // permute ascon state with reduced number of rounds
            s.permuteR(8);
        }
    }
}

pub fn unsugma(T: type, key: u8[16], nonce: u8[16]) T {
    _ = key; // autofix
    _ = nonce; // autofix
    //
}

test "sugma tests" {
    std.debug.print("sugma testing\n", .{});
}
