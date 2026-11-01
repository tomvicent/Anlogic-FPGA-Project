# AXI 总线学习笔记：协议、Vivado 连接与 Zynq-7000 摄像头工程

> 这份笔记汇总 AXI 的常见概念，并结合本仓库的 Vivado Block Design、Vitis BSP 和已有的 VDMA 学习内容举例。AXI 不是一种单一的物理总线，而是一组片上接口协议。实际接口能力和参数以所用 IP 版本、Vivado 配置及 AMD/Arm 产品手册为准。

## 1. 先记住这几个核心概念

- **AXI4 Memory-Mapped（AXI4-MM）**：按地址访问寄存器或存储器，可突发传输，适合 CPU、DMA、DDR、外设寄存器。
- **AXI4-Lite**：较简单的地址读写接口，通常用于控制/状态寄存器；每次传输一个数据拍，不支持突发。
- **AXI4-Stream（AXIS）**：不带地址的数据流接口，适合视频、音频、网络包、采样数据等连续数据。
- **握手：**一个通道在时钟上升沿同时满足 `VALID=1` 和 `READY=1` 时完成一次传输。VALID 由数据/控制的发送方驱动，READY 由接收方驱动。
- **主从（Master/Slave）：**在某个接口连接上，Master 发起事务，Slave 响应事务。一个 IP 可以在不同接口上同时作为 Master 和 Slave。
- **AXI 总线传输与中断是两条不同的信号路径。**例如 CPU 经 AXI-Lite 读写 GPIO 寄存器，而 GPIO 的中断输出单独连到 PS 的 `IRQ_F2P`。

## 2. AXI 家族与适用场景

| 接口 | 是否带地址 | 典型传输 | 常见用途 |
|---|---|---|---|
| AXI3 | 是 | 突发读写，旧版 AXI-MM | Zynq-7000 PS-PL GP 等接口的协议侧 |
| AXI4 | 是 | 高吞吐突发读写 | DDR、DMA、数据搬运、内存映射外设 |
| AXI4-Lite | 是 | 单拍读写，无突发 | 控制寄存器、状态寄存器、GPIO 控制 |
| AXI4-Stream | 否 | 持续/分包的数据流 | 视频像素流、音视频、DSP 数据、网络数据 |

AXI3/AXI4/AXI4-Lite 都属于 Memory-Mapped 家族；Stream 的传输模型不同，不进行地址译码。工程里会用 Interconnect、Protocol Converter、Data Width Converter 等 IP 将不同接口连接起来，但只有在转换器支持的范围内才能转换，不能假设任意接口可以无条件直连。

### 2.1 AXI3 与 AXI4 的常见差别

- AXI3 突发通常最多 16 拍；AXI4 的 INCR 突发可到 256 拍（仍须满足边界与目标 IP 限制）。
- AXI3 有写数据 ID `WID`，协议允许写数据交错；AXI4 移除了 `WID`，写数据按地址事务次序关联，不能交错不同写突发的数据。
- Zynq-7000 PS-PL 的 GP 端口采用 AXI3；PL 中许多新 IP 的接口可能是 AXI4 或 AXI4-Lite，因此 Vivado 可能自动插入协议转换器。

这些只是常见协议区别摘要，兼容性应查看具体接口和转换 IP 参数。

## 3. AXI4-MM 的五个通道

AXI4-MM 把一次读写事务分成多个独立通道。每个通道都有自己的 VALID/READY 握手。

| 通道 | 方向（以 Master/Slave 定义） | 作用 | 常见信号 |
|---|---|---|---|
| 写地址 AW | Master → Slave | 写事务地址和控制信息 | `AWADDR`, `AWLEN`, `AWSIZE`, `AWBURST`, `AWVALID`, `AWREADY` |
| 写数据 W | Master → Slave | 写入的数据拍和字节使能 | `WDATA`, `WSTRB`, `WLAST`, `WVALID`, `WREADY` |
| 写响应 B | Slave → Master | 告知写事务完成状态 | `BRESP`, `BVALID`, `BREADY` |
| 读地址 AR | Master → Slave | 读事务地址和控制信息 | `ARADDR`, `ARLEN`, `ARSIZE`, `ARBURST`, `ARVALID`, `ARREADY` |
| 读数据 R | Slave → Master | 返回读数据和响应状态 | `RDATA`, `RRESP`, `RLAST`, `RVALID`, `RREADY` |

