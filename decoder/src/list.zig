//! List command

const std = @import("std");

const main = @import("main.zig");
const messaging = @import("messaging.zig");

/// A single entry in the list response of subscriptions
/// https://rules.ectf.mitre.org/2025/specs/detailed_specs.html#id6
pub const SubscriptionEntry = extern struct {
    channel_id: u32 align(1),
    start: u64 align(1),
    end: u64 align(1),
};

/// The decoder response to a list command in correct byte order
/// https://rules.ectf.mitre.org/2025/specs/detailed_specs.html#decoder-response
const ListChannelResponse = extern struct {
    num_channels: u32 align(1) = 0,
    subscriptions: [8]SubscriptionEntry align(1) = undefined,

    /// Initialize a `ListChannelResponse`, filling in subscription metadata
    /// from the global `subscriptions` list
    pub fn init() ListChannelResponse {
        var self = ListChannelResponse{};

        for (main.subscriptions) |subscription| if (subscription) |sub| {
            self.subscriptions[self.num_channels] = SubscriptionEntry{
                .channel_id = sub.serialized.channel_id,
                .start = sub.serialized.start,
                .end = sub.serialized.end,
            };
            self.num_channels += 1;
        };

        return self;
    }

    /// Get underlying bytes of self, up to the number of subscripts
    fn asBytes(self: *ListChannelResponse) []const u8 {
        const size = @sizeOf(@TypeOf(self.num_channels)) + @sizeOf(SubscriptionEntry) * self.num_channels;
        return std.mem.asBytes(self)[0..size];
    }
};

/// Send a List Channels response
pub fn execute() !void {
    var list_channel_response = ListChannelResponse.init();
    try messaging.sendWithAcks(.List, list_channel_response.asBytes());
}
