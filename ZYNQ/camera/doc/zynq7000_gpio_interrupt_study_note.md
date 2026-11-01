# Zynq-7000 Standalone：PS GPIO、AXI GPIO 与中断学习笔记

> 本笔记根据对话中提供的 Zynq-7000 Standalone C 示例整理。原代码在 AXI GPIO 配置处被截断，因此后半部分的中断注册与回调按 Xilinx 驱动的常见用法说明；实际宏名、函数调用和硬件连线应以当前 Vivado/Vitis 工程为准。

## 1. 先建立正确的整体图景

示例里有两种 GPIO：

- **PS GPIO（`XGpioPs`）**：Zynq PS 内部的 GPIO 控制器，可连接 MIO，也可通过 EMIO 延伸到 PL。示例用它驱动 LED 所在的 MIO 引脚。
- **AXI GPIO（`XGpio`）**：PL 中的 AXI GPIO IP。PS 通过 AXI 总线访问它的寄存器；示例让它读取 PL 侧按键/输入，并由 IP 的中断输出通知 PS。

典型信号路径是：

```text
PL 输入变化
  → AXI GPIO 检测到输入/中断条件
  → AXI GPIO 的 interrupt 输出接到 Zynq PS 的 IRQ_F2P
  → PS 内部 GIC（通用中断控制器）向 Cortex-A9 发出 IRQ
  → 异常入口分发到已注册的 AXI GPIO 中断处理函数
  → 软件读取/清除 AXI GPIO 中断状态，并更新应用状态
  → 主循环或回调调用 PS GPIO 驱动
  → PS GPIO 经 MIO（或 EMIO）控制 LED
```

中断不会自动“控制 AXI 去驱动 LED”。中断只是通知 CPU 有事件；程序必须执行对应处理，再通过某个 GPIO/外设驱动写 LED。此例中 LED 如果确实接在 MIO 上，是由 **PS GPIO** 驱动，而非 AXI GPIO。

## 2. 头文件

```c
#include "xparameters.h"
#include "xgpio.h"
#include "xgpiops.h"
#include "xscugic.h"
#include "xil_exception.h"
#include "xil_printf.h"
#include "xstatus.h"
```

- `xparameters.h`：由硬件平台生成，包含设备 ID、基地址、中断 ID 等参数。它是核对宏名称的首要依据。
- `xgpio.h`：PL AXI GPIO 驱动 `XGpio` 的声明。
- `xgpiops.h`：PS GPIO 驱动 `XGpioPs` 的声明。
- `xscugic.h`：Zynq-7000 PS GIC 驱动 `XScuGic` 的声明。
- `xil_exception.h`：CPU 异常/IRQ 入口注册与使能接口。
- `xil_printf.h`：嵌入式轻量打印函数 `xil_printf`。
- `xstatus.h`：`XST_SUCCESS`、`XST_FAILURE` 等状态码。

原始代码还出现了 `<stdio.h>`，但若只用 `xil_printf`，通常不需要它；普通 `printf` 是否可用取决于 BSP 的 C 库配置。

## 3. 宏：设备 ID、向量 ID 与引脚/通道

```c
#define GPIOPS_DEVICE_ID   XPAR_XGPIOPS_0_DEVICE_ID
#define AXI_GPIO_DEVICE_ID XPAR_AXI_GPIO_0_DEVICE_ID
#define SCUGIC_DEVICE_ID   XPAR_SCUGIC_0_DEVICE_ID
#define AXI_GPIO_INT_ID    XPAR_FABRIC_GPIO_0_VEC_ID

#define LED_MIO_PIN       0U
#define BUTTON_CHANNEL    1U
#define BUTTON_DIRECTION_MASK 0xFFFFFFFFU
```