读与写有各自的地址/数据通道，彼此可以独立推进；读数据和写数据也可以在系统允许时同时传输。注意写地址 AW、写数据 W、写响应 B 是三个独立通道，因此地址握手和数据握手不必在同一拍发生。

### 3.1 VALID/READY 握手

一次通道传输在某个 `ACLK` 上升沿满足 `VALID && READY` 时完成：

```text
发送端：VALID=1 表示当前控制/数据有效
接收端：READY=1 表示当前能够接收
完成条件：在时钟边沿采样到 VALID=1 且 READY=1
```

发送端一旦拉高 VALID，就必须保持 VALID 以及该通道对应的数据/控制不变，直到握手完成；不能在 READY 尚未接受时撤回当前拍。READY 可以拉低，形成反压（back-pressure），此时发送端需要等待。

这个握手是**同步于时钟的**，不是异步握手。跨时钟域时不能只把 VALID/READY 接过去，必须使用合适的 AXI Clock Converter、异步 FIFO 或 CDC 设计。

### 3.2 突发相关字段

- `AxADDR`：突发起始字节地址。
- `AxLEN`：突发拍数减一。例如 `AxLEN=0` 代表 1 拍，`AxLEN=15` 代表 16 拍。
- `AxSIZE`：每拍字节数的以 2 为底的指数，字节数为 `2^AxSIZE`。例如 32-bit 数据总线的完整一拍是 4 字节，通常 `AxSIZE=2`。
- `AxBURST`：突发地址变化方式，常见 `FIXED`、`INCR`、`WRAP`。连续搬运通常使用 `INCR`。
- `WLAST` / `RLAST`：标记突发的最后一个写/读数据拍。
- `WSTRB`：每一位对应一个数据字节，指示本拍哪些字节有效，用于部分写入。
- `BRESP` / `RRESP`：响应状态，例如 OKAY、SLVERR、DECERR。错误响应需要在驱动/调试中检查。

AXI4 的 INCR 突发长度上限通常为 256 拍，AXI3 通常最多 16 拍；还要满足总线宽度、对齐和 4 KB 边界等规则。精确限制应按协议版本和目标 IP 的手册确认。AXI4-Lite 不使用突发长度字段，每次访问是一拍。

理论数据带宽可粗估为 `数据宽度（bit）÷ 8 × 时钟频率（Hz）`，实际有效带宽还会受突发长度、反压、仲裁、DDR效率、时钟域转换和 IP 限制影响。单纯增加位宽或时钟频率不保证应用吞吐量同比提升。

### 3.3 事务 ID 与顺序

AXI-MM 可用 ID 标记事务，使多个事务在途，并允许系统在规则允许时交错或乱序完成。互连/从设备需要保留足够的 ID 信息并保证响应归属正确。AXI4-Lite 通常不支持 ID 和多个 outstanding burst；对于简单寄存器访问，常以更简单的控制流换取易实现性。

## 4. AXI4-Lite：寄存器访问常用接口

AXI4-Lite 保留五通道的读写拆分和 VALID/READY 握手，但移除了多拍突发能力和相关 burst 控制。它非常适合 PS 配置 PL IP：

```text
CPU load/store
  → PS 的 AXI Master 端口
  → AXI Interconnect / 地址译码
  → AXI4-Lite Slave（例如 AXI GPIO）寄存器
```

软件访问外设寄存器时，驱动根据 BSP 的基地址访问寄存器。设备 ID 用于查找驱动配置，基地址用于定位寄存器，中断 ID 则用于识别 GIC 中断源，这三者含义不同。

## 5. AXI4-Stream：无地址的数据流

AXI4-Stream 每个接口至少有数据有效和接收准备的握手。常见信号如下：

| 信号 | 用途 |
|---|---|
| `TDATA` | 当前数据拍 |
| `TVALID` | 发送端声明数据拍有效 |
| `TREADY` | 接收端声明能够接收 |
| `TKEEP` | 指示 `TDATA` 中哪些字节有效 |
| `TLAST` | 标记一个包/帧段的末尾，具体语义由应用约定 |
| `TUSER` | 用户侧带信息，具体用途由应用约定 |

Stream 传输在上升沿满足 `TVALID && TREADY` 时完成。若 `TVALID=1` 但 `TREADY=0`，发送端需保持数据及相关侧带信号稳定。接收端可以用 `TREADY` 做反压。

**视频协议约定注意：**AXI4-Stream 本身不规定 `TLAST` 一定表示行尾、`TUSER` 一定表示帧开始。AMD/Xilinx 的 AXI4-Stream Video IP 通常约定 `TLAST` 表示一行结束、`TUSER[0]` 表示一帧的起始像素；具体仍需核对所连接 IP 的视频接口文档。

