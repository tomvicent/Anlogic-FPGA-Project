# UDP 摄像头工程开发记录

> 日期：2026-10-28
> 工程：`Vitis/UDP/prj/udp_camera`（Vivado 2020.2，xc7z020clg400-2）
> 目标：OV5640 输出 JPEG → PL 采集 → AXI DMA → DDR → PS（lwIP/UDP）→ PC 接收

---

## 1. 总体方案与数据通路

需要先明确一点：**本方案不是"在 PL 里实现 JPEG 编码器"，而是使用 OV5640 芯片自带的 JPEG 压缩功能。**

PS 通过 EMIO 模拟 SCCB（I2C）把 OV5640 配置成 JPEG 输出模式，摄像头 DVP 接口上出来的
直接就是 JPEG 字节流（每帧以 `FFD8` 开头、`FFD9` 结尾，帧长度不固定）。PL 只负责：

1. 采集 8 位 DVP 字节流；
2. 打包成 AXI4-Stream（由 `Video In to AXI4-Stream` IP 完成，依据 VSYNC/HREF 划分帧）；
3. 经 FIFO + AXI DMA S2MM 写入 DDR；
4. PS 从 DDR 按 1024 字节一块通过 UDP 发给 PC。

```
                    EMIO SCCB (GPIO) 配置寄存器
   PS(Zynq) ───────────────────────────────────────► OV5640
      ▲                                                  │
      │                                                  │ DVP: PCLK / VSYNC / HREF / D[7:0]
      │                                                  ▼
      │                                        ┌──────────────────┐
      │                                        │ ov5640_data_8b   │  (本次添加的 IP)
      │                                        │  8 位数据透传     │
      │                                        └────────┬─────────┘
      │                              vid_clk / vid_ce / vid_vsync / vid_active_video / vid_data[7:0]
      │                                                 ▼
      │                                     ┌───────────────────────┐
      │                                     │ Video In to AXI4-Stream│  (v_vid_in_axi4s)
      │                                     └──────────┬────────────┘
      │                                                ▼
      │                                     ┌───────────────────────┐
      │                                     │ axis_data_fifo        │
      │                                     └──────────┬────────────┘
      │                                                ▼
      │                                     ┌───────────────────────┐
      │                                     │ AXI DMA (S2MM)        │
      │                                     └──────────┬────────────┘
      │                                                ▼
      │                                          DDR (PS 侧内存)
      │                                                │
      └──────────── lwIP UDP 发送 ◄───────────────────┘
                          │
                          ▼
                    PC (192.168.1.102:5001)
```

选用 OV5640 硬件 JPEG 的原因：

- 640×480 原始 RGB565 一帧约 600 KB，而 JPEG 一帧通常只有几十 KB，100M 以太网也能轻松传输；
- PL 不需要实现复杂的 JPEG 编码逻辑，节省 LUT/BRAM；
- 代价是帧长度可变，接收端要按 JPEG 头尾或 VSYNC 划分帧，不能按固定长度计算。

---

## 2. 本次改动记录

### 2.1 新增 IP：`ov5640_data_8b`

从正点原子例程 `Example/alientek-zynq7020-examples/ZYNQ_Vitis_7020/44_ov5640_ps_eth_udp_pc`
移植，放到工程的 IP 仓库：

```
Vitis/UDP/prj/udp_camera/ip_repo/ov5640_data_8b/
├── component.xml                      # IP 描述文件（Vivado 识别用）
├── src/
│   └── ov5640_data_8b.v               # 模块源码
└── xgui/
    └── ov5640_data_8b_v1_0.tcl        # IP 参数 GUI
```

工程的 `udp_camera.xpr` 中已配置：

```
<Option Name="IPRepoPath" Val="$PPRDIR/ip_repo"/>
```

Vivado 会扫描 `ip_repo` 下所有 `component.xml`，重新打开工程后在 IP Catalog 的
**User IP** 分类下即可看到 `ov5640_data_8b`（VLNV：`xilinx.com:user:ov5640_data_8b:1.0`）。

### 2.2 移除 IP：`ov5640_capture_data`

`ip_repo/ov5640_capture_data` 是 OV5640 采集 + RGB565→RGB888 转换的 IP（LCD 显示实验用，
输出 24 位 `vid_data`）。UDP JPEG 方案只需要原始 8 位字节流透传，因此用 `ov5640_data_8b` 替换。
该 IP 在 `Vitis/LCD/prj/LCD/ip_repo/ov5640_capture_data` 中保留了完全相同的副本，需要时可以取回。

`ip_repo/rgb2lcd` 未改动。

---

## 3. 模块端口说明

文件：`prj/udp_camera/ip_repo/ov5640_data_8b/src/ov5640_data_8b.v`

