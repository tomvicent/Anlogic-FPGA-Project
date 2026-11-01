# camera vs emio_gpio：UART 串口打印问题排查与修复总结

> 日期：2026-10-19
> 现象：`camera` 工程里 `print()` 串口打不出字；`emio_gpio` 工程同样用 `print()` 却正常。
> 结论：**不是代码问题，是硬件工程没使能 UART + BSP 控制台（stdin/stdout）设置指向错误外设。**

---

## 一、两个工程的核心区别（一句话版）

| | emio_gpio（正常） | camera（最初异常） |
|---|---|---|
| 硬件 PS 配置 | Block Design 中使能了 **UART0**（MIO10/11） | Block Design 中 **UART0/UART1 都没使能** |
| BSP 控制台（stdin/stdout） | `ps7_uart_0` | `ps7_coresight_comp_0`（CoreSight 调试口） |
| STDOUT_BASEADDRESS | `0xE0000000`（UART0 真身） | `0xF8800000`（非串口，写了也白写） |
| xparameters.h UART 驱动 | 有 `XPAR_PS7_UART_0` | 无任何 UART 驱动实例 |

---

## 二、详细区别对比（寄存器级证据）

### 1. UART 时钟（SLCR 寄存器 0xF800012C）

| 位 | 含义 | emio_gpio | camera（修复前） | camera（修复后） |
|---|---|---|---|---|
| bit20 | UART0_CPU_1XCLKACT | **1（开）** | 0（关） | **1（开）** |
| bit21 | UART1_CPU_1XCLKACT | 0 | 0 | 0 |

对应 `ps7_init.c` 中的写值：emio_gpio 为 `0x015C000D`，camera 修复前为 `0x014C000D`。

### 2. UART 寄存器初始化（0xE0000000 段）

| 项 | emio_gpio | camera（修复前） | camera（修复后） |
|---|---|---|---|
| 波特率分频 BDIV (0x34) | 0x6 | **未初始化（段为空）** | 0x6 |
| 时钟分频 CD (0x18) | 0x7C | 未初始化 | 0x7C |
| 控制寄存器 (0x00) TXEN/RXEN | 0x17 | 未初始化 | 0x17 |

### 3. MIO 引脚复用

- emio_gpio：MIO10（UART0 RX）、MIO11（UART0 TX）配置为 UART 功能。
- camera（修复前）：无任何 MIO 引脚配置为 UART。

### 4. BSP 配置文件（system.mss）

```
emio_gpio:  PARAMETER stdin  = ps7_uart_0
            PARAMETER stdout = ps7_uart_0

camera修复前: PARAMETER stdin  = ps7_coresight_comp_0
            PARAMETER stdout = ps7_coresight_comp_0

camera修复后: PARAMETER stdin  = ps7_uart_0   ← 手动修改后
            PARAMETER stdout = ps7_uart_0
```

### 5. xparameters.h

```
emio_gpio:  STDOUT_BASEADDRESS = 0xE0000000
            XPAR_PS7_UART_0_BASEADDR = 0xE0000000

camera修复前: STDOUT_BASEADDRESS = 0xF8800000  ← CoreSight 调试口，不是串口
            无 XPAR_PS7_UART_0 定义

camera修复后: STDOUT_BASEADDRESS = 0xE0000000
            XPAR_PS7_UART_0_BASEADDR = 0xE0000000
```

---

## 三、根因链条

```
硬件 Block Design 没有使能 UART
   ↓
导出 XSA 时 PS 配置里没有 UART 外设
   ↓
Vitis 生成 BSP：找不到可用的串口控制台 → 兜底选择 CoreSight 调试口
   ↓
system.mss: stdout = ps7_coresight_comp_0
   ↓
xparameters.h: STDOUT_BASEADDRESS = 0xF8800000
   ↓
print() 底层 outbyte() 把字符写到 0xF8800000 → 不是 UART → 串口什么都收不到
```

**最迷惑的一步**：后来在硬件里使能 UART0、重新导出 XSA、更新平台后，BSP 重新生成了：
- ✅ UARTPS 驱动被加入（xparameters 里出现 `XPAR_PS7_UART_0`）
- ❌ 但 **stdin/stdout 控制台选择不会被自动修改**（属于用户设置，Vitis 不擅自更改），仍是 `ps7_coresight_comp_0`

所以表现为：**硬件明明开了 UART，打印还是没输出。**

---

## 四、原理：print() 到串口的五层链路

```
① 应用层   main.c: print("...")
② 库层     outbyte(c) —— standalone 库里 print 的底层实现，往某地址写 1 字节
③ 寻址层   STDOUT_BASEADDRESS —— 决定"往哪个地址写" ⚠️ 咽喉
④ 外设层   外设的 TX FIFO 寄存器（字节落进哪个外设）
⑤ 物理层   MIO 引脚 → USB-UART 芯片 → 电脑 COM 口 → 串口工具显示
```