- `*_DEVICE_ID` 用来让驱动查找对应硬件实例的静态配置。它不是 GPIO 引脚号，也不是中断号。
- `SCUGIC_DEVICE_ID` 用于查找 GIC 的驱动配置。
- `AXI_GPIO_INT_ID` 是 AXI GPIO 中断在处理器中断控制器里的 ID。常见由 `xparameters.h` 生成，符号名随 Vivado 地址/实例命名和 BSP 版本变化。它不是“中断文件名”。
- `LED_MIO_PIN` 是 PS GPIO 的引脚编号。`0U` 只是示例值，必须按板卡原理图、PS 配置和 MIO 映射核对；并非所有板子的 LED 都接 MIO 0。若 LED 接在 PL，需用 AXI GPIO 或其他 PL 逻辑驱动；若走 EMIO，则连接方式不同。
- `BUTTON_CHANNEL` 是 AXI GPIO 的通道号，通常为 1 或 2。它不是数据位号。AXI GPIO 可配置一个或两个通道，且各通道宽度由 Vivado IP 参数决定，最大宽度不是简单等同于“PS GPIO 位宽”。
- `BUTTON_DIRECTION_MASK` 对 `XGpio_SetDataDirection` 而言，每一位对应一个 AXI GPIO 数据位：`1` 为输入、`0` 为输出。`0xFFFFFFFFU` 将 32 位都设为输入。若 IP 通道实际宽度不足 32 位，应按设计宽度和实际接线设置有效位；输入通道通常配置为输入。

中断 ID 的 Zynq-7000 硬件来源是 PL 到 PS 的 `IRQ_F2P` fabric interrupt 输入，再映射到 GIC。Zynq-7000 有多个 PL→PS 中断输入，GIC ID 取决于使用的 `IRQ_F2P` 位。不要靠“80 到 90”猜编号：检查 `xparameters.h` 中生成的 `XPAR_FABRIC_..._VEC_ID`，并确认 Vivado 的中断连线。AMD UG585 列出了这些映射。

## 4. 驱动对象与 `volatile`

```c
static XGpioPs gpiops;
static XGpio axi_gpio;
static XScuGic gic;
static volatile u32 led_value = 0U;
```

- `gpiops`：PS GPIO 驱动实例状态对象，保存驱动使用的配置/基地址等信息。
- `axi_gpio`：AXI GPIO 驱动实例状态对象。
- `gic`：GIC 驱动实例状态对象。
- `static`：对象只在此 C 文件内可见，并具有静态存储期；不是硬件初始化操作。
- `u32`：Xilinx 定义的 32 位无符号整数类型。
- `volatile`：告诉编译器该变量可能在普通执行流之外被改变（例如中断处理函数），访问时不要随意缓存或优化掉。它不保证多线程同步、原子性，也不能替代正确的中断同步设计。若 ISR 与主循环共享变量，通常让 ISR 只更新简单状态，由主循环处理较复杂工作。

## 5. `main()` 中已显示代码逐段说明

### 5.1 打印与状态变量

```c
int status;
xil_printf("AXI GPIO button interrupt example\r\n");
```

`status` 接收驱动初始化的返回值；`XST_SUCCESS` 表示成功。`\r\n` 是串口常见的回车换行组合。

### 5.2 查 PS GPIO 配置

```c
XGpioPs_Config *ps_config = XGpioPs_LookupConfig(GPIOPS_DEVICE_ID);
if (ps_config == NULL) {
    ...
}
```

`XGpioPs_LookupConfig` 按设备 ID 在 BSP 生成的配置表中查找该 PS GPIO 实例的静态配置，返回配置结构体指针。它只是**查找配置描述**，并未初始化外设，也不负责查找某个 GPIO 中断。

### 5.3 初始化 PS GPIO 驱动实例

```c
status = XGpioPs_CfgInitialize(&gpiops, ps_config, ps_config->BaseAddr);
```

含义拆解：

1. `&gpiops`：把驱动对象地址传给驱动，让它在该对象中保存运行所需状态。
2. `ps_config`：刚查到的静态硬件配置。
3. `ps_config->BaseAddr`：PS GPIO 寄存器映射的有效基地址。驱动之后通过它访问 GPIO 控制寄存器。
4. 返回值写入 `status`，随后用 `XST_SUCCESS` 检查。

简言之：**用 BSP 的硬件配置和寄存器基地址，把软件驱动实例 `gpiops` 初始化到可用状态。** 这与 STM32 HAL 的初始化思路相似，都是将外设硬件配置与软件驱动对象关联起来；差别是 Xilinx Standalone 驱动通常依据 Vivado 导出的硬件平台/BSP 配置表，而 STM32 常见流程是配置 Cube/HAL 结构体并调用 HAL 初始化函数。

### 5.4 把 LED 对应 PS GPIO 引脚设为输出