| 端口 | 方向 | 位宽 | 说明 |
|---|---|---|---|
| `rst_n` | in | 1 | 系统复位，低有效 |
| `cam_pclk` | in | 1 | 摄像头像素时钟（OV5640 DVP PCLK） |
| `cam_vsync` | in | 1 | 场同步，高电平有效（本设计按上升沿判帧） |
| `cam_href` | in | 1 | 行有效信号，高电平期间数据有效 |
| `cam_data` | in | 8 | 摄像头 8 位数据（JPEG 模式下即 JPEG 字节流） |
| `cam_rst_n` | out | 1 | 摄像头复位，低有效；本模块固定输出 1（不复位） |
| `cam_pwdn` | out | 1 | 摄像头掉电控制，高有效；本模块固定输出 0（不掉电） |
| `vid_clk` | out | 1 | 视频时钟，直接等于 `cam_pclk` |
| `vid_ce` | out | 1 | 视频时钟使能，高有效 |
| `vid_vsync` | out | 1 | 视频场同步（打拍后输出） |
| `vid_active_video` | out | 1 | 视频数据有效（打拍后的 HREF） |
| `vid_data` | out | 8 | 视频数据（打拍后的摄像头数据） |

IP 在 Block Design 中会以接口形式显示：`rst_n`、`vid_clk`、`cmos_jpeg`（包含
`vid_data` / `vid_active_video` / `vid_vsync`），以及独立的 `cam_*` 端口。

参数：

| 参数 | 默认值 | 说明 |
|---|---|---|
| `WAIT_FRAME` | 10 | 上电后等待摄像头输出的帧数，计满后才开始放行数据 |

---

## 4. 代码逐段讲解

### 4.1 摄像头控制信号

```verilog
assign cam_rst_n = 1'b1;   // 1：不复位
assign cam_pwdn  = 1'b0;   // 0：电源不休眠
```

模块本身不控制摄像头复位/掉电，始终让 OV5640 处于工作状态。真正的初始化（上电时序、
寄存器配置、JPEG 模式选择）由 PS 通过 EMIO SCCB 完成。

### 4.2 异步复位、同步释放

```verilog
always @(posedge cam_pclk or negedge rst_n) begin
    if(!rst_n) begin
        rst_n_d0   <= 1'b0;
        rst_n_sync <= 1'b0;
    end
    else begin
        rst_n_d0   <= 1'b1;
        rst_n_sync <= rst_n_d0;
    end
end
```

`rst_n` 来自 PS 侧（异步于 `cam_pclk`），直接拿它复位 `cam_pclk` 域的寄存器可能产生亚稳态。
这里用经典的"异步复位、同步释放"电路：复位拉低时立即生效（异步），释放时经过两级触发器
同步到 `cam_pclk` 域，后续所有时序逻辑都用 `rst_n_sync` 作为复位。

### 4.3 行/场同步打拍与场同步上升沿检测

```verilog
always @(posedge cam_pclk or negedge rst_n_sync) begin
    if(!rst_n_sync) begin
        cam_vsync_d0 <= 1'b0;
        cam_vsync_d1 <= 1'b0;
        cam_href_d0  <= 1'b0;
        cam_href_d1  <= 1'b0;
    end
    else begin
        cam_vsync_d0 <= cam_vsync;   // 第一级
        cam_vsync_d1 <= cam_vsync_d0; // 第二级
        cam_href_d0  <= cam_href;
        cam_href_d1  <= cam_href_d0;
    end
end

assign pos_vsync = ~cam_vsync_d1 & cam_vsync_d0;
```

- `cam_vsync`/`cam_href` 都打两拍，目的是与后面同样打两拍的数据 `cam_data_d1` **保持对齐**；
- `pos_vsync` 用"上一拍为 0、当前拍为 1"检测上升沿，得到每帧一个 `cam_pclk` 宽的脉冲，
  用来统计帧数。OV5640 的 VSYNC 是高电平有效，帧开始时产生上升沿。

### 4.4 帧计数与 `wait_done`

```verilog
always @(posedge cam_pclk or negedge rst_n_sync) begin
    if(!rst_n_sync)
        frame_cnt <= 4'd0;
    else if(pos_vsync && (frame_cnt < WAIT_FRAME))
        frame_cnt <= frame_cnt + 4'd1;
end

always @(posedge cam_pclk or negedge rst_n_sync) begin
    if(!rst_n_sync)
        wait_done <= 1'b0;
    else if(pos_vsync && (frame_cnt == WAIT_FRAME))
        wait_done <= 1'b1;
end
```

计数过程（`WAIT_FRAME = 10` 时）：

| VSYNC 上升沿 | `frame_cnt`（边沿后） | `wait_done` |
|---|---|---|
| 第 1~10 个 | 1 → 10 | 0 |
| 第 11 个 | 10（不再增加） | 1 |

也就是先完整接收 10 帧，从第 11 帧开始才把数据放行。原因是摄像头上电后要经过一段
自动曝光/自动白平衡的稳定时间，前几帧图像偏暗或偏色，丢掉可以避免 PC 端看到异常画面。
`wait_done` 一旦拉高，只有复位才能清零。

> 小细节：`frame_cnt` 声明为 `[5:0]`，但复位和加法用了 4 位常量 `4'd0`/`4'd1`。
> 由于 `WAIT_FRAME` 很小，功能没问题，只是位宽写法不统一；严谨些可统一成 `6'd0`/`6'd1`
> 或把声明改成 `[4:0]`。

### 4.5 数据打拍与输出选择

