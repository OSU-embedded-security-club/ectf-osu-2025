//! High level Zig wrapper over the MSDK to interact with the 512KB flash on the
//! MAX78000. Roughly a translation of `simple_flash.c` from the insecure example
//!
//! Flash layout by pages:
//! 0-27   Encrypted firmware
//! 28-51  Unused
//! 52     Metadata
//! 53-61  Subscriptions (1 per channel, 8 total)
//! 62-63  Unused

const std = @import("std");
const msdk = @import("msdk");
const lib = @import("lib");
const root = @import("root");
const secrets = @import("secrets");

const messaging = @import("messaging.zig");

/// Interrupt Request handler
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

/// Initialize flash, and read in any saved subscriptions into RAM
pub fn init() !void {
    msdk.MXC_NVIC_SetVector(msdk.FLC0_IRQn, irq);

    // Zig has some trouble translating `NVIC_EnableIRQ` so we help out its
    // missing `__COMPILER_BARRIER();` by adding our own fences
    @fence(std.builtin.AtomicOrder.seq_cst);
    msdk.NVIC_EnableIRQ(msdk.FLC0_IRQn);
    @fence(std.builtin.AtomicOrder.seq_cst);

    try lib.msdkTry(msdk.MXC_FLC_EnableInt(msdk.MXC_F_FLC_INTR_DONEIE | msdk.MXC_F_FLC_INTR_AFIE));
    msdk.MXC_ICC_Disable(msdk.MXC_ICC0);

    var meta: FlashMeta = undefined;
    read(flash_start_address, &meta);

    // Make sure the flash is in a valid state by initializing the metadata page
    // on the first boot
    if (meta.isFirstBoot()) {
        meta = .{};
        try write(flash_start_address, std.mem.asBytes(&meta));
        return;
    }

    // Read in the valid subscriptions and initialize them
    for (meta.valid, 1..) |valid, i| if (valid) {
        var subscription_bytes: lib.Subscription.Bytes = undefined;
        read(flash_start_address + (i * msdk.MXC_FLASH_PAGE_SIZE), &subscription_bytes);
        root.subscriptions[i - 1] = lib.Subscription.init(
            subscription_bytes.channel_id,
            subscription_bytes.start,
            subscription_bytes.end,
            std.mem.asBytes(&subscription_bytes.root_hashes),
        );
    };
}

/// All flash pages are encrypted at rest. To prevent nonce reuse, we keep track
/// of the which nonce to use next
var global_nonce: u64 = 0;

/// Read from `address` in the flash into `ptr`
fn read(address: usize, ptr: anytype) void {
    comptime std.debug.assert(8192 >= @sizeOf(@TypeOf(global_nonce)) + @sizeOf(@TypeOf(ptr.*)));

    // First read the nonce stored at the beginning of the flash page, and
    // potentially update the global nonce if this nonce is bigger (to prevent
    // nonce reuse)
    var nonce: @TypeOf(global_nonce) = undefined;
    msdk.MXC_FLC_Read(@intCast(address), &nonce, @sizeOf(@TypeOf(nonce)));
    global_nonce = @max(global_nonce, nonce);

    // Read the rest of the bytes into `ptr`, and decrypt it
    msdk.MXC_FLC_Read(@intCast(address + @sizeOf(@TypeOf(global_nonce))), ptr, @sizeOf(@TypeOf(ptr.*)));
    const bytes = std.mem.asBytes(ptr);
    std.crypto.stream.salsa.Salsa20.xor(bytes, bytes, 0, secrets.flash_at_rest_key, std.mem.toBytes(nonce));
}

/// Write `bytes` to `address` in the flash. Transparently encrypts the data
/// before writing to flash
fn write(address: usize, bytes: []u8) !void {
    std.debug.assert(8192 >= @sizeOf(@TypeOf(global_nonce)) + bytes.len);

    // Increment the nonce so we don't reuse nonces
    global_nonce +%= 1;

    // This encrypts the underlying bytes, which is problematic because after
    // this function returns, the bytes will be garbled. So, once we are done
    // writing it to flash, we need to decrypt the underlying bytes back
    std.crypto.stream.salsa.Salsa20.xor(bytes, bytes, 0, secrets.flash_at_rest_key, std.mem.toBytes(global_nonce));
    defer std.crypto.stream.salsa.Salsa20.xor(bytes, bytes, 0, secrets.flash_at_rest_key, std.mem.toBytes(global_nonce));

    // Erase the page at the `address`, write the nonce in plaintext first, then
    // write the encrypted `bytes` in
    try lib.msdkTry(msdk.MXC_FLC_PageErase(address));
    try lib.msdkTry(msdk.MXC_FLC_Write(address, @sizeOf(@TypeOf(global_nonce)), @ptrCast(&global_nonce)));
    try lib.msdkTry(msdk.MXC_FLC_Write(address + @sizeOf(@TypeOf(global_nonce)), bytes.len, @ptrCast(@alignCast(bytes.ptr))));
}

/// Write the compressed form of the subscription corresponding to the
/// `channel_index` to flash.
///
/// This incurs 2 flash writes, one to the page storing the metadata about which
/// channels have valid subscriptions, and one to the page for that particular
/// subscription
pub fn saveSubscriptions(channel_index: u3) !void {
    // Create the metadata storing which subscriptions are active
    var meta = FlashMeta{};
    for (root.subscriptions, 0..) |subscription, i| if (subscription) |_| {
        meta.valid[i] = true;
    };

    // Write metadata page
    try write(flash_start_address, std.mem.asBytes(&meta));

    // Write the subscription to the right page in flash
    const addr = flash_start_address + msdk.MXC_FLASH_PAGE_SIZE * (@as(usize, channel_index) + 1);
    try write(addr, root.subscriptions[channel_index].?.asBytes());
}

const FlashMeta = extern struct {
    /// Magic value used to identify if the page of flash metadata has been
    /// written to before or not
    const first_boot_magic: u64 = 0xdeadbeefcafebabe;

    magic: u64 = first_boot_magic,

    /// Which subscriptions are valid
    valid: [8]bool = std.mem.zeroes([8]bool),

    /// Checks magic to determine if this struct has been initialized properly,
    /// if it hasn't that means it is the first time we have booted
    fn isFirstBoot(self: *FlashMeta) bool {
        return self.magic != first_boot_magic;
    }
};

/// Address of the start of the area in flash that we write to. We start at the
/// 10th to last page (out of 64). Each page is 8KB
const flash_start_address = msdk.MXC_FLASH_MEM_BASE + msdk.MXC_FLASH_MEM_SIZE - (10 * msdk.MXC_FLASH_PAGE_SIZE);
