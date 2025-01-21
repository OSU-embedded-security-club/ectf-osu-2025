const std = @import("std");
const msdk = @import("msdk");
const messaging = @import("host_messaging.zig");
const shared = @import("shared");

fn flash_simple_irq() callconv(.C) void {
    const temp = msdk.MXC_FLC0.*.intr;

    if (temp & msdk.MXC_F_FLC_INTR_DONE != 0) {
        msdk.MXC_FLC0.*.intr &= ~msdk.MXC_F_FLC_INTR_DONE;
        messaging.debugMessage(" -> Interrupt! (Flash access failure)", .{});
    }

    if (temp & msdk.MXC_F_FLC_INTR_AF != 0) {
        msdk.MXC_FLC0.*.intr &= ~msdk.MXC_F_FLC_INTR_AF;
        messaging.debugMessage(" -> Interrupt! (Flash access failure)", .{});
    }
}

pub fn flash_simple_init() void {
    msdk.MXC_NVIC_SetVector(msdk.FLC0_IRQn, flash_simple_irq);
    msdk.NVIC_EnableIRQ(msdk.FLC0_IRQn);
    const result = msdk.MXC_FLC_EnableInt(msdk.MXC_F_FLC_INTR_DONEIE | msdk.MXC_F_FLC_INTR_AFIE);
    if (result != 0) {
        messaging.debugMessage("Failed to enable flash interrupts: {}\n", .{result});
    }
    msdk.MXC_ICC_Disable(msdk.MXC_ICC0);
}

pub fn flash_simple_erase_page(address: u32) i32 {
    return msdk.MXC_FLC_PageErase(address);
}

pub fn flash_simple_read(address: u32, buffer: []u8, size: u32) void {
    msdk.MXC_FLC_Read(address, buffer, size);
}

pub fn flash_simple_write(address: u32, buffer: []u8, size: u32) i32 {
    _ = buffer; // autofix
    return msdk.MXC_FLC_Write(address, size.buffer);
}
