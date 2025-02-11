const std = @import("std");
const root = @import("root");

const messaging = @import("messaging.zig");

pub const max_message_size = @sizeOf(ListChannelResponse);

pub const SubscriptionEntry = extern struct {
    channel_id: u32 align(1),
    start: u64 align(1),
    end: u64 align(1),
};

const ListChannelResponse = extern struct {
    num_channels: u32 align(1),
    subscriptions: [8]SubscriptionEntry align(1) = undefined,

    fn asBytes(self: *ListChannelResponse) []const u8 {
        const size = @sizeOf(@TypeOf(self.num_channels)) + @sizeOf(SubscriptionEntry) * self.num_channels;
        return std.mem.asBytes(self)[0..size];
    }
};

pub fn execute() !void {
    var list_channel_response = ListChannelResponse{ .num_channels = 0 };

    var channel_index: usize = 0;
    for (root.subscriptions) |subscription| {
        if (subscription) |sub| {
            list_channel_response.subscriptions[channel_index] = SubscriptionEntry{
                .channel_id = sub.serialized.channel_id,
                .start = sub.serialized.start,
                .end = sub.serialized.end,
            };
            channel_index += 1;
        }
    }
    list_channel_response.num_channels = channel_index;

    const body = list_channel_response.asBytes();

    try messaging.sendWithAcks('L', body);
}
