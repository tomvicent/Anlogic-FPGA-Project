# OV5640 + ZYNQ PS 以太网（UDP）视频传输实验

> 工程：`Vitis/UDP/prj/udp_camera`  
> 平台：正点原子领航者 ZYNQ7020 / Vivado & Vitis 2020.2  
> 协议栈：lwIP 2.1.1，RAW API（`NO_SYS=1`）

---

## 1. 这个工程在做什么

OV5640 采集 640×480 图像（YUV422，YUYV 字节流），PL 把摄像头 DVP 数据转成 AXI4-Stream，写入 AXIS FIFO；PS 端轮询 FIFO 水位，用 AXI DMA 把数据搬进 DDR，再通过 lwIP 以 **1024 字节/包**的 UDP 数据报发给 PC 上位机显示。

UDP 层之上**没有自定义包头**，PS 只是把摄像头原始字节流按 1024 字节切片发送，因此必须使用配套的上位机（或自己写一个按 YUV422 解码的程序），普通网络调试助手只能看到十六进制数据。

### 数据通路

```
OV5640 (DVP 8bit, YUV422)
  └─> ov5640_data_8b        // 等待 10 帧、数据打拍
       └─> v_vid_in_axi4s   // 视频时序 -> AXI4-Stream
            └─> axis_data_fifo (4096 × 8bit)
                 ├─ axis_rd_data_count ──> AXI GPIO (PS 读 FIFO 水位)
                 └─> AXI DMA S2MM (Simple 模式)
                      └─> DDR @ 0x08000000 (rx_buffer_ptr)
                           └─> PS lwIP udp_send()
                                └─> PS GEM ──> RJ45 ──> PC 上位机
```

### 关键参数

| 项目 | 值 | 位置 |
|---|---|---|
| 开发板 IP | `192.168.1.10 / 255.255.255.0` | `src/main.c` `DEFAULT_IP_ADDRESS` |
| 网关 | `192.168.1.1` | `src/main.c` `DEFAULT_GW_ADDRESS` |
| PC 上位机 IP | `192.168.1.102` | `src/udp_perf_server.h` `UDP_DEST_IP_x` |
| UDP 端口 | 本地 5001 → 目的 5001 | `src/udp_perf_server.h` |
| 每个 UDP 载荷 | 1024 字节 | `UDP_VIDEO_PKT_LEN` |
| DMA 触发水位 | 1031 字节（`MAX_PKT_LEN`） | `src/main.c` |
| 摄像头分辨率 | 640×480，YUV422（YUYV） | `src/main.c` / `ov5640_init.c` |
| 单帧数据量 | 640×480×2 = 614400 字节 | — |
| 单帧包数 | 614400 / 1024 = 600 包 | — |
| DMA 目标地址 | `0x08000000` | `src/axi_dma/axi_dma.c` `RX_BUFFER_BASE` |
| lwIP pbuf 池 | 16384 × 1700 字节 | BSP `lwipopts.h` |

> 摄像头输出 30 fps 时，原始数据率约 **147 Mbit/s**（不含以太网/UDP/IP 开销），因此网口必须协商到 **1000 Mbps**；100 Mbps 链路一定丢包、花屏。

---

## 2. 软件实现流程

### 2.1 初始化（`main.c`）

1. `emio_init()`：初始化 EMIO 模拟 SCCB，用于配置 OV5640。
2. `ov5640_init(640, 480, 2844, 1968)`：通过 SCCB 写寄存器，输出 YUV422。
3. `axi_gpio_init()`：AXI GPIO 全输入，用于读取 FIFO 的 `axis_rd_data_count`。
4. `axi_dma_cfg()`：查找并初始化 AXI DMA（Simple 模式，无 SG）。
5. `Init_Intr_System()` / `Setup_Intr_Exception()` / `dma_setup_intr_system()`：初始化 GIC 并使能 DMA S2MM 完成中断。
6. `lwip_udp_init()`：
   - `lwip_init()`；
   - `xemac_add()` 注册 GEM 网口，`netif_set_default()`、`netif_set_up()`；
   - 配置静态 IP/掩码/网关；
   - `print_app_header()` 打印配置；
   - `start_application()` 创建 UDP PCB。

### 2.2 UDP 发送端（`udp_perf_server.c/.h`）

`start_application()`：

```c
pcb = udp_new();
udp_bind(pcb, IP_ADDR_ANY, 5002);          // 本地端口
udp_connect(pcb, &dest_ip, 5002);          // 目的：192.168.1.102:5002
```

`udp_connect()` 后，后续 `udp_send()` 不再需要每次指定目的地址。