```verilog
always @(posedge cam_pclk or negedge rst_n_sync) begin
    if(!rst_n_sync) begin
        cam_data_d0 <= 8'd0;
        cam_data_d1 <= 8'd0;
    end
    else begin
        cam_data_d0 <= cam_data;
        cam_data_d1 <= cam_data_d0;
    end
end

assign vid_clk = cam_pclk;
assign vid_data          = wait_done ? cam_data_d1 : 8'b0;
assign vid_vsync         = wait_done ? cam_vsync_d1 : 1'b0;
assign vid_active_video  = wait_done ? cam_href_d1 : 1'b0;
assign vid_ce            = wait_done;
```

- 数据打两拍，与 HREF/VSYNC 的两级延迟对齐，输出时 `vid_data`、`vid_active_video`、
  `vid_vsync` 描述的是同一时刻的像素；
- `wait_done` 为 0 时输出全 0，相当于把前 10 帧屏蔽掉；
- `vid_clk` 直接用 `cam_pclk`，因此 Video 接口与摄像头接口同源同时钟。

### 4.6 为什么 `vid_ce` 一直为 1

`Video In to AXI4-Stream` 的 `vid_io_in_ce`（时钟使能）表示"当前这个 PCLK 上 `vid_data`
是不是一个有效数据"。两种模式的区别：

- **RGB565 模式**（原 `ov5640_capture_data`）：一个像素需要两个 8 位字节，`byte_flag`
  每拍翻转，只在拼成一个 16 位像素时才拉高 CE，输出 24 位 RGB888；
- **JPEG 模式**（本模块）：每个 PCLK 输出一个完整的 JPEG 字节，不存在拼字问题，
  所以 `wait_done` 之后 CE 恒为 1。数据是否有效由 `vid_active_video`（HREF）指示。

这也说明 JPEG 模式下帧长度是可变的：不能再用 `640 × 480 × 2` 之类的公式计算帧大小，
`v_vid_in_axi4s` 会依据 VSYNC/HREF 在帧结束时自动产生 `TLAST`，DMA 按帧/按块搬运即可。

### 4.7 与原 `ov5640_capture_data` 的对比

| 项目 | `ov5640_capture_data`（已移除） | `ov5640_data_8b`（当前） |
|---|---|---|
| 摄像头输出格式 | RGB565（每像素 2 字节） | JPEG（每字节即一个 JPEG 数据） |
| 数据位宽 | `vid_data[23:0]` | `vid_data[7:0]` |
| 字节拼接 | 需要 `byte_flag` 交替拼 16 位 | 不需要，直接透传 |
| `vid_ce` | `(byte_flag_d0 & active) \| !active` | `wait_done` 恒高 |
| 帧长度 | 固定 | **可变**（JPEG 压缩结果决定） |
| 典型用途 | LCD/HDMI 实时显示 | 以太网传输、存储 |

---

## 5. PS 侧 OV5640 JPEG 配置要点（供后续 Vitis 开发参考）

参考代码：
`Example/alientek-zynq7020-examples/ZYNQ_Vitis_7020/44_ov5640_ps_eth_udp_pc/vitis/ov5640_ps_eth_udp_pc/src/ov5640/ov5640_init.c`

关键配置：

| 寄存器 | 值 | 作用 |
|---|---|---|
| `0x4300` | `0x30` | 输出格式选择（YUV422，作为 JPEG 压缩输入） |
| `0x501f` | `0x00` | ISP 输出 YUV422 |
| `0x4713` | `0x03` | **JPEG mode 3**，开启硬件 JPEG 压缩 |
| `0x4407` | `0x01` | JPEG 量化比例（可调，影响画质/帧大小） |
| `0x460b` / `0x460c` | `0x35` / `0x22` | JPEG 相关时序 |
| `0x4837` | `0x16` | DVP PCLK 分频 |
| `0x3824` | `0x02` | DVP 时钟分频 |
| `0x3808~0x380b` | 640 / 480 | 输出分辨率 |
| `0x380c~0x380f` | 2844 / 1968 | 总行/场时间（决定帧率、PCLK） |

其它流程：

1. 读 `0x300a/0x300b` 确认芯片 ID 为 `0x5640`；
2. 写 `0x3008 = 0x82` 软复位，延时 1 ms，再写 `0x3008 = 0x02` 进入正常工作；
3. 通过 EMIO GPIO 模拟 SCCB（`emio_sccb` 接口）完成上述寄存器配置；
4. 配置 AXI DMA（S2MM）、中断、lwIP UDP。

例程中 UDP 发送行为（`udp_perf_server.c`）：

- 开发板 IP 由 `assign_default_ip()` 设置，目标 IP 为 `192.168.1.102`，端口 `5001`；
- PS 轮询 AXI GPIO 读取 FIFO 中的数据计数，≥1024 字节就启动一次 DMA 读 1024 字节到 DDR；
- DMA 完成后调用 `udp_tx_data(buffer, 1024)`，每包固定 1024 字节，没有额外包头。

---

## 6. 后续接入 Block Design 的步骤

本次只添加了 IP 核，尚未修改 `system.bd`。下一步在 Vivado 中操作：

