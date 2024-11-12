const std = @import("std");

/// Does cool stuff
pub fn hi() i32 {
    std.debug.print("Hello, world!\n", .{});
    return 1;
}

test "one" {
    const a = hi();
    const b = 2;
    try std.testing.expectEqual(a + b, 3);
}
