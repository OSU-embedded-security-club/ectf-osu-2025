//! Interact with the hardware security features of the MAX78000
const msdk = @import("msdk");

/// Enable the Memory Protection Unit (MPU) over regions to make the code RX and
/// the RAM RW
pub fn mpu() void {
    msdk.ARM_MPU_Disable();

    // make SRAM non-executable
    msdk.ARM_MPU_SetRegion(
        msdk.ARM_MPU_RBAR(1, 0x20000000),
        msdk.ARM_MPU_RASR(1, msdk.ARM_MPU_AP_FULL, msdk.ARM_MPU_ACCESS_ORDERED, 0, 0, 0, 0b00000000, msdk.ARM_MPU_REGION_SIZE_1MB),
    );
    msdk.ARM_MPU_Enable(msdk.MPU_CTRL_HFNMIENA_Msk | msdk.MPU_CTRL_PRIVDEFENA_Msk);

    // except for this region which must be executable
    msdk.ARM_MPU_SetRegion(
        msdk.ARM_MPU_RBAR(2, 0x20000000),
        msdk.ARM_MPU_RASR(0, msdk.ARM_MPU_AP_FULL, msdk.ARM_MPU_ACCESS_ORDERED, 0, 0, 0, 0b10000000, msdk.ARM_MPU_REGION_SIZE_4KB),
    );
    msdk.ARM_MPU_Enable(msdk.MPU_CTRL_HFNMIENA_Msk | msdk.MPU_CTRL_PRIVDEFENA_Msk);

    // Make FLASH read only
    msdk.ARM_MPU_SetRegion(
        msdk.ARM_MPU_RBAR(3, 0x10000000),
        msdk.ARM_MPU_RASR(0, msdk.ARM_MPU_AP_RO, msdk.ARM_MPU_ACCESS_ORDERED, 0, 0, 0, 0b00000000, msdk.ARM_MPU_REGION_SIZE_256KB),
    );

    msdk.ARM_MPU_Enable(msdk.MPU_CTRL_HFNMIENA_Msk | msdk.MPU_CTRL_PRIVDEFENA_Msk);
}

/// Disable all peripherals
pub fn disable() void {
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_GPIO0);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_GPIO1);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_GPIO2);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_DMA);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_SPI0);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_SPI1);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_UART0); // UART0 will be re-enabled when MXC_UART_Init is called
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_UART1);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_UART2);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_UART3);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_I2C0);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_I2C1);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_I2C2);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_TMR0);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_TMR1);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_TMR2);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_TMR3);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_TMR4);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_TMR5);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_ADC);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_CNN);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_PT);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_TRNG);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_SMPHR);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_OWIRE);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_CRC);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_AES);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_I2S);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_PCIF);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_WDT0);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_WDT1);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_CPU1);
    msdk.MXC_SYS_ClockDisable(msdk.MXC_SYS_PERIPH_CLOCK_LPCOMP);
}

/// Stub for Zig because it struggles translating inline assembly in C code
export fn __DSB() callconv(.C) void {
    asm volatile ("dsb 0xF" ::: "memory");
}

/// Stub for Zig because it struggles translating inline assembly in C code
export fn __ISB() callconv(.C) void {
    asm volatile ("isb 0xF" ::: "memory");
}

/// Stub for Zig because it struggles translating inline assembly in C code
export fn __DMB() callconv(.C) void {
    asm volatile ("dmb 0xF" ::: "memory");
}
