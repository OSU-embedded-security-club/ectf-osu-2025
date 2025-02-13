//! Cryptographic utilities

const std = @import("std");

/// Decrypt `data` using 24 byte `key` with Salsa20, and a nonce of 0. Use this
/// only for decrypting frame data
pub fn decrypt(data: []u8, key: [24]u8) void {
    var extended_key: [32]u8 = undefined;
    @memcpy(extended_key[0..24], key[0..24]);
    @memcpy(extended_key[24..32], key[0..8]);
    std.crypto.stream.salsa.Salsa20.xor(data, data, 0, extended_key, std.mem.zeroes([8]u8));
}