`udp_tx_data(buffer, len)`：

```c
Xil_DCacheInvalidateRange((UINTPTR)buffer_ptr, len);   // 丢弃 DMA 写入前的旧 cache 行
ptr = pbuf_alloc(PBUF_TRANSPORT, len, PBUF_POOL);      // 1024 字节可放入单个 pbuf
pbuf_take(ptr, buffer_ptr, len);                       // 从 DDR 拷贝到 pbuf
udp_send(pcb, ptr);                                    // 交给 lwIP/EMAC
pbuf_free(ptr);                                        // 释放应用层引用
```

- `PBUF_POOL_BUFSIZE = 1700`，所以 1024 字节载荷只占一个 pbuf，效率高。
- Xilinx GEM 驱动在发送时会 `pbuf_ref()`，所以 `udp_send()` 返回后立即 `pbuf_free()` 是安全的；驱动在 TX 完成后释放最后一个引用。
- 发送是非阻塞的；pbuf 池暂时耗尽时该包直接丢弃（`udp_tx_drop_cnt++`），不会卡住采集循环。

### 2.3 主循环（`main.c`）

```c
while (1) {
    xemacif_input(netif);                     // 必须持续调用：处理 ARP 应答/收包

    fifo_count = get_fifo_count();            // PS 读取 AXIS FIFO 可读字节数
    if ((fifo_count >= MAX_PKT_LEN) && (dma_start_flag == 0)) {
        axi_dma_start(MAX_PKT_LEN);           // 启动 S2MM，搬 1031 字节到 DDR
        dma_start_flag = 1;
    }

    if (rx_done) {                            // DMA 完成中断置位
        udp_tx_data(rx_buffer_ptr, UDP_VIDEO_PKT_LEN);  // 发 1024 字节
        rx_done = 0;
        dma_start_flag = 0;
    }
}
```

DMA 完成中断在 `axi_dma.c:rx_intr_handler()` 中处理：清中断、`rx_done = 1`；出错时复位 DMA。cache 维护分两处：`axi_dma_start()` 里 `Xil_DCacheFlushRange()`（clean & invalidate），`udp_tx_data()` 读取前再 `Xil_DCacheInvalidateRange()`。

### 2.4 一次传输的完整时序

```
PL: OV5640 持续采数 -> FIFO 水位上升
PS: 轮询到 fifo_count >= 1031
PS: 启动 AXI DMA S2MM（读 1031 字节）
PL: DMA 把 FIFO 数据写入 DDR 0x08000000
PL: 传输完成 -> S2MM 中断
PS: rx_done=1 -> udp_tx_data()
PS: 无效 cache -> pbuf_take -> udp_send -> pbuf_free
PC: 上位机收到 1024 字节 UDP 数据，按 YUV422 显示
```

---

## 3. 重点笔记 / 避坑清单

### 3.1 IP 与端口

- 开发板固定 `192.168.1.10/24`，PC 必须配成同网段（默认代码目标是 `192.168.1.102`），并关闭 Windows 防火墙对 UDP 5001 的拦截。
- PC 如果改 IP，要同步修改 `udp_perf_server.h` 里的 `UDP_DEST_IP_0..3`，**重新编译**。
- 若用路由器 DHCP，注意不要让 PC 与开发板处于不同网段。

### 3.2 `xemacif_input()` 不能省

RAW API 没有后台线程；`xemacif_input(netif)` 负责从 EMAC 收包队列取包。首次发送前 lwIP 需要通过 ARP 解析 PC 的 MAC 地址，ARP 应答必须在主循环里被处理。漏掉它会出现“能 ping 通、发不出图像”或只有零星数据。

### 3.3 DMA 与 Cache 一致性（最容易翻车）

AXI DMA 通过 AXI 总线直接写 DDR，**不经过 CPU cache**。CPU 读 `rx_buffer_ptr` 时如果命中旧 cache 行，就会把上一包数据再发一次。因此 `udp_tx_data()` 里在读取前调用：

```c
Xil_DCacheInvalidateRange((UINTPTR)buffer_ptr, len);
```

- DMA 缓冲区地址 `0x08000000` 和长度 1024 都是 32 字节对齐的，可安全按 cache 行无效化。
- 如果以后把 DMA 缓冲区改成非对齐地址，或在这个函数里传入栈上/普通变量地址，**不要**做 cache 无效化，否则可能丢掉 CPU 尚未写回的数据。
- 若开启双缓冲，每个缓冲区都要单独做 cache 维护。

### 3.4 DMA 缓冲区地址不能落进 lwIP 内存池（本工程已修正）