```c
XGpioPs_SetDirectionPin(&gpiops, LED_MIO_PIN, 1U);
XGpioPs_SetOutputEnablePin(&gpiops, LED_MIO_PIN, 1U);
XGpioPs_WritePin(&gpiops, LED_MIO_PIN, led_value);
```

- `XGpioPs_SetDirectionPin(..., 1U)`：方向设为输出；此 API 中 `1` 表示输出、`0` 表示输入。
- `XGpioPs_SetOutputEnablePin(..., 1U)`：使能该引脚的输出驱动。
- `XGpioPs_WritePin(...)`：写输出值，通常 `0` 为低、`1` 为高。LED 是高电平点亮还是低电平点亮由板卡电路决定。

这几个调用作用在 PS GPIO 引脚上，不会配置 AXI GPIO 通道。

### 5.5 初始化 PL AXI GPIO

```c
status = XGpio_Initialize(&axi_gpio, AXI_GPIO_DEVICE_ID);
```

`XGpio_Initialize` 按设备 ID 查找 BSP 中的 AXI GPIO 配置，并初始化 `axi_gpio` 驱动对象。对应硬件必须已经在 Vivado Block Design 中实例化，并导出到当前 Vitis platform/BSP。PS 通常通过 AXI Lite 访问 AXI GPIO 的寄存器。

对照而言：`XGpioPs_*` 操作 PS 内部 GPIO；`XGpio_*` 操作 PL 中 AXI GPIO IP。二者 API、硬件资源和配置来源不同。

## 6. 被截断部分应完成的配置工作

原代码下一句开头为“将按键所在通道配置为输入并清除待处理中断”，具体代码没有完整保存在引用中。典型逻辑包括：

1. `XGpio_SetDataDirection(&axi_gpio, BUTTON_CHANNEL, BUTTON_DIRECTION_MASK);` 配置通道位方向。
2. 初始化 GIC：查找 `XScuGic_Config`，调用 `XScuGic_CfgInitialize`。
3. 将 AXI GPIO 的中断 ID 和 ISR 通过 `XScuGic_Connect` 关联。
4. 使能 GIC 中对应的中断 ID：`XScuGic_Enable`。
5. 使能 AXI GPIO 通道中断和全局中断：`XGpio_InterruptEnable`、`XGpio_InterruptGlobalEnable`。
6. 注册 CPU IRQ 异常入口：`Xil_ExceptionInit`、`Xil_ExceptionRegisterHandler`，并使能 IRQ。
7. 在 ISR 中读取必要状态、清除/确认 AXI GPIO 的中断状态，并记录事件或执行简短处理。

这是多级使能：**外设自身中断使能 → GIC 中断使能 → CPU 异常/IRQ 入口使能**。只做其中一层通常不会正常进入 ISR。清除中断的具体时机和掩码需遵照 AXI GPIO 驱动/硬件配置，并避免因未清状态导致重复进入。

## 7. “中断文件名”到底是什么

通常没有一个由 Vivado 自动生成、名字固定的“中断文件”。应用代码里可以在任意 `.c` 文件定义 ISR，例如：

```c
static void button_interrupt_handler(void *callback_ref)
{
    XGpio *gpio = (XGpio *)callback_ref;
    /* 检查/清除中断状态，记录事件；尽量保持短小。 */
}
```

真正决定中断发生时调用哪个函数的是软件注册关系，通常通过 `XScuGic_Connect(&gic, AXI_GPIO_INT_ID, handler, callback_ref)` 建立。`AXI_GPIO_INT_ID` 标识硬件中断源，`handler` 是软件函数指针；两者不是同一个概念。也可以把 AXI GPIO 驱动自带的 `XGpio_InterruptHandler` 接到 GIC，再由驱动回调机制调用应用函数，具体取决于所用驱动 API 和示例。

## 8. 对常见理解的修正