1. 重新打开工程 / 刷新 IP Catalog，确认 User IP 中出现 `ov5640_data_8b`；
2. 在 Block Design 中添加该 IP：
   - `cam_pclk`、`cam_vsync`、`cam_href`、`cam_data`、`cam_rst_n`、`cam_pwdn` 引出到顶层；
   - `reset` 接系统复位（注意低有效）；
   - `vid_clk`、`cmos_jpeg` 接到 `Video In to AXI4-Stream`（当前 BD 里还没有，需要添加）：
     `ov5640_data_8b/cmos_jpeg → v_vid_in_axi4s/vid_io_in`，
     `vid_clk → vid_io_in_clk`，`vid_ce → vid_io_in_ce`；
3. `v_vid_in_axi4s/video_out → axis_data_fifo/S_AXIS → axi_dma/S_AXIS_S2MM`，
   DMA 的 `M_AXI_S2MM` 经 `axi_mem_intercon` 接到 PS 的 `S_AXI_HP0`；
4. PS 的 `GPIO_0`（EMIO）接 OV5640 的 SCCB 引脚（SCL/SDA），并在 PS 配置中启用 EMIO GPIO；
5. 更新约束文件：摄像头 PCLK/VSYNC/HREF/D[7:0]/SCL/SDA/PWDN/RST 引脚；
6. 综合、实现、生成 bitstream，导出 XSA 到 Vitis；
7. Vitis 中实现 lwIP UDP 发送 + PC 端接收程序。

PC 端接收建议：

- 绑定 UDP 5001 端口，按到达顺序拼接字节流；
- 用 JPEG 的 `FF D8`（SOI）和 `FF D9`（EOI）定位完整帧并保存为 `.jpg`；
- 例程没有包序号，UDP 丢包/乱序会直接破坏 JPEG。后续可自己加 4 字节包头
  （帧号 + 包序号），PC 端按序号排序、丢包时整帧丢弃，避免花屏/半张图。

---

## 7. 风险与注意事项

1. **JPEG 帧长度可变**：DMA 一次搬运 1024 字节是"按流切断"的，帧边界只能靠
   `TLAST`/VSYNC 或 PC 端 JPEG 标志判断；如果 DMA 配置成按固定长度搬运，需要确保软件
   能处理半个包/跨帧包。
2. **UDP 不可靠**：高分辨率/高帧率时容易丢包，优先保证网线直连、关闭 PC 防火墙干扰，
   并考虑加包头序号。
3. **`WAIT_FRAME` 不要设太小**：OV5640 上电后自动曝光稳定需要时间，太小可能看到偏暗画面。
4. **SCCB 配置必须在数据采集之前完成**：PS 初始化顺序是先 `emio_init()` → `ov5640_init()`，
   再启动 DMA/UDP，否则 PL 可能把未配置好的数据搬进 DDR。
5. **时钟约束**：`cam_pclk` 由摄像头提供，属于外部输入时钟，必须在约束文件里
   `create_clock`，否则时序检查不完整。

---

## 8. 时序问题记录（2026-10-28）

### 8.1 现象

实现后的 Timing Summary：

```
WNS(ns)  TNS(ns)  TNS Failing Endpoints
-3.767   -7.534   2
Timing constraints are not met.
```

`Other Path Groups Table`：

```
Path Group          From Clock   To Clock   WNS      TNS     Failing
**async_default**   clk_fpga_0   cam_pclk   -3.767   -7.534  2
```

两条违例路径完全一样，类型是 **Recovery（异步复位释放检查）**，不是 setup/hold 数据路径：

| 起点 | 终点 |
|---|---|
| `rst_ps7_0_100M/.../ACTIVE_LOW_PR_OUT_DFF[0].FDRE_PER_N/Q`（clk_fpga_0 域） | `ov5640_data_8b_0/inst/rst_n_d0_reg/CLR`（cam_pclk 域） |
| 同上 | `ov5640_data_8b_0/inst/rst_n_sync_reg/CLR`（cam_pclk 域） |

### 8.2 原因

`rst_n` 由 PS 的 `rst_ps7_0_100M` 产生，同步于 `clk_fpga_0`（100 MHz），但对 `cam_pclk`
（72 MHz）是异步的。模块内部用 `rst_n_d0 → rst_n_sync` 两级触发器做"异步复位、同步释放"，
第一级触发器的异步复位释放时刻与 `cam_pclk` 边沿没有固定关系，某个周期两者几乎重合
（报告中 recovery requirement 只有 0.015 ns），于是报 -3.767 ns。

这是复位同步器的固有特性：第一级即使发生亚稳态，也会在第二级采样前稳定下来，
因此这条 recovery 路径不应参与跨时钟域时序分析。**不是逻辑错误，也不影响功能。**

### 8.3 处理

在 `udp_camera.srcs/constrs_1/new/design.xdc` 中增加：

```tcl
set cam_rst_sync_cells [get_cells -quiet -hier -filter {NAME =~ *ov5640_data_8b_0/inst/rst_n_*_reg}]
set_property -quiet ASYNC_REG TRUE $cam_rst_sync_cells

set cam_rst_sync_pins [get_pins -quiet -hier -filter {NAME =~ *ov5640_data_8b_0/inst/rst_n_*_reg/CLR}]
set_false_path -quiet -from [get_clocks -quiet clk_fpga_0] -to $cam_rst_sync_pins
```

