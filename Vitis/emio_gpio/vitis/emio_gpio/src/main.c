#include <stdio.h>
#include "xparameters.h"
#include "xgpiops.h"
#include "sleep.h"
#define GPIOPS_ID   XPAR_XGPIOPS_0_DEVICE_ID  // PS_GPIO_ID
#define MIO_LED0    7    // PS_LED0
#define MIO_LED1    8    // PS_LED1
#define MIO_KEY0    12   // PS_KEY0
#define EMIO_KEY    54   // PL_KEY0
//#define UART0_BASE  0xE0000000
//#define UART0_IDR   (*(volatile unsigned int *)(UART0_BASE + 0x0C))
int main()
{
    XGpioPs gpiops_inst;
    XGpioPs_Config *gpiops_cfg_ptr;
//    UART0_IDR = 0x00001FFF;
//
    print("EMIO_TEST!\n");
    gpiops_cfg_ptr = XGpioPs_LookupConfig(GPIOPS_ID);
    XGpioPs_CfgInitialize(&gpiops_inst, gpiops_cfg_ptr, gpiops_cfg_ptr->BaseAddr);
    XGpioPs_SetDirectionPin(&gpiops_inst, MIO_LED0, 1);
    XGpioPs_SetDirectionPin(&gpiops_inst, MIO_LED1, 1);
    XGpioPs_SetOutputEnablePin(&gpiops_inst, MIO_LED0, 1);
    XGpioPs_SetOutputEnablePin(&gpiops_inst, MIO_LED1, 1);
    XGpioPs_SetDirectionPin(&gpiops_inst, MIO_KEY0, 0);
    XGpioPs_SetDirectionPin(&gpiops_inst, EMIO_KEY, 0);
    while(1)
    {
        XGpioPs_WritePin(&gpiops_inst, MIO_LED0,
            ~XGpioPs_ReadPin(&gpiops_inst, MIO_KEY0));
        XGpioPs_WritePin(&gpiops_inst, MIO_LED1,
            ~XGpioPs_ReadPin(&gpiops_inst, EMIO_KEY));
    }

    
    return 0;
}