- **“PL GPIO 变化就会在 AXI 总线上产生中断”**：不准确。AXI 是 PS 对 AXI GPIO 寄存器进行读写的总线访问路径；中断是 AXI GPIO IP 独立的 interrupt 输出信号，经 PL→PS 中断线进入 GIC。
- **“GIC 有 90 多个可配置中断”**：GIC 管理大量中断源，但 `XScuGic_LookupConfig` 查找的是 GIC 控制器的驱动配置实例，不是枚举/初始化 90 多个中断。单个中断源通过 ID 单独连接、配置和使能。
- **“PL IRQ_F2P 的编号大概是 80 到 90”**：需要按芯片和具体 PL→PS 输入映射核实。Zynq-7000 的 IRQ_F2P 映射到指定 GIC SPI ID；使用 BSP 生成的 `XPAR_FABRIC_..._VEC_ID`，检查 Vivado 中断连接，不能从示例名推测固定编号。
- **“AXI GPIO 通道可以直接和 PS 端 IO/DDR 连接”**：AXI GPIO 通道是 PL 侧并行数字 I/O。它可以接 PL 逻辑或顶层引脚，也可以通过 EMIO 等已设计的接口连接；不能把 AXI GPIO 通道当成 DDR 接口。PS 访问 DDR 和 PL 访问 DDR 需要通过 Zynq 的存储器/AXI互连路径配置，不是 AXI GPIO 的功能。
- **“IP 文件放在 ip_user_files 就是软件驱动”**：`ip_user_files` 是 Vivado 生成/管理 IP 相关输出的目录之一；应用使用的 BSP 驱动代码、`xparameters.h` 和硬件平台描述由 Vitis/platform 流程提供。不要仅凭目录名判断硬件 IP、生成文件和驱动源的职责。
- **“按键电平变化一定会产生 AXI GPIO 中断”**：还需确认 AXI GPIO IP 启用了中断能力、硬件接线正确、Vivado 把 interrupt 接到 PS IRQ_F2P、软件使能各级中断。按键还可能需要消抖和合适的边沿/电平处理。

## 9. 调试检查清单

1. 在生成的 `xparameters.h` 搜索 `XPAR_XGPIOPS_0_DEVICE_ID`、`XPAR_AXI_GPIO_0_DEVICE_ID`、`XPAR_SCUGIC_0_DEVICE_ID` 和 `XPAR_FABRIC_..._VEC_ID`；名字不匹配时以实际文件为准。
2. Vivado 中确认 AXI GPIO 通道宽度、输入/输出方向、中断是否启用，以及 `ip2intc_irpt` 是否连到 PS 的 `IRQ_F2P`。
3. 确认 `BUTTON_CHANNEL` 和数据位与实际接线相符；用轮询读取先验证输入电平，再调中断。
4. 确认中断 ID 与当前 bitstream/platform 匹配；硬件设计变化后重新导出硬件并更新 Vitis platform/BSP。
5. 确认 GIC 中断已连接并使能、AXI GPIO 内部中断已使能、CPU IRQ 已使能，且 ISR 清除了正确的 pending 状态。
6. 核对板卡原理图中的 LED MIO/PL 引脚及有效电平。错误的 MIO 编号或 LED 极性会让程序“运行正常但灯不亮”。
7. ISR 中尽量只做确认中断、读取必要数据、置标志等短操作；延时、复杂打印、阻塞等待和按键消抖一般放到主循环/定时器任务中。

## 10. 一句话总结

这份示例是 **PS GPIO 输出 LED + PL AXI GPIO 输入并产生中断 + PS GIC 分发中断** 的组合。`XGpioPs_CfgInitialize` 初始化 PS GPIO 驱动实例；`XGpio_Initialize` 初始化 AXI GPIO 驱动实例；GIC 的配置查找不等于配置所有中断；中断 ID 来自硬件平台映射，ISR 函数由软件注册。

## 参考

- [AMD UG585：Zynq-7000 SoC Technical Reference Manual — Interrupt Signals](https://docs.amd.com/r/en-US/ug585-zynq-7000-SoC-TRM/Interrupt-Signals)
- [Xilinx embeddedsw：AXI GPIO 中断示例](https://github.com/Xilinx/embeddedsw/blob/master/XilinxProcessorIPLib/drivers/gpio/examples/xgpio_intr_tapp_example.c)
- [Xilinx embeddedsw：`xgpio.h` API 声明](https://github.com/Xilinx/embeddedsw/blob/master/XilinxProcessorIPLib/drivers/gpio/src/xgpio.h)
- [Xilinx embeddedsw：PS GPIO 中断示例](https://github.com/Xilinx/embeddedsw/blob/master/XilinxProcessorIPLib/drivers/gpiops/examples/xgpiops_intr_example.c)