要点：

- `ASYNC_REG = TRUE` 告诉工具这两个触发器是同步器，帮助布局并提高 MTBF；
- `set_false_path` 只排除 `clk_fpga_0 → 复位同步器 CLR` 这一条跨时钟复位路径，
  不会误伤 `v_vid_in_axi4s` 内部异步 FIFO 的 `set_max_delay` CDC 约束；
- **XDC 文件不支持 `if`、`for` 等控制流**。之前用 `if {[llength ...]}` 判断对象是否存在，
  综合时会报 `CRITICAL WARNING: Command 'if' is not supported in the xdc constraint file`，
  导致约束实际未生效。正确做法是直接使用 `set_property -quiet` / `set_false_path -quiet`
  （对象为空时自动忽略）。

### 8.4 改完后检查

重新运行综合 + 实现，**实测结果（2026-10-28 16:17）**：

```
WNS = 2.983 ns   TNS = 0.000   TNS Failing Endpoints = 0
All user specified timing constraints are met.
```

- `**async_default** clk_fpga_0 → cam_pclk` 这一行已从 Other Path Groups Table 消失；
- `clk_fpga_0` 内部最差路径为 2.983 ns；
- `v_vid_in_axi4s` 内部异步 FIFO 的两条 CDC 路径仍正常参与时序检查
  （`clk_fpga_0 → cam_pclk` WNS 8.937 ns，`cam_pclk → clk_fpga_0` WNS 12.765 ns）。

另外 `check_timing` 仍会报 `10 input ports with no input delay`（HIGH）：`cam_data[7:0]`、
`cam_href`、`cam_vsync` 没有设置 `set_input_delay`，这些输入路径不做建立/保持分析。
当前参考例程也没有加，功能上可工作；若要严谨，可按 OV5640 数据手册的 DVP 输出时序补：

```tcl
set_input_delay -clock cam_pclk -max <max_delay> [get_ports {cam_data[*] cam_href cam_vsync}]
set_input_delay -clock cam_pclk -min <min_delay> [get_ports {cam_data[*] cam_href cam_vsync}]
```

---

## 9. DMA 传输卡死问题定位（2026-10-30）

### 9.1 现象

板子运行后只有第一次 DMA 搬运会发生，之后：

- 串口 `dbg:` 打印一直是 `fifo=4096 rx_done=0 dma=1 tx=0 drop=0`
  （FIFO 被摄像头填满后停住，DMA 标志一直停在"已启动"，UDP 一个包都没发出去）；
- PC 上位机"完全没包"；
- 即"AXI DMA 的中断卡住了"：**S2MM 传输完成中断永远进不到 CPU**。

### 9.2 定位过程

先排除数据源：`ov5640_init.c`、`emio_sccb_cfg.c`、`sys_intr.c` 与正点原子例程
`44_ov5640_ps_eth_udp_pc` 逐字节相同（`diff` 无差异），PL 的 `ov5640_data_8b` /
`v_vid_in_axi4s` / `axis_data_fifo` / `axi_dma` 参数也与例程一致。

对比例程与本工程 Block Design，**中断通路是唯一差别**：

| 项目 | 正点原子例程 | 本工程 |
|---|---|---|
| DMA `s2mm_introut` 接到 | `processing_system7_0/IRQ_F2P` 唯一一位 `[0]` | `xlconcat_1/In1` → `IRQ_F2P[1]` |
| PS `IRQ_F2P` 位宽 | 1 位 | 2 位（In0 接常量 0，In1 接 DMA） |
| 硬件实际中断号 | **61**（IRQ_F2P[0]） | **62**（IRQ_F2P[1]） |
| Vitis 生成的 `XPAR_FABRIC_AXI_DMA_0_S2MM_INTROUT_INTR` | 61 | **61（错误）** |

证据链（全部可在工程里复核）：

1. `udp_camera.srcs/sources_1/bd/system/system.bd` 的 nets：
   - `axi_dma_0_s2mm_introut` 的 ports 是 `axi_dma_0/s2mm_introut` + **`xlconcat_1/In1`**；
   - `xlconcat_1_dout` 的 ports 是 `xlconcat_1/dout` + `processing_system7_0/IRQ_F2P`；
   - PS 的 `IRQ_F2P` 为 `[1:0]`（2 位）。
2. 生成的 RTL `udp_camera.gen/.../synth/system.v`：
   ```verilog
   system_xlconcat_1_0 xlconcat_1 (
       .In0(1'b0),
       .In1(axi_dma_0_s2mm_introut),
       .dout(xlconcat_1_dout));
   ```
3. `xlconcat` 核源码 `ipshared/4b67/hdl/xlconcat_v2_1_vl_rfs.v` 里：
   ```verilog
   assign dout = {In1, In0};   // In1 = dout[1]
   ```
   所以 DMA 中断在 `dout[1]` → `IRQ_F2P[1]`。
4. Zynq-7000 的 PS 中断号是固定的：`IRQ_F2P[0]=61`、`IRQ_F2P[1]=62`。
5. 但 BSP 里
   `vitis/system_wrapper/ps7_cortexa9_0/.../include/xparameters.h:311`：
   ```c
   #define XPAR_FABRIC_AXI_DMA_0_S2MM_INTROUT_INTR 61U
   ```
   即 `axi_dma.c` 里的 `RX_INTR_ID` = **61**。