本 BSP 的 `lwipopts.h` 里 `PBUF_POOL_SIZE = 16384`、`PBUF_POOL_BUFSIZE = 1700`，lwIP 会在 `.bss` 中静态分配一个约 **28 MB** 的 pbuf 池。实测本工程链接结果：

```
memp_memory_PBUF_POOL_base = 0x00287784   // pbuf 池起始
memp_memory_PBUF_base      = 0x01E8B804   // 池结束（下一个 pool）
__bss_end                  = 0x02008034   // 整个镜像结束（约 32 MB）
```

原厂例程把 DMA 目标地址设为 `0x01400000`（20 MB 处），**正好落在 pbuf 池内部**。正常运行时 pbuf 分配从池头部开始、释放也回到头部，一般不会碰到 20 MB 处，所以能“看起来正常”；但这属于越界使用保留内存，一旦 pbuf 用量增大或 lwIP 配置变化就可能破坏数据甚至死机。

本工程已将 `axi_dma/axi_dma.c` 中的 `RX_BUFFER_BASE` 改为：

```c
#define RX_BUFFER_BASE  0x08000000U   // 128 MB，位于 .bss 之后、DDR 范围内
```

只要 DDR ≥ 128 MB（本板 PS 配置为 1 GB）就安全。若你自行修改 lwIP 池大小或链接脚本，请重新核对 `.map` 文件，确保 DMA 缓冲区不与 `.bss/.heap/.stack` 重叠。

### 3.5 `MAX_PKT_LEN = 1031` 与 `1024` 的关系

正点原子原例程就是这么写的：

- 当 FIFO 水位 ≥ **1031** 时启动 DMA，DMA 实际搬 **1031** 字节；
- UDP 只发送缓冲区开头的 **1024** 字节，剩下 7 字节不发送，下一次 DMA 会覆盖它们。

也就是说，按原厂代码，数据流每 1031 字节会丢掉 7 字节，这依赖配套上位机的容错/重组方式。实测（原厂论坛）`MAX_PKT_LEN` 在 1024～1031 之间都能工作，超过 1031 容易触发 `XAxiDma error`。**如果上位机按 1024 字节固定切片重组，建议把 `MAX_PKT_LEN` 也改成 1024**，让“DMA 搬运长度 = UDP 发送长度”，字节流才是连续的：

```c
#define MAX_PKT_LEN 1024
```

改完要观察上位机是否仍有斜纹/错位；不同版本上位机行为可能不同。

### 3.6 UDP 是无连接的

- 丢包不会重传，网络拥塞、PC 处理不及时都会造成花屏/撕裂，这是正常现象。
- 不要在同一循环里加 `xil_printf`，串口打印非常慢，会直接拖垮发送带宽。
- 想统计丢包，可在 Vitis 调试器里观察 `udp_tx_pkt_cnt`、`udp_tx_drop_cnt`、`fifo_count`、`rx_done`。

### 3.7 带宽与链路速率

- 640×480×2 B×30 fps ≈ 18.4 MB/s ≈ 147 Mbit/s，加上 UDP/IP/以太网开销约 160 Mbit/s。
- 必须使用千兆网口/千兆交换机/超五类以上网线，PC 网卡也要显示 1.0 Gbps。
- 百兆链路跑 640×480 YUV422 必然严重丢帧，只能降低分辨率/帧率或改用 JPEG。

### 3.8 中断与 DMA

- `dma_setup_intr_system()` 里给 S2MM 中断设置优先级 0xA0（数值越低优先级越高），并注册 `rx_intr_handler`。
- 中断处理只做清状态和置 `rx_done`，真正的搬数据和网络发送都在主循环完成，避免长时间占用中断。
- 出错时 `rx_intr_handler` 会复位 DMA；若频繁出现 `XAxiDma error`，先降低 `MAX_PKT_LEN`、检查 FIFO 是否溢出、确认 PL 位流与 Vitis 工程匹配。

### 3.9 工程文件命名

`udp_perf_server.c/.h` 是 Vitis lwIP 模板留下的名字，里面已不再是 iperf 服务器。`main.c` 的 include 和函数调用依赖这两个文件名，所以没有改名；阅读时不要被名字误导。

---

## 4. 编译与运行步骤

1. **Vivado**：打开 `udp_camera.xpr`，确认 Block Design 已综合实现并生成比特流；导出 XSA（工程 `vitis` 目录已带 `system_wrapper` 平台和 `_ide/bitstream/system_wrapper.bit`）。
2. **PC 网络设置**：有线网卡配置静态 IP `192.168.1.102`，掩码 `255.255.255.0`（网关可空）；关闭其他网卡，避免路由走错。
3. **Vitis**：
   - 打开工作空间 `Vitis/UDP/prj/udp_camera/vitis`；
   - 先 Build `system_wrapper` 平台，再 Build `udp_camera` 应用；
   - 连接 JTAG，Program FPGA（`system_wrapper.bit`），Run/Debug `udp_camera.elf`。
