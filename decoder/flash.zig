const std = @import("std");
const msdk = @import("msdk");
const messaging = @import("messaging.zig");
const lib = @import("lib");
const root = @import("root");

fn irq() callconv(.C) void {
    const temp = msdk.MXC_FLC0.*.intr;

    if (temp & msdk.MXC_F_FLC_INTR_DONE != 0) {
        msdk.MXC_FLC0.*.intr &= ~msdk.MXC_F_FLC_INTR_DONE;
        messaging.sendDebug(" -> Interrupt! (Flash access done)", .{});
    }

    if (temp & msdk.MXC_F_FLC_INTR_AF != 0) {
        msdk.MXC_FLC0.*.intr &= ~msdk.MXC_F_FLC_INTR_AF;
        messaging.sendDebug(" -> Interrupt! (Flash access failure)", .{});
    }
}

pub fn init() !void {
    msdk.MXC_NVIC_SetVector(msdk.FLC0_IRQn, irq);
    @fence(std.builtin.AtomicOrder.seq_cst);
    msdk.NVIC_EnableIRQ(msdk.FLC0_IRQn);
    @fence(std.builtin.AtomicOrder.seq_cst);
    try lib.msdkTry(msdk.MXC_FLC_EnableInt(msdk.MXC_F_FLC_INTR_DONEIE | msdk.MXC_F_FLC_INTR_AFIE));
    msdk.MXC_ICC_Disable(msdk.MXC_ICC0);

    var meta: PageMeta = undefined;
    msdk.MXC_FLC_Read(flash_start_address, &meta, @sizeOf(@TypeOf(meta)));

    if (meta.first_boot != first_boot_magic) {
        messaging.sendDebug("First boot!", .{});
        meta = .{};

        try lib.msdkTry(msdk.MXC_FLC_PageErase(flash_start_address));
        try write(flash_start_address, std.mem.asBytes(&meta));
        return;
    }

    for (meta.valid, 1..) |valid, i| {
        if (valid) {
            var subscription_bytes: lib.Subscription.Bytes = undefined;
            read(flash_start_address + (i * msdk.MXC_FLASH_PAGE_SIZE), &subscription_bytes);
            root.subscriptions[i - 1] = lib.Subscription.init(
                subscription_bytes.channel_id,
                subscription_bytes.start,
                subscription_bytes.end,
                std.mem.asBytes(&subscription_bytes.root_hashes),
            );
        }
    }
}

fn read(address: usize, v: anytype) void {
    msdk.MXC_FLC_Read(@intCast(address), v, @sizeOf(@TypeOf(v.*)));
}

fn write(address: usize, buffer: []u8) !void {
    try lib.msdkTry(msdk.MXC_FLC_Write(address, buffer.len, @ptrCast(@alignCast(buffer.ptr))));
}

pub fn saveSubscriptions(channel_index: u3) !void {
    var meta = PageMeta{};
    for (root.subscriptions, 0..) |subscription, i| {
        if (subscription) |_| {
            meta.valid[i] = true;
        }
    }

    try lib.msdkTry(msdk.MXC_FLC_PageErase(flash_start_address));
    try write(flash_start_address, std.mem.asBytes(&meta));

    const addr = flash_start_address + msdk.MXC_FLASH_PAGE_SIZE * (@as(usize, channel_index) + 1);
    try lib.msdkTry(msdk.MXC_FLC_PageErase(addr));
    try write(addr, std.mem.asBytes(&root.subscriptions[channel_index].?));
}

const PageMeta = extern struct {
    first_boot: u64 = first_boot_magic,
    valid: [8]bool = std.mem.zeroes([8]bool),
};

const first_boot_magic: u64 = 0xdeadbeefcafebabe;
const flash_start_address = msdk.MXC_FLASH_MEM_BASE + msdk.MXC_FLASH_MEM_SIZE - (10 * msdk.MXC_FLASH_PAGE_SIZE);