6. 用同一份 XSA 在临时 Vitis workspace 里**重新生成 BSP**，结果仍是 `61U`
   （实测，非 BSP 缓存问题）——Vitis 2020.2 对 `xlconcat` 上未接中断的 `In0`
   做了"跳过/压缩"，按已连接中断的顺序编号，没有计入位偏移。硬件不会压缩，
   `dout[1]` 物理上就是 `IRQ_F2P[1]`。
7. 平台里的 `system_wrapper.bit`（10-30 11:13）与 Vivado 最新实现产物
   `udp_camera.runs/impl_1/system_wrapper.bit`（10-30 11:09）MD5 完全一致：
   `1838525f3d9aa3eb8dbcd5dd0b6015d3`，确认板子上跑的就是"中断在 bit1"的硬件。

### 9.3 根因

**软件使能的 GIC 中断号（61）与硬件实际的中断号（62）不一致。**

`dma_setup_intr_system()` 里 `XScuGic_Connect/Enable(61, ...)`，
DMA 完成时拉高的是 `IRQ_F2P[1]`（GIC ID 62）。ID 62 在 GIC 中处于关闭状态，
中断永远进不来 → `rx_intr_handler()` 不执行 → `rx_done` 永远为 0。

主循环逻辑因此永久卡死：

```c
if ((fifo_count >= MAX_PKT_LEN) && (dma_start_flag == 0)) {  // 第一次进这里
    axi_dma_start(MAX_PKT_LEN);                            // DMA 搬了 1024 字节
    dma_start_flag = 1;
}
if (rx_done) {                                             // 永远进不去
    ...
    dma_start_flag = 0;                                    // 永远不会清零
}
```

第一次 DMA 完成后 FIFO 再次被填满，而 `dma_start_flag` 一直是 1，
不会发起第二次 DMA，也不会发 UDP。

### 9.4 快速确认（不改 PL、不改代码）

**方法 A：调试器看寄存器（最直接）**

| 地址 | 寄存器 | 预期值 | 含义 |
|---|---|---|---|
| `0x40400034` | AXI DMA `S2MM_DMASR` | bit1=1（Idle）、bit12=1（IOC_Irq） | DMA 已完成，完成中断挂起但没人处理 |
| `0xF8F01104` | GIC `GICD_ISENABLER1` | bit29=1、bit30=0 | 只使能了 ID 61，ID 62 是关的 |
| `0xF8F01204` | GIC `GICD_ISPENDR1` | bit30=1 | ID 62 已挂起（等一个永远不会来的使能） |

**方法 B：一行软件绕过，直接验证**

把 `axi_dma.c` 里改一行（临时）：

```c
/* 硬件实际是 xlconcat In1 -> IRQ_F2P[1] = GIC 62；
 * Vitis 生成的 XPAR_FABRIC_AXIDMA_0_VEC_ID 却是 61，临时绕过 */
#define RX_INTR_ID  62
```

重新编译运行。若串口 `dbg:` 的 `rx_done` 开始翻转、`tx` 持续增长、PC 开始收包，
则根因确认。（若之后又改回 BD 的 In0，必须改回 `XPAR_FABRIC_AXIDMA_0_VEC_ID`。）

### 9.5 正式修复（推荐）

**方案 1（永久推荐）：改 BD，让 DMA 中断落在 `IRQ_F2P[0]`**

1. Vivado 打开 `system.bd`，把 `axi_dma_0/s2mm_introut` 从 `xlconcat_1/In1`
   改接到 **`xlconcat_1/In0`**（或直接删掉 `xlconcat_1`，把 DMA 中断接到
   `processing_system7_0/IRQ_F2P[0]`）；
2. 重新综合、实现、生成 bitstream，重新导出 XSA 覆盖
   `vitis/system_wrapper/hw/system_wrapper.xsa`（及顶层同名文件），
   把新的 `.bit` 拷进 `hw/`；
3. Vitis 里刷新平台（Platform 右键 Update / 重新 Generate BSP），
   确认 `xparameters.h` 里 `XPAR_FABRIC_AXI_DMA_0_S2MM_INTROUT_INTR` = 61U，
   且 BD 里 DMA 确实接在 `IRQ_F2P[0]`；
4. 重新编译 `udp_camera` 下载运行。

这样硬件位号和软件 ID 一致，后续再加第二个中断时也可以规规矩矩用 `In1`（ID 62，
但要注意 Vitis 的编号问题，加完必须核对 `xparameters.h` 与 BD 是否一致）。

**方案 2（不想重新跑实现）：软件固定用 62**

```c
/* BD: axi_dma_0/s2mm_introut -> xlconcat_1/In1 -> IRQ_F2P[1] -> GIC ID 62 */
#define RX_INTR_ID  62
```

注意这是"绑定当前 bitstream"的写法，以后 BD 或中断接线一改就可能再次错位，
只建议作为临时验证手段。

### 9.6 顺带发现的健壮性问题（建议一并修）