## 6. Zynq-7000 的 PS-PL AXI 端口

端口名称里的 `M`/`S` 代表 PS 视角或接口命名中的 Master/Slave 方向：

| 端口 | 谁发起事务 | 主要用途 |
|---|---|---|
| `M_AXI_GP0/1` | PS 是 Master，访问 PL | PS 访问 PL 侧外设寄存器，例如 AXI GPIO 的 AXI-Lite 寄存器 |
| `S_AXI_GP0/1` | PL 是 Master，访问 PS | PL Master 访问 PS 地址空间/内存映射资源 |
| `S_AXI_HP0..3` | PL 是 Master，访问高性能路径 | PL DMA/VDMA 等高带宽访问 DDR/OCM 的常用入口 |
| `S_AXI_ACP` | PL 是 Master，经 ACP 连接缓存一致性单元 | 可用于与 CPU cache 交互的一致性访问；需谨慎考虑缓存一致性属性与竞争 |

Zynq-7000 PS-PL 的 GP 接口基于 AXI3；HP/ACP 等也有各自的数据宽度、时钟和交易属性要求。端口的 Master/Slave 角色描述谁发起 AXI 事务，和 AXI4-Stream 视频链路中的“输入/输出”命名不要混淆。启用端口后还要确认相关 PS 配置、时钟、复位和 PL 电平转换设置正确。

### 6.1 如何选择端口（粗略规则）

- PS 只需设置 PL IP 控制寄存器：常从 `M_AXI_GP0/1` 进入 PL，目标 IP 使用 AXI4-Lite Slave。
- PL 中 DMA/VDMA 要向 DDR 读写大量数据：常接 PS 的 `S_AXI_HP` 端口；确认 HP 端口 enable、时钟、宽度和地址路径。
- PL 加速器需要与 CPU cache 协同：评估 ACP；不是所有大块数据吞吐场景都应优先选择 ACP。
- 选型还要结合带宽、延迟、缓存一致性、仲裁和 CPU 负载，不能只根据端口名字判断。

## 7. Vivado AXI 系统中常见 IP

- **AXI GPIO**：把 AXI-Lite 寄存器控制转换成 PL 并行 GPIO 输入/输出，可选择中断功能。
- **AXI Interconnect**：连接多个 AXI Master/Slave，负责地址译码、仲裁和路径组合；可配置协议/宽度转换能力。
- **AXI SmartConnect**：新设计中常见的自动化互连 IP，根据连接需求构建互连逻辑。
- **AXI Protocol Converter**：在支持的接口协议之间转换，例如 AXI3 到 AXI4-Lite。
- **AXI Data Width Converter**：在支持的条件下变换数据位宽。
- **AXI Clock Converter / Register Slice**：跨时钟域或插入流水寄存器以满足时序；不能替代系统级 CDC 检查。
- **AXI DMA**：内存映射与 AXI4-Stream 之间搬运通用数据。
- **AXI VDMA**：针对视频帧的 2D Memory-Mapped 与 AXI4-Stream 搬运，支持行步长、帧缓存和 Genlock 等视频相关功能。细节见本目录的 [VDMA Genlock 笔记](./axi_vdma_genlock_modes.md)。

## 8. 本仓库 `camera` Block Design 的 AXI 路径

根据 `camera.srcs/sources_1/bd/system/system.bd` 与当前生成的 `xparameters.h`，本工程这版 Block Design 中可确认的 AXI 路径是 **PS 通过 AXI GPIO 控制/读取一个 PL GPIO 引脚**。当前 BD 里有 AXI GPIO 和 AXI Interconnect，未看到 AXI VDMA 实例；VDMA 的概念笔记不代表它已经接入本设计。

```text
Cortex-A9 / PS
  │  CPU 访问 AXI GPIO 寄存器
  ▼
PS M_AXI_GP0（PS 作为 AXI Master）
  ▼
ps7_0_axi_periph / AXI Interconnect
  ▼
自动生成的 AXI Protocol Converter（AXI3 → AXI4-Lite）
  ▼
axi_gpio_0 / S_AXI（AXI GPIO 作为 AXI4-Lite Slave）
  ├── GPIO → 顶层 AXI_GPIO_KEY 引脚
  └── ip2intc_irpt → PS IRQ_F2P（中断独立于 AXI 读写通道）
```

本设计中 `axi_gpio_0` 的可核对参数：

