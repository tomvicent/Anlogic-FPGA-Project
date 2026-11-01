#include "xparameters.h"
#include "xgpio.h"
#include "xgpiops.h"
#include "xscugic.h"
#include "xil_exception.h"
#include "xil_printf.h"
#include "xstatus.h"
#include <stdio.h>

/* 硬件设备 ID：请确认这些宏名称与生成的 xparameters.h 一致。 */
#define GPIOPS_DEVICE_ID       XPAR_XGPIOPS_0_DEVICE_ID
#define AXI_GPIO_DEVICE_ID     XPAR_AXI_GPIO_0_DEVICE_ID
#define SCUGIC_DEVICE_ID       XPAR_SCUGIC_0_DEVICE_ID
#define AXI_GPIO_INT_ID        XPAR_FABRIC_GPIO_0_VEC_ID

/* 与开发板连接方式相关的引脚和通道配置。 */
#define LED_MIO_PIN            0U
#define BUTTON_CHANNEL         1U

/*
 * AXI GPIO 通道方向掩码：
 * 1 表示输入，0 表示输出。
 * 如果按键接在其他通道或数据位上，请相应调整此掩码。
 */
#define BUTTON_DIRECTION_MASK  0xFFFFFFFFU

static XGpioPs gpiops;
static XGpio axi_gpio;
static XScuGic gic;

static volatile u32 led_value = 0U;

static int setup_interrupt_system(void);
static void button_interrupt_handler(void *callback_ref);

int main(void)
{
    int status;

    /* 初始化 PS 端 GPIO，并将 LED 所连接的 MIO 引脚配置为输出。 */
    print("AXI GPIO button interrupt example\r\n");

    /* 查找 PS GPIO 配置；未找到时无法继续初始化。 */
    XGpioPs_Config *ps_config = XGpioPs_LookupConfig(GPIOPS_DEVICE_ID);
    if (ps_config == NULL) {
        xil_printf("PS GPIO configuration not found\r\n");
        return XST_FAILURE;
    }

    status = XGpioPs_CfgInitialize(&gpiops, ps_config, ps_config->BaseAddr);
    if (status != XST_SUCCESS) {
        xil_printf("PS GPIO initialization failed\r\n");
        return XST_FAILURE;
    }

    /* 设置 MIO 引脚方向和输出使能，并写入 LED 初始状态。 */
    XGpioPs_SetDirectionPin(&gpiops, LED_MIO_PIN, 1U);
    XGpioPs_SetOutputEnablePin(&gpiops, LED_MIO_PIN, 1U);
    XGpioPs_WritePin(&gpiops, LED_MIO_PIN, led_value);

    /* 初始化 PL 侧 AXI GPIO，用于读取按键状态及产生中断。 */
    status = XGpio_Initialize(&axi_gpio, AXI_GPIO_DEVICE_ID);
    if (status != XST_SUCCESS) {
        xil_printf("AXI GPIO initialization failed\r\n");
        return XST_FAILURE;
    }

    /* 将按键所在通道配置为输入，并清除可能残留的通道中断标志。 */
    XGpio_SetDataDirection(&axi_gpio, BUTTON_CHANNEL,
                           BUTTON_DIRECTION_MASK);
    XGpio_InterruptClear(&axi_gpio, XGPIO_IR_CH1_MASK);

    status = setup_interrupt_system();
    if (status != XST_SUCCESS) {
        xil_printf("Interrupt setup failed\r\n");
        return XST_FAILURE;
    }

    xil_printf("Ready. Press the PL button to toggle the PS MIO LED.\r\n");

    while (1) {
        /* 主循环空转；按键检测和 LED 控制由中断处理函数完成。 */
    }
}

static int setup_interrupt_system(void)
{
    int status;
    XScuGic_Config *gic_config;

    /* 获取并初始化 PS 通用中断控制器（GIC）的配置。 */
    gic_config = XScuGic_LookupConfig(SCUGIC_DEVICE_ID);
    if (gic_config == NULL) {
        xil_printf("GIC configuration not found\r\n");
        return XST_FAILURE;
    }

    status = XScuGic_CfgInitialize(&gic, gic_config,
                                   gic_config->CpuBaseAddress);
    if (status != XST_SUCCESS) {
        xil_printf("GIC initialization failed\r\n");
        return XST_FAILURE;
    }

    /* 将 AXI GPIO 的中断 ID 关联到按键中断处理函数。 */
    status = XScuGic_Connect(&gic, AXI_GPIO_INT_ID,
                             (Xil_ExceptionHandler)button_interrupt_handler,
                             &axi_gpio);
    if (status != XST_SUCCESS) {
        xil_printf("GIC interrupt connection failed\r\n");
        return XST_FAILURE;
    }

    /* 先使能 AXI GPIO 通道及全局中断，再使能 GIC 中对应的中断源。 */
    XGpio_InterruptEnable(&axi_gpio, XGPIO_IR_CH1_MASK);
    XGpio_InterruptGlobalEnable(&axi_gpio);
    XScuGic_Enable(&gic, AXI_GPIO_INT_ID);

    /* 注册 GIC 中断分发函数，并打开 CPU 的中断异常响应。 */
    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                 (Xil_ExceptionHandler)XScuGic_InterruptHandler,
                                 &gic);
    Xil_ExceptionEnable();

    return XST_SUCCESS;
}

static void button_interrupt_handler(void *callback_ref)
{
    XGpio *gpio = (XGpio *)callback_ref;
    u32 interrupt_status;

    /* 读取 AXI GPIO 中断状态，确认是否为按键通道触发。 */
    interrupt_status = XGpio_InterruptGetStatus(gpio);

    if ((interrupt_status & XGPIO_IR_CH1_MASK) != 0U) {
        /* 清除 AXI GPIO 的通道中断标志，避免重复响应同一中断。 */
        XGpio_InterruptClear(gpio, XGPIO_IR_CH1_MASK);

        /* 翻转 LED 状态，并通过 PS MIO 引脚更新 LED 输出。 */
        led_value ^= 1U;
        XGpioPs_WritePin(&gpiops, LED_MIO_PIN, led_value);
    }
}
