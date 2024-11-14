const std = @import("std");
const shared = @import("shared");
const msdk = shared.msdk;
const params = @import("params");

/// Entrypoint for the application processor
pub export fn main() noreturn {
    _ = msdk.LED_Init();
    msdk.LED_Off(msdk.LED1);
    msdk.LED_Off(msdk.LED2);

    shared.sayHi();

    while (true) {
        for (0..3) |_| {
            msdk.LED_On(msdk.LED2);
            _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(500 / 3));
            msdk.LED_Off(msdk.LED2);
            _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(500 / 3));
        }
        for (0..3) |_| {
            msdk.LED_On(msdk.LED2);
            _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(1000 / 3));
            msdk.LED_Off(msdk.LED2);
            _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(1000 / 3));
        }
        for (0..3) |_| {
            msdk.LED_On(msdk.LED2);
            _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(500 / 3));
            msdk.LED_Off(msdk.LED2);
            _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(500 / 3));
        }
        _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(2000 / 3));
    }
}