- `C_GPIO_WIDTH = 1`：GPIO 通道宽度为 1 位。
- `C_IS_DUAL = 0`：不是双通道 GPIO。
- `C_INTERRUPT_PRESENT = 1`：IP 中包含中断功能。
- AXI-Lite 地址映射：`0x4120_0000`，地址范围为 `0x4120_0000–0x4120_FFFF`（BD 映射窗口 64 KiB）。实际 GPIO 驱动寄存器只占其中规定的寄存器偏移。
- BSP 中 `XPAR_AXI_GPIO_0_DEVICE_ID = 0`；`XPAR_FABRIC_GPIO_0_VEC_ID` 映射至本工程生成的 fabric 中断 ID。平台重新导出后，宏名/值可能变化，应查当前平台的 `xparameters.h`。
- AXI GPIO 的寄存器访问走 AXI-Lite；`ip2intc_irpt` 是单独的中断线，不是通过 AXI 数据通道“发送中断”。

相关 C 驱动函数：`XGpio_Initialize` 根据设备 ID 初始化驱动对象；`XGpio_SetDataDirection` 配置 GPIO 数据位方向；读写/中断 API 最终通过寄存器基址访问 AXI GPIO。具体通道宽度、方向和中断掩码需与当前 IP 参数一致。

## 9. VDMA 中的 AXI 通路（摄像头常见结构）

若后续在 PL 加入摄像头采集与显示链路，常见的帧缓存数据路径可以抽象为：

```text
摄像头接收/处理 IP
  → AXI4-Stream Video
  → VDMA S2MM（Stream to Memory-Mapped，写帧缓存）
  → PS DDR（通常经 HP 接口）
  → VDMA MM2S（Memory-Mapped to Stream，读帧缓存）
  → AXI4-Stream Video
  → 显示/视频处理 IP
```

VDMA 的寄存器一般经 AXI4-Lite 控制；帧数据则经 Memory-Mapped AXI 突发读写与 DDR 交换；视频像素数据经 AXI4-Stream 传输。它同时使用多个 AXI 接口类型，各自目的不同。帧缓存地址、stride、HSIZE、VSIZE、像素格式、AXIS 时钟/反压、FSYNC/Genlock 和 DDR 可达性都必须匹配。

## 10. 时钟、复位、地址与缓存一致性

### 10.1 时钟与复位

- 同一条 AXI 链路上的接口需满足相同或已正确转换的时钟关系；信号按相应 `ACLK` 采样。
- `ARESETN` 通常为低有效复位。解除复位的时序应符合互连和外设 IP 要求。
- Vivado BD 的 `FCLK_CLK0` 经常提供 PL AXI 外设时钟；但需要确认它与 AXI Master、Interconnect、Slave 的 `ACLK` 连接都正确。
- 不同频率或异步时钟域应放置合适的 Clock Converter/FIFO，并对时钟与复位做同步设计。

### 10.2 地址映射

- AXI-MM 通过地址决定目标 Slave/寄存器；地址由地址空间、地址段和互连译码共同决定。
- 在 Vivado Address Editor 中检查每个 Master 到 Slave 的 Address Segment 是否已分配、是否冲突、范围是否合理。
- 软件驱动使用 BSP 导出的基地址。硬件地址改变后，要重新生成/导出硬件平台并更新 BSP，避免软件仍使用旧 `xparameters.h`。
- 基地址/地址范围不是 GPIO 位宽，也不是 DDR 帧缓存地址；它们描述 CPU/AXI 对 IP 寄存器的地址窗口。

### 10.3 DMA 与 CPU Cache

DMA/VDMA 写入 DDR 的数据不一定自动与 Cortex-A9 数据缓存一致。若 CPU 和 DMA 共享同一缓冲区，需要根据所用端口和内存属性正确执行 cache flush/invalidate 或采用已配置的硬件一致性路径；还需注意缓存行对齐、缓冲区生命周期和访问所有权。`volatile` 只影响编译器对特定变量的优化，不会刷新/失效 CPU cache，也不能替代内存屏障或缓存维护。

## 11. 调试 AXI 问题的检查顺序

