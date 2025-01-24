const std = @import("std");
const msdk = @import("msdk");
const messaging = @import("host_messaging.zig");
const shared = @import("shared");

fn irq() callconv(.C) void {
    const temp = msdk.MXC_FLC0.*.intr;

    if (temp & msdk.MXC_F_FLC_INTR_DONE != 0) {
        msdk.MXC_FLC0.*.intr &= ~msdk.MXC_F_FLC_INTR_DONE;
        // messaging.debugMessage(" -> Interrupt! (Flash access done)", .{});
    }

    if (temp & msdk.MXC_F_FLC_INTR_AF != 0) {
        msdk.MXC_FLC0.*.intr &= ~msdk.MXC_F_FLC_INTR_AF;
        // messaging.debugMessage(" -> Interrupt! (Flash access failure)", .{});
    }
}

pub fn init(subscriptions: *[8]?messaging.Subscription) !void {
    msdk.MXC_NVIC_SetVector(msdk.FLC0_IRQn, irq);
    @fence(std.builtin.AtomicOrder.seq_cst);
    msdk.NVIC_EnableIRQ(msdk.FLC0_IRQn);
    @fence(std.builtin.AtomicOrder.seq_cst);
    asm volatile ("cpsie i" ::: "memory");
    try shared.msdkTry(msdk.MXC_FLC_EnableInt(msdk.MXC_F_FLC_INTR_DONEIE | msdk.MXC_F_FLC_INTR_AFIE));
    msdk.MXC_ICC_Disable(msdk.MXC_ICC0);

    var meta: PageMeta = undefined;
    msdk.MXC_FLC_Read(FLASH_START_ADDR, &meta, @sizeOf(@TypeOf(meta)));

    if (meta.first_boot != FIRST_BOOT_MAGIC) {
        meta = .{};

        try shared.msdkTry(msdk.MXC_FLC_PageErase(FLASH_START_ADDR));
        try write(FLASH_START_ADDR, std.mem.asBytes(&meta));
        return;
    }

    for (meta.valid, 1..) |valid, i| {
        if (valid) {
            msdk.MXC_FLC_Read(@intCast(FLASH_START_ADDR + (i * msdk.MXC_FLASH_PAGE_SIZE)), &subscriptions[i - 1], @sizeOf(@TypeOf(subscriptions[i - 1])));
        }
    }
}

fn read(address: usize, v: anytype) void {
    msdk.MXC_FLC_Read(@intCast(address), v, @sizeOf(@TypeOf(v.*)));
}

fn write(address: usize, buffer: []u8) !void {
    try shared.msdkTry(msdk.MXC_FLC_Write(address, buffer.len, @ptrCast(@alignCast(buffer.ptr))));
}

pub fn saveSubscriptions(channelIndex: u3, subscriptions: *[8]?messaging.Subscription) !void {
    var meta = PageMeta{};
    for (subscriptions, 0..) |subscription, i| {
        if (subscription) |_| {
            meta.valid[i] = true;
        }
    }

    messaging.debugMessage("saving channel={}", .{channelIndex});

    const err = msdk.MXC_FLC_PageErase(FLASH_START_ADDR);
    messaging.debugMessage("err={}", .{err});
    // try shared.msdkTry(msdk.MXC_FLC_PageErase(FLASH_START_ADDR));
    // try write(FLASH_START_ADDR, std.mem.asBytes(&meta));

    // const offset = FLASH_START_ADDR + (channelIndex * msdk.MXC_FLASH_PAGE_SIZE);
    // try shared.msdkTry(msdk.MXC_FLC_PageErase(offset));
    // try write(offset, std.mem.asBytes(&subscriptions[channelIndex]));
}

const PageMeta = extern struct {
    first_boot: u64 = FIRST_BOOT_MAGIC,
    valid: [8]bool = std.mem.zeroes([8]bool),
};

const FIRST_BOOT_MAGIC: u64 = 0xba345908903256;

pub const FLASH_START_ADDR = msdk.MXC_FLASH_MEM_BASE + msdk.MXC_FLASH_MEM_SIZE - (10 * msdk.MXC_FLASH_PAGE_SIZE);
// pub const FLASH_START_ADDR = msdk.MXC_FLASH_PAGE_ADDR(msdk.MXC_FLASH_MEM_SIZE / msdk.MXC_FLASH_PAGE_SIZE - 9);
// pub const FLASH_START_ADDR = msdk.MXC_FLASH_PAGE_ADDR(0);

test "size" {
    try std.testing.expectEqual(2040, @sizeOf(messaging.Subscription));
}
