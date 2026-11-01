#include <stdio.h>
#include "al_core.h"
#include "al_gpio_hal.h"
#include "al_uart_hal.h"

#define AL_UART_DEVID 1
#define PS_LED 51
#define AL_GPIO_DEVICE_ID 0
#define AL_GPIO_DIR_OUTPUT 1

static AL_UART_InitStruct UART_InitStruct = {
    .BaudRate = 115200,
    .Parity = AL_UART_NO_PARITY,
    .WordLength = AL_UART_CHAR_8BITS,
    .StopBits = AL_UART_STOP_1BIT,
    .HwFlowCtl = AL_FALSE,
    .CharTimeoutEnable = AL_TRUE
};

AL_S32 main()
{
    // 先点LED确认程序跑起来了
    AL_GPIO_HalStruct *GPIO;
    AlGpio_Hal_Init(&GPIO, AL_GPIO_DEVICE_ID, AL_NULL);
//    AlGpio_Hal_SetDirection(GPIO, PS_LED, AL_GPIO_DIR_OUTPUT);
    AlGpio_Hal_WritePin(GPIO, PS_LED, 1);  // LED亮

    // 直接用HAL初始化UART1并发数据
    AL_UART_HalStruct *UartHandle;
    AL_S32 ret = AlUart_Hal_Init(&UartHandle, AL_UART_DEVID, &UART_InitStruct, AL_NULL);

    const char *msg = "UART1 TEST OK\r\n";
    while(1)
    {
        AlUart_Hal_SendDataPolling(UartHandle, (const AL_U8 *)msg, 14);
        // 延时一会儿
        for(volatile int i=0; i<1000000; i++);
    }
    return 0;
}
