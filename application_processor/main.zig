const std = @import("std");

// const params = @cImport({
//     @cInclude("ectf_params.h");
// });

const msdk = @import("msdk");
const params = @import("params");

pub export fn main() noreturn {
    _ = msdk.LED_Init();
    initI2C() catch {
        msdk.LED_On(msdk.LED1);
        _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(5000));
    };
    msdk.LED_Off(msdk.LED1);

    _ = params.AP_PIN;

    sendI2C("Hello, world!") catch {
        msdk.LED_On(msdk.LED3);
        _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(5000));
    };

    msdk.LED_Off(msdk.LED1);
    msdk.LED_Off(msdk.LED2);

    while (true) {
        msdk.LED_Off(msdk.LED3);
        msdk.LED_On(msdk.LED1);
        _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(1000));
        msdk.LED_Off(msdk.LED1);
        msdk.LED_On(msdk.LED2);
        _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(1000));
        msdk.LED_Off(msdk.LED2);
        msdk.LED_On(msdk.LED3);
        _ = msdk.MXC_Delay(msdk.MXC_DELAY_MSEC(1000));
    }
}

const I2CError = error{
    InitFailed,
    SendFailed,
};

const I2C_ADDR = 0x50;
const I2C_INTERFACE = msdk.MXC_I2C1;
const I2C_SPEED = 10000;

fn initI2C() !void {
    msdk.MXC_ICC_Enable(msdk.MXC_ICC0);

    _ = msdk.MXC_SYS_Clock_Select(msdk.MXC_SYS_CLOCK_IPO);

    const success = msdk.MXC_I2C_Init(I2C_INTERFACE, 1, 0);
    if (success != msdk.E_SUCCESS) {
        return I2CError.InitFailed;
    }

    _ = msdk.MXC_I2C_SetFrequency(I2C_INTERFACE, I2C_SPEED);

    msdk.MXC_I2C_SetTimeout(I2C_INTERFACE, 100);
}

fn sendI2C(data: []const u8) !void {
    const request = msdk.mxc_i2c_req_t{
        .i2c = I2C_INTERFACE,
        .addr = I2C_ADDR,
        .tx_buf = @constCast(data.ptr),
        .rx_len = data.len,
    };
    const success = msdk.MXC_I2C_MasterTransaction(@constCast(&request));
    if (success != msdk.E_SUCCESS) {
        return I2CError.SendFailed;
    }
}