1. **DMA 错误中断后永久卡死**
   `rx_intr_handler()` 的错误分支里 `XAxiDma_Reset()` 会把 `DMACR` 清零
   （中断使能位一并丢失），但没有重新 `XAxiDma_IntrEnable()`；
   同时主循环只看 `rx_done`，不会清 `dma_start_flag`。
   任何一次 DMA 错误（AXI 响应错误等）都会让系统永久停住。
   建议：

   ```c
   /* ISR 错误分支，Reset 完成后 */
   XAxiDma_IntrEnable(axidma_inst, XAXIDMA_IRQ_ALL_MASK,
                      XAXIDMA_DEVICE_TO_DMA);
   error = 1;   /* 让主循环能看见 */
   ```

   ```c
   /* main.c 主循环里增加 */
   if (error) {
       error = 0;
       rx_done = 0;
       dma_start_flag = 0;   /* 允许重新发起 DMA */
   }
   ```

2. **Cache 维护顺序**
   `axi_dma_start()` 在 `XAxiDma_SimpleTransfer()` **之后**才
   `Xil_DCacheFlushRange()`。S2MM 的目标缓冲区如果此时还有脏行，回写会覆盖
   DMA 刚写入的数据。虽然当前 `udp_tx_data()` 会在读之前 invalidate，
   实际不易触发，但顺序应当反过来：**启动 DMA 之前** flush/invalidate，
   DMA 完成、CPU 读之前再 invalidate。
   最省事的改法是把这个 flush 挪到 `XAxiDma_SimpleTransfer()` 前面。

3. **ISR 末尾多余的 `XAxiDma_IntrGetIrq()`**
   处理函数最后又读了一次中断状态但**没有 ack**，属于从例程带过来的冗余写法，
   建议删掉，避免误解（第二次读并不会清除中断）。

4. **包边界与 JPEG 帧边界无关**
   `main.c` 一次搬 1024 字节就发一包，TLAST/帧边界可能落在包中间，
   这是正常现象；PC 端按 `FFD8/FFD9` 拼帧即可（上位机已按此实现）。
   只有"多搬少发"（如原来的 1031/1024）才会真正撕裂码流，那个问题已修。

### 9.7 验证清单（修复后逐项确认）

- [ ] 串口 `dbg:`：`rx_done` 在 0/1 之间翻转，`tx` 持续增长，`drop` 基本不涨；
- [ ] `fifo` 不再长期停在 4096（而是在 1024 附近波动或保持不满）；
- [ ] PC 上位机选 `JPEG 裸流(FFD8/FFD9 拼帧)`、端口 5002，`已收帧` 递增、能出图；
- [ ] GIC `GICD_ISENABLER1` 中实际使用的中断位为 1，且与 BD 接线的位号一致；
- [ ] 断开/恢复摄像头或制造一次 DMA 错误后，系统能自动恢复，不再永久卡死。

> 经验：**凡是 BD 里经过 `xlconcat` 的 fabric 中断，导入 Vitis 后必须人工核对
> `xparameters.h` 中的 `..._INTR` 编号和 BD 里实际接的 `IRQ_F2P[n]`（ID = 61 + n）是否一致。**
> 这次就是 Vitis 生成的编号比实际硬件少算了 `xlconcat` 上空着的 `In0` 位。

---

## 10. 上位机联调与轮询绕过中断（2026-10-30）

### 10.1 板子侧代码修正

| 文件 | 改动 | 原因 |
|---|---|---|
| `src/main.c:58` | `MAX_PKT_LEN` `1031` → **`1024`** | DMA 一次从 FIFO 搬 1031 字节，但 `udp_tx_data()` 只发 1024 字节，多搬的 7 字节既不发送也不回 FIFO，每包丢 7 字节导致 JPEG 流被撕碎（收到包但永远解不出图） |
| `src/udp_perf_server.h:35-36` | `UDP_DEST_PORT` / `UDP_LOCAL_PORT` `5001` → **`5002`** | PC 本机 5001 被 NI(LabVIEW) 服务 `lktsrv` 占用（`Get-NetUDPEndpoint` 可见），绑定报 10013/10048 |

备份在 `上位机/备份_原始源码/`（`main.c.bak`、`udp_perf_server.h.bak`）。

### 10.2 PC 侧网络诊断（确认板子到底有没有发包）

在 PC 上依次验证：

1. `Get-NetIPAddress` → 有线网卡（Realtek GbE, ifIndex=6）已配 `192.168.1.102/24` ✓
2. `ping 192.168.1.10` → 通，ARP 解析到 `00-0A-35-00-01-02` ✓（说明 PHY/网线/lwIP 都正常）
3. 在 `0.0.0.0:5002` 上用 Python UDP socket 抓 12 秒包 → **0 个包到达**
4. `Get-NetAdapterStatistics` 测有线网卡 6 秒收字节数 → **0 字节增量**

结论：板子虽然能 ping 通（ICMP 有响应），但**完全没有往外发 UDP 视频包**。问题在板子侧，不在 PC 配置。

### 10.3 加调试打印定位卡在哪一段

在 `main.c` 主循环末尾加每秒一次的状态打印：