1. **确认接口类型和角色**：是 AXI-MM、AXI4-Lite 还是 AXI4-Stream？谁是 Master？谁是 Slave？
2. **确认 BD 连接**：AXI 接口是否连接到正确的 Interconnect/SmartConnect；是否自动插入 Protocol Converter/Clock Converter。
3. **检查地址**：Address Editor、`xparameters.h` 和软件驱动基地址是否一致。
4. **检查时钟/复位**：各 `ACLK` 和低有效 `ARESETN` 是否接对，复位是否释放。
5. **读写握手**：ILA 中观察 `AWVALID/AWREADY`、`WVALID/WREADY`、`BVALID/BREADY`、`ARVALID/ARREADY`、`RVALID/RREADY`。长期 VALID 无 READY 表示下游背压或连接/时钟/复位异常；发起写后要观察写响应。
6. **检查 Stream 反压**：`TVALID` 与 `TREADY` 是否能握手；堵塞时确认下游是否准备好，以及发送方是否正确保持数据不变。
7. **检查错误响应/中断**：AXI-MM 的 `BRESP/RRESP`、VDMA 状态寄存器、AXI GPIO 中断使能与 GIC 配置。
8. **DMA 数据问题**：确认 DDR 地址可达、地址和长度对齐要求、缓存维护、缓冲区大小、突发/stride/帧尺寸。
9. **区分 AXI 读写与独立信号**：中断、GPIO pin、电源/时钟复位等通常不是 AXI 数据通道本身。

## 12. 常见误区

- **把 AXI 当成一组共享数据线的传统并行总线。**AXI 是由独立通道、握手和属性字段组成的片上互连接口协议。
- **认为 VALID 或 READY 单独为 1 就完成了传输。**必须在同一个有效时钟边沿同时采样到二者为 1。
- **认为 AXI-Lite 可以做长突发搬运。**AXI4-Lite 面向寄存器访问，没有 AXI4 的 burst 传输能力。
- **认为 AXI4-Stream 有地址。**Stream 只有数据及可选侧带，流本身不进行地址译码。
- **把 IP 的 `M_AXI`/`S_AXI` 名称与整个系统的角色混为一谈。**角色要从具体接口的发起方和接收方判断。
- **认为 PL DMA 只要拿到 DDR 地址就一定能访问。**还要确认它连接到 PS 的 HP/ACP/其他可用路径，PS 端口已启用，地址映射、时钟、复位和缓存策略正确。
- **认为中断经 AXI 总线传输。**许多 PL IP 通过独立 interrupt wire 接到 GIC/PS IRQ 输入，AXI-Lite 通常用于配置中断寄存器。
- **认为 Genlock 或多帧缓存只靠 AXI 通道握手就会自动工作。**它们是 VDMA 的视频帧级管理功能，需要配好帧缓存和同步参数。

## 13. 推荐阅读

- Arm：《[Introduction to AMBA AXI4](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/Learn%20the%20Architecture/102202_0100_01_Introduction_to_AMBA_AXI.pdf)》：适合建立 VALID/READY、通道与事务概念。
- Arm：《[AMBA AXI and ACE Protocol Specification](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf)》：协议规范，查找具体信号、时序和限制。
- AMD：《[Vivado Design Suite: AXI Reference Guide (UG1037)](https://docs.amd.com/v/u/en-US/ug1037-vivado-axi-reference-guide)》：AXI 在 AMD/Xilinx IP 和 Vivado 工具中的使用。
- AMD：《[Zynq-7000 SoC Technical Reference Manual (UG585)](https://docs.amd.com/r/en-US/ug585-zynq-7000-SoC-TRM/PS-PL-AXI-Interfaces)》：Zynq-7000 PS-PL GP/HP/ACP 接口。
- AMD：《[AXI GPIO Product Guide (PG144)](https://docs.amd.com/r/en-US/pg144-axi-gpio)》：AXI GPIO 寄存器、中断和 IP 配置。
- AMD：《[AXI Interconnect Product Guide (PG059)](https://docs.amd.com/r/en-US/pg059-axi-interconnect)》：互连、译码、协议和宽度转换。
- AMD：《[AXI VDMA Product Guide (PG020)](https://docs.amd.com/r/en-US/pg020_axi_vdma)》：视频 DMA 的寄存器、帧缓存、AXI 通路和 Genlock。

## 14. 总结

把 AXI 系统拆成三个问题会更容易看懂：

1. **传什么：**寄存器/内存映射数据用 AXI-MM 或 AXI4-Lite；连续数据流用 AXI4-Stream。
2. **怎么连：**确认 Master/Slave 角色、地址译码、互连/协议转换、时钟和复位。
3. **谁来管理数据：**CPU 直接配置寄存器，DMA/VDMA 负责大量搬运；若共享 DDR，还要处理帧缓存、缓存一致性和同步。