4. **串口**（115200）应看到：
   ```
   OV5640 detected successful!
   AXI DMA CFG Success
   Board  IP : 192.168.1.10  (local port 5001)
   Target IP : 192.168.1.102  (port 5001), 1024 bytes/datagram
   UDP video stream started: port 5001 -> 192.168.1.102:5001
   ```
5. **PC 端**：
   - `ping 192.168.1.10` 确认链路；
   - 打开配套上位机，监听/接收 UDP 5001 端口，显示摄像头画面。
6. **抓包验证**：Wireshark 过滤 `udp.port == 5001`，应看到源 `192.168.1.10`、目的 `192.168.1.102`、UDP 长度 1032（1024 载荷 + 8 字节 UDP 头）的连续数据报；30 fps 时约 18000 包/秒。

---

## 5. 常见问题排查

| 现象 | 排查方向 |
|---|---|
| 串口 `OV5640 detected failed` | 摄像头排线、SCCB（EMIO）引脚约束、OV5640 供电/复位 |
| `ping` 不通 | IP/掩码/网线/防火墙；串口打印的板卡 IP 是否为 `192.168.1.10` |
| 能 ping，上位机无图像 | 目的 IP 是否改成 PC 实际 IP；UDP 5001 是否被防火墙拦截；是否用了配套上位机 |
| 花屏、斜纹、撕裂 | UDP 丢包（检查千兆链路、CPU 占用）；`MAX_PKT_LEN` 与上位机切片是否一致；cache 是否无效化 |
| 大面积绿色/灰色 | 上位机按 YUV422 解码；确认 OV5640 寄存器 `0x4300 = 0x30`（YUV422, YUYV） |
| 串口反复 `XAxiDma error` | 降低 `MAX_PKT_LEN`（1024～1031）；确认 PL 位流与工程匹配；检查 FIFO 是否溢出 |
| 帧率很低 | 网口是否只有 100M；是否在循环里打印；PC 端解码性能 |
| 运行一会儿后不显示 | 检查 `udp_tx_drop_cnt` 是否增长（pbuf 耗尽/网络拥塞）；检查 DMA 是否复位 |

**排查顺序建议**：串口初始化日志 → `ping` → Wireshark 看是否有 1024 字节 UDP 流 → 上位机显示。先证明“有数据在发”，再查“数据是否正确”。

---

## 6. 可选的改进方向

1. **双缓冲 / Ping-Pong**：当前只有一个 DMA 缓冲区，`udp_tx_data` 拷贝期间 DMA 必须等下一轮；双缓冲可让 DMA 写入和网络发送并行，降低丢帧。
2. **按帧/行边界触发 DMA**：利用 AXI-Stream 的 `TLAST`/帧同步，而不是固定 1031 字节阈值，可避免跨行切片。
3. **零拷贝**：用 `pbuf_alloc(PBUF_REF)` 指向 DMA 缓冲区，配合双缓冲和发送完成回调，省掉 1024 字节 `pbuf_take` 拷贝。
4. **降低带宽**：OV5640 输出 RGB565/JPEG、降低分辨率或帧率；JPEG 需要 PC 端解码。
5. **可靠性**：UDP 加自定义序号/NACK，或改 TCP（延迟更大）；用于产品时建议 RTP/RTSP。
6. **性能统计**：定期在串口打印 `udp_tx_pkt_cnt / udp_tx_drop_cnt / fifo_count`（例如每 5 秒一次，放在发送路径之外）。

---

## 7. 源码索引

| 文件 | 作用 |
|---|---|
| `src/main.c` | 初始化、lwIP 网口、主采集/发送循环 |
| `src/udp_perf_server.c/.h` | UDP PCB 创建、连接、`udp_tx_data()` 发送 |
| `src/axi_dma/axi_dma.c/.h` | AXI DMA 配置、启动、S2MM 中断处理 |
| `src/axi_gpio_cfg/axi_gpio_cfg.c/.h` | 读取 AXIS FIFO 可读字节数 |
| `src/emio_sccb_cfg/` | EMIO 模拟 SCCB 时序 |
| `src/ov5640/ov5640_init.c/.h` | OV5640 上电与寄存器配置 |
| `src/sys_intr/` | GIC 中断系统初始化 |
| `src/platform_zynq.c` | lwIP 平台适配（`xemac_add` 等） |