```c
xil_printf("dbg: fifo=%d rx_done=%d dma=%d tx=%u drop=%u\r\n",
           fifo_count, rx_done, dma_start_flag,
           udp_tx_pkt_cnt, udp_tx_drop_cnt);
```

同时 `extern` 引用了 `udp_perf_server.c` 里的 `udp_tx_pkt_cnt` / `udp_tx_drop_cnt`。

第一组结果：

```
dbg: fifo=4098 rx_done=0 dma=1 tx=0 drop=0
```

- `fifo=4098`：FIFO 有数据（OV5640 在出像素），排除摄像头问题；
- `dma=1`：DMA 已启动但 `rx_done` 永远不翻 0；
- `tx=0`：一个 UDP 包都没发出去。

**定位：DMA S2MM 完成中断没进 CPU**（即第 9 节记录的中断号 61/62 错位）。

### 10.4 轮询绕过中断

既然中断路由断了，不纠结改 BD/改 XSA，直接在主循环里轮询 `XAxiDma_Busy`：

```c
/* axi_dma.c 新增 */
int axi_dma_done(void) {
    if (error) return -1;
    if (XAxiDma_Busy(&axidma, XAXIDMA_DEVICE_TO_DMA)) return 0;
    return 1;
}

/* main.c 主循环里，if(rx_done) 之前加 */
if (dma_start_flag == 1 && !rx_done) {
    int _d = axi_dma_done();
    if (_d == 1) rx_done = 1;
    else if (_d == -1) rx_done = 1;
}
```

第二组结果：

```
dbg: fifo=4098 rx_done=0 dma=1 tx=6 drop=0
```

`tx=6`！DMA 硬件确实完成了 6 次传输并发出了 6 个包。但第 7 次又卡住了。

### 10.5 stat=0x5000：中断状态位堆积 + DMA 错误

在 dbg 行里加了 `axi_dma_raw_status()`（直接读 `XAxiDma_IntrGetIrq`）：

```
dbg: fifo=4098 rx_done=0 dma=1 tx=6 drop=0 stat=0x5000
```

`0x5000 = 0x1000 (IOC 完成) | 0x4000 (ERROR)`。

原因：中断处理函数 `rx_intr_handler()` 从来没被调用过（因为 GIC ID 62 没使能），所以：

- 每次 DMA 完成后 IOC 位（0x1000）一直挂着**没人 ack**；
- 第 7 次 DMA 出了错（0x4000），错误位也挂着没人处理；
- DMA 通道进入错误状态后 `XAxiDma_Busy` 永远返回忙，死锁。

### 10.6 修复：轮询时手动 ack 中断 + 出错自动 reset

把 `axi_dma_done()` 重写成"代替中断处理函数"的角色：

```c
int axi_dma_done(void) {
    u32 irq = XAxiDma_IntrGetIrq(&axidma, XAXIDMA_DEVICE_TO_DMA);

    if (irq & XAXIDMA_IRQ_ERROR_MASK) {
        XAxiDma_IntrAckIrq(&axidma, irq, XAXIDMA_DEVICE_TO_DMA);
        XAxiDma_Reset(&axidma);
        /* 等 reset 完成 ... */
        XAxiDma_IntrEnable(&axidma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
        error = 1;
        return -1;   /* 通知主循环：这包数据作废，重新发起 */
    }
    if (irq & XAXIDMA_IRQ_IOC_MASK) {
        XAxiDma_IntrAckIrq(&axidma, irq, XAXIDMA_DEVICE_TO_DMA);
        return 1;    /* 正常完成 */
    }
    return 0;        /* 还在搬 */
}
```

关键点：

1. **每次轮询都读并 ack 中断状态**——不 ack 的话 IOC/ERROR 位一直堆着，DMA 驱动内部状态会乱；
2. **出错就 reset 通道 + 重新开中断**——不让 DMA 永久卡死，下次循环自动恢复；
3. 返回 -1 时主循环会把 `rx_done` 置 1，发一个 stale buffer 然后 `dma_start_flag=0` 重新发起，不会死循环。

### 10.7 上位机（PC 端）

程序在 `D:\FPGA\Vitis\UDP\上位机\udp_video_station.py`（PySide6 GUI，单文件）。

接收设置：

| 控件 | 值 |
|---|---|
| 协议类型 | `JPEG 裸流(FFD8/FFD9 拼帧)` |
| 本地地址 | `192.168.1.102` |
| 本地端口 | `5002` |
| 远程地址 | `192.168.1.10` |
| 远程端口 | `5002` |

新增的 `JpegStreamAssembler` 按 `FFD8` 起帧、`FFD9` 切帧，自动丢弃帧头前的垃圾字节，不需要包序号。

### 10.8 后续待办

- [ ] 正式修中断号：按第 9.5 节方案 1 改 BD 让 DMA 中断落 `IRQ_F2P[0]`（ID 61），这样就不需要轮询绕过了；
- [ ] 轮询方案是 workaround，CPU 占用略高（每圈都读 DMA 寄存器），667MHz 下可接受；
- [ ] DMA 出错时会发一包 stale 数据，上位机解码失败计数会涨，属于正常恢复过程；
- [ ] 长期稳定后可删掉 dbg 打印，恢复纯中断驱动。

