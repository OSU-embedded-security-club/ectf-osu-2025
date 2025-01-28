const std = @import("std");
const msdk = @import("msdk");
const messaging = @import("host_messaging.zig");
const shared = @import("shared");
const root = @import("root");

fn irq() callconv(.C) void {
    const temp = msdk.MXC_FLC0.*.intr;

    if (temp & msdk.MXC_F_FLC_INTR_DONE != 0) {
        msdk.MXC_FLC0.*.intr &= ~msdk.MXC_F_FLC_INTR_DONE;
        messaging.debugMessage(" -> Interrupt! (Flash access done)", .{});
    }

    if (temp & msdk.MXC_F_FLC_INTR_AF != 0) {
        msdk.MXC_FLC0.*.intr &= ~msdk.MXC_F_FLC_INTR_AF;
        messaging.debugMessage(" -> Interrupt! (Flash access failure)", .{});
    }
}

pub fn init() !void {
    msdk.MXC_NVIC_SetVector(msdk.FLC0_IRQn, irq);
    @fence(std.builtin.AtomicOrder.seq_cst);
    msdk.NVIC_EnableIRQ(msdk.FLC0_IRQn);
    @fence(std.builtin.AtomicOrder.seq_cst);
    try shared.msdkTry(msdk.MXC_FLC_EnableInt(msdk.MXC_F_FLC_INTR_DONEIE | msdk.MXC_F_FLC_INTR_AFIE));
    msdk.MXC_ICC_Disable(msdk.MXC_ICC0);

    var meta: PageMeta = undefined;
    msdk.MXC_FLC_Read(FLASH_START_ADDR, &meta, @sizeOf(@TypeOf(meta)));

    if (meta.first_boot != FIRST_BOOT_MAGIC) {
        messaging.debugMessage("First boot!", .{});
        meta = .{};

        try shared.msdkTry(msdk.MXC_FLC_PageErase(FLASH_START_ADDR));
        try write(FLASH_START_ADDR, std.mem.asBytes(&meta));
        return;
    }

    for (meta.valid, 1..) |valid, i| {
        if (valid) {
            messaging.debugMessage("Reading saved subscription {}", .{i});
            root.subscriptions[i - 1] = messaging.Subscription{
                .start = 0,
                .end = 0,
            };
            msdk.MXC_FLC_Read(@intCast(FLASH_START_ADDR + (i * msdk.MXC_FLASH_PAGE_SIZE)), &root.subscriptions[i - 1].?, @sizeOf(@TypeOf(root.subscriptions[i - 1].?)));
        }
    }
}

fn read(address: usize, v: anytype) void {
    msdk.MXC_FLC_Read(@intCast(address), v, @sizeOf(@TypeOf(v.*)));
}

fn write(address: usize, buffer: []u8) !void {
    try shared.msdkTry(msdk.MXC_FLC_Write(address, buffer.len, @ptrCast(@alignCast(buffer.ptr))));
}

pub fn saveSubscriptions(channelIndex: u3) !void {
    var meta = PageMeta{};
    for (root.subscriptions, 0..) |subscription, i| {
        if (subscription) |_| {
            meta.valid[i] = true;
        }
    }

    messaging.debugMessage("saving channel={}", .{channelIndex});

    try shared.msdkTry(msdk.MXC_FLC_PageErase(FLASH_START_ADDR));
    try write(FLASH_START_ADDR, std.mem.asBytes(&meta));

    const addr = FLASH_START_ADDR + msdk.MXC_FLASH_PAGE_SIZE * (@as(usize, channelIndex) + 1);
    try shared.msdkTry(msdk.MXC_FLC_PageErase(addr));
    try write(addr, std.mem.asBytes(&root.subscriptions[channelIndex].?));
}

const PageMeta = extern struct {
    first_boot: u64 = FIRST_BOOT_MAGIC,
    valid: [8]bool = std.mem.zeroes([8]bool),
};

const FIRST_BOOT_MAGIC: u64 = 0xdeadbeefcafebabe;

pub const FLASH_START_ADDR = msdk.MXC_FLASH_MEM_BASE + msdk.MXC_FLASH_MEM_SIZE - (10 * msdk.MXC_FLASH_PAGE_SIZE);
