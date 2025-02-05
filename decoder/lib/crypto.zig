const std = @import("std");

pub fn decrypt(data: []u8, key: [16]u8) void {
    var extended_key: [32]u8 = undefined;
    @memcpy(extended_key[0..16], key[0..16]);
    @memcpy(extended_key[16..32], key[0..16]);
    std.crypto.stream.salsa.Salsa20.xor(data, data, 0, extended_key, std.mem.zeroes([8]u8));
}
