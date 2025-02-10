const std = @import("std");

pub fn decrypt(data: []u8, key: [24]u8) void {
    var extended_key: [32]u8 = undefined;
    @memcpy(extended_key[0..24], key[0..24]);
    @memcpy(extended_key[24..32], key[0..8]);
    std.crypto.stream.salsa.Salsa20.xor(data, data, 0, extended_key, std.mem.zeroes([8]u8));
}