- 第③步指向 `0xE0000000`（UART0）→ 字节进串口
- 第③步指向 `0xF8800000`（CoreSight）→ 字节写进调试口，串口无输出

### 类比：修路 vs 路标

- **ps7_init（硬件初始化）＝ 修路**：开时钟、配波特率、配 MIO 引脚复用，把 UART0 这条路修好
- **BSP 的 STDOUT_BASEADDRESS ＝ 路标/导航**：告诉 print() 往哪条路走
- **print() 只认路标，不认路**：路修好了，路标还指着旧方向（CoreSight），照样到不了串口

### STDOUT 地址由谁决定

1. Vitis 生成 BSP 时扫描硬件，找可用作控制台的外设（UART）
2. 有 UART → 默认选第一个（`ps7_uart_0`）
3. 无 UART → 退回兜底 `ps7_coresight_comp_0`
4. 选择结果写入 `system.mss`（stdin/stdout 参数）→ 据此生成 `xparameters.h`
5. 该选择属于用户设置，**之后重新生成 BSP 也不会自动改**

---

## 五、修复步骤（根治方案）

### 步骤 1：Vivado 硬件工程使能 UART

1. 打开 `camera.xpr` → Block Design
2. 双击 `processing_system7_0`
3. **Peripherals → I/O Peripherals → UART → 勾选 UART 0**（与 emio_gpio 一致，板载 USB 串口接 MIO10/11；若板子接 MIO48/49 则选 UART 1）
4. Generate Output Products → Export Hardware（含 bitstream）→ 生成新 .xsa

### 步骤 2：Vitis 更新平台并修改 BSP 控制台

1. Vitis 中 Update Hardware Specification，换成新 .xsa
2. 右键 `standalone_ps7_cortexa9_0` → **Board Support Package Settings** → **Modify BSP Settings...**
3. 左侧选 standalone → 把 **stdin** 和 **stdout** 从 `ps7_coresight_comp_0` 改为 **`ps7_uart_0`**
4. 确认重新生成 BSP → 右键 `system_wrapper` Build（消除 Out-of-date）→ 右键 `camera` Build

### 步骤 3：验证

- 打开 `xparameters.h`，确认 `STDOUT_BASEADDRESS = 0xE0000000`
- 串口工具 115200、8N1，选 emio_gpio 能打字时的 COM 口
- 运行后应看到：`AXI GPIO button interrupt example` / `Ready. Press the PL button...`

---

## 六、临时直写方案（绕过 BSP 控制台，备用）

FSBL / ps7_init 启动时已把 UART0 配成 115200，可直接写 TX FIFO：

```c
#define UART0_BASE 0xE0000000U
static void uart_putc(char c)
{
    while (!(*(volatile unsigned int *)(UART0_BASE + 0x2CU) & 0x08U)); /* 等 TX FIFO 不满 */
    *(volatile unsigned int *)(UART0_BASE + 0x30U) = (unsigned int)c;  /* 写 TX FIFO */
}
static void uart_puts(const char *s)
{
    while (*s != '\0') uart_putc(*s++);
}
```

把 `print("...")` 换成 `uart_puts("...")` 即可，但注意**只对当前代码有效**，其它用 `print()` 的地方仍会打空气——所以最终还是要做根治（第五节）。

---

## 七、最终状态确认（2026-10-19 15:14）

| 项 | 状态 |
|---|---|
| 硬件 UART0（时钟/寄存器/MIO） | ✅ 已使能 |
| BSP stdin/stdout | ✅ `ps7_uart_0` |
| STDOUT_BASEADDRESS | ✅ `0xE0000000` |
| main.c | ✅ 恢复标准 `print()` / `xil_printf()` |
| 串口输出 | ✅ 正常 |

---

## 八、附录：关键文件路径与寄存器速查

**关键文件**
- 硬件初始化：`camera\prj\camera\vits\system_wrapper\hw\ps7_init.c`
- BSP 控制台设置：`...\standalone_ps7_cortexa9_0\bsp\system.mss`
- 外设地址表：`...\bsp\ps7_cortexa9_0\include\xparameters.h`
- 应用代码：`camera\prj\camera\vits\camera\src\main.c`
- 对比工程：`D:\FPGA\Vitis\emio_gpio\vitis\emio_gpio\src\main.c`

**寄存器速查（Zynq-7000 UART0）**

| 地址 | 寄存器 | 用途 |
|---|---|---|
| 0xE0000000 | 控制 | bit4=TXEN、bit2=RXEN、bit1=TXRES、bit0=RXRES |
| 0xE0000004 | 模式 | 数据位/校验/停止位配置 |
| 0xE0000018 | CD | 波特率时钟分频 |
| 0xE0000034 | BDIV | 波特率预分频 |
| 0xE000002C | 通道状态 | bit3=TXFUL（发送 FIFO 满标志） |
| 0xE0000030 | TX FIFO | 写入即发送 |
| 0xF800012C | SLCR 时钟 | bit20=UART0 CPU 时钟使能 |
