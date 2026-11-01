# 连接矩阵

工程：四轴电机闭环控制 FPGA 系统
器件：安路 Anlogic DR1M90GEG400（米联客 MLK-F3P-CZ02 DR1）

本文件描述三件事：**(A)** 板级物理连接与引脚预算；**(B)** 顶层内部信号连接；**(C)** 子模块间连接。

---

## A. 板级物理连接与引脚预算

### A.1 可用板级资源（来自 `doc/hw/config.json`，已交叉核对）

| 资源 | Bank | 信号数 | 电压 | 电压选择 | 当前可自动约束 | 备注 |
|------|------|--------|------|----------|----------------|------|
| `FEP` 高速扩展 | 32（原理图老编号 34） | 48 | 未定，允许 1.8/2.5/3.3 | 跳线 `J3` | ❌ | 需 `project_port_name_and_direction_confirmed` + `j3_bank32_voltage_physically_confirmed` |
| `CEP-J12` | 11 | 24 | 3.3V（LVCMOS33） | 无 | ❌ | 需先选定协议 |
| 板载 `LED3` | 33 | 1（`J15`） | 3.3V | — | ✅ | 仅需确认端口名 |
| 板载 `LED4` | 33 | 1（`M20`） | 3.3V | — | ✅ | 仅需确认端口名 |
| 板载 `KEY1` | 33 | 1（`K14`） | 3.3V | — | ❌ | **与 `pl_eth_mdio` 复用冲突** |
| 板载 `KEY2` | 33 | 1（`J14`） | 3.3V | — | ❌ | **与 `pl_eth_mdc` 复用冲突** |
| `PL_CLK` | 33 | 1（`H16`） | 3.3V | — | ✅ | 100 MHz |

**可用业务 IO 总量 = 48（FEP）+ 24（CEP）= 72 根。**

> 板载按键只有 2 个且都与 PL 以太网引脚复用，**4 路微动开关无法使用 `KEY1`/`KEY2`**，必须走扩展连接器。这是本设计必须跨连接器的根本原因。

### A.2 顶层端口分组与引脚需求

| # | 信号组 | 顶层端口 | 宽度 | 方向 | 模式条件 |
|---|--------|----------|------|------|----------|
| 1a | 三相上管 | `o_m_pwm_hi_a/b/c` | 3 × 4 = 12 | out | 仅三相模式 |
| 1b | 三相下管 | `o_m_pwm_lo_a/b/c` | 3 × 4 = 12 | out | 仅三相模式，依赖 `D1` |
| 1c | 步进脉冲 | `o_m_step_pul` | 4 | out | 仅步进模式 |
| 1d | 步进方向 | `o_m_step_dir` | 4 | out | 仅步进模式 |
| 2 | SPI 角度 | `o_spi_sck` / `o_spi_mosi` / `i_spi_miso` / `o_spi_cs_n` | 4 × 4 = 16 | 3 出 1 入 | — |
| 3 | ABZ 编码器 | `i_abz_a` / `i_abz_b` / `i_abz_z` | 3 × 4 = 12 | in | — |
| 4 | 微动开关 | `i_sw` | 4 | in | — |
| 5 | 数字输出 | `o_dout` | 4 | out | 依赖 `D6`（1 或 2 路/轴） |
| 6 | 时钟 | `i_clk` | 1 | in | 板载 `H16`，不占连接器 |
| 7 | 复位 | `i_rst_n` | 1 | in | 依赖 `D7` |
| 8 | 状态指示 | `o_led` | 2 | out | 板载 `J15`/`M20`，不占连接器 |

**连接器引脚需求（当前默认方案）**

```
1a + 1b + 1c + 1d = 12 + 12 + 4 + 4 = 32
2 (SPI)                             = 16
3 (ABZ)                             = 12
4 (开关)                            =  4
5 (数字输出)                        =  4
7 (复位)                            =  1
                                    ------
合计                                 = 69   （+ 板载 clk/led 共 3 根 = 72）
```

### A.3 引脚分配提案

| 连接器 | 承载信号组 | 占用引脚 | 容量 | 余量 | 电压前提 |
|--------|-----------|----------|------|------|----------|
| `FEP`（bank 32） | 电机驱动 32 + ABZ 12 + 微动开关 4 | **48** | 48 | **0** | J3 必须为 **3.3V**（编码器与驱动器均为 3.3V 逻辑） |
| `CEP-J12`（bank 11） | SPI 16 + 数字输出 4 + 复位 1 | **21** | 24 | 3 | 固定 3.3V LVCMOS33 |
| 板载（bank 33） | `PL_CLK`(H16) + `LED3`(J15) + `LED4`(M20) | 3 | — | — | 3.3V |

分配理由：

- **`FEP` 全部给电机与编码器**：这两组信号对时序最敏感、速率最高，且都必须在同一 bank 内以保证电压一致（J3 一档同时决定整个 bank 32）。ABZ 与 PWM 放在同一 bank 可避免跨 bank 的走线长度差异影响相位。
- **`CEP-J12` 给 SPI、开关与数字输出**：`CEP-J12` 是固定 3.3V，无需跳线，适合承载对电压最不敏感、速率最低的外设。3 根余量可用于将来的状态输出或调试。

### A.4 引脚预算的收紧点（关键风险）

**当前方案把 FEP 吃到 0 余量。** 这意味着：如果 FEP 上有任何一根引脚实际不可用（被板载外设占用、或被原理图未标注的复用占用），方案立刻溢出。

三个可用的收紧手段，按优先级：

| 优先级 | 手段 | 释放引脚 | 前提 |
|--------|------|----------|------|
| 1 | **确认 `D1`：外部栅极驱动自带死区** | **+12** | 驱动器为 3 输入型（如带内部死区的智能驱动），PL 无需输出下管信号 |
| 2 | **确认 `D3`：4 路 SPI 共享 SCK+MOSI** | **+6** | 4 个传感器型号一致、SPI 模式一致 |
| 3 | 微动开关移至 `CEP-J12` 余量 | +4 | 引脚走线可接受 |

**若手段 1 成立**，FEP 占用降为 36，余量 12，方案非常宽松。
**若手段 1 与 2 都成立**，FEP 占用降为 30，余量 18。

> **这一节必须在上约束前解决**。它同时解释了两件事：为什么 `D1` 是架构级决策（不只是参数问题），以及为什么 `doc/hw/config.json` 的 `constraint_readiness` 把 `shared_pin_route_choices_not_confirmed` 列为阻塞原因。

### A.5 不可用于本设计的板级资源（禁止绑定）

以下资源在 `config.json` 的 `constraint_generation_policy.never_generate_pl_pin_constraints_for` 中明确列出，**任何情况下都不得绑定**：

- PS DDR3、PS QSPI、PS eMMC
- PS Ethernet MIO、PS USB ULPI MIO、PS TF/SDIO MIO、PS UART MIO
- PS clocks、resets、JTAG、configuration pins（含 `PS_POR_N`、`PS_SRST_N`、`PROGRAMN`、`INITN`、`DONE`）

以上均为 PS 专用或配置专用资源，绑定会破坏启动通路。

### A.6 引脚级映射（已在硬件档案中齐备，供约束阶段直接引用）

`doc/hw/config.json` 的 `board_profile.connectors[*].signal_pins` 已逐条记录"连接器位号 ↔ 封装引脚"的映射，例如：

| 连接器 | 连接器位号 | 封装引脚 | Bank | 极性 |
|--------|-----------|----------|------|------|
| FEP | `A4` | `V20` | 32 | P |
| FEP | `A5` | `W20` | 32 | N |
| FEP | `A6` | `Y18` | 32 | P |
| FEP | `A7` | `Y19` | 32 | N |
| FEP | `A8` | `Y16` | 32 | P |
| FEP | `A9` | `Y17` | 32 | N |
| CEP-J12 | `J12-3` | `Y12` | 11 | — |
| CEP-J12 | `J12-4` | `Y13` | 11 | — |
| CEP-J12 | `J12-5` | `T9` | 11 | — |
| CEP-J12 | `J12-6` | `U10` | 11 | — |

**约束阶段不需要重新从 PDF 提取引脚**，直接引用本表数据源即可。但需注意：

- FEP 的引脚按**差分对（P/N）**组织（48 信号 = 24 对）。本设计全部使用**单端信号**，因此每对中只用一个引脚，实际可用单端信号数仍为 48（不是 24）。这与 `coverage.fep_signal_count = 48` 一致。
- FEP 的 `usable_for_auto_constraint` 当前为 `false`，`required_conditions` 为 `project_port_name_and_direction_confirmed` + `j3_bank32_voltage_physically_confirmed`。**顶层端口名在本文件中已冻结**，因此只剩 J3 电压需要物理确认。

---

## B. 顶层内部信号连接

`rtl/top_skeleton.sv` 中的所有内部连线，及其生产者与消费者。

| 信号 | 宽 | 生产者 | 消费者 | 协议 | 备注 |
|------|----|--------|--------|------|------|
| `sys_rst_n` | 1 | `clk_reset_gen` | 全部模块 | 电平，低有效，同步释放 | 不得直连 `i_rst_n`（边界 B6） |
| `por_done` | 1 | `clk_reset_gen` | `digital_out_safe` | 电平 | `0` 期间强制安全态（边界 B9） |
| `en_ctrl_tick` | 1 | `clk_reset_gen` | 4 × `axis_ctrl`、`feedback_fusion`、`pid_ctrl` | 单拍使能 | 1 kHz |
| `en_deb_tick` | 1 | `clk_reset_gen` | 4 × `debounce`、可选 ABZ 滤波 | 单拍使能 | — |
| `en_pwm_tick` | 1 | `clk_reset_gen` | `sync_timebase` | 单拍使能 | 可选，载波亦可自由运行 |
| `tb_run` | 1 | `sync_timebase` | 4 × `axis_ctrl` | 电平 | 全局启停，四轴同拍采样 |
| `tb_carrier_cnt[15:0]` | 16 | `sync_timebase` | 4 × `axis_ctrl` → `pwm3ph_deadtime` | 广播只读 | **全局唯一**载波（边界 B1） |
| `tb_carrier_dir` | 1 | `sync_timebase` | 4 × `axis_ctrl` → `pwm3ph_deadtime` | 广播只读 | 中心对齐用 |
| `tb_carrier_wrap` | 1 | `sync_timebase` | 4 × `axis_ctrl` | 单拍脉冲 | — |
| `sw_deb[3:0]` | 4 | 4 × `debounce` | `reg_file` / 上层逻辑 | 电平 | 已去抖，已按极性映射 |
| `axis_dout_req[3:0]` | 4 | 4 × `axis_ctrl`（`o_dout_req`） | `digital_out_safe` | 电平（逻辑值） | 极性映射在 `digital_out_safe` 内完成 |
| `axis_fault[3:0]` | 4 | 4 × `axis_ctrl` | `o_led[0]`、`reg_file` | 电平 | — |
| `axis_aligned[3:0]` | 4 | 4 × `axis_ctrl` | `o_led[1]`、`reg_file` | 电平 | — |
| `axis_pos_meas[31:0]` ×4 | 32 | `axis_ctrl`（`o_pos_meas`） | `reg_file` | 数据 | 观测/回读 |

**位-每-轴展开规则**（顶层用 `generate` 完成，下游 RTL 必须沿用）：

```systemverilog
// 每轴的 8 位驱动输出按轴号 a 展开到 8 条 4 位总线的第 a 位
assign o_m_pwm_hi_a[a] = ax_pwm_hi_a;
assign o_m_pwm_hi_b[a] = ax_pwm_hi_b;
assign o_m_pwm_hi_c[a] = ax_pwm_hi_c;
assign o_m_pwm_lo_a[a] = ax_pwm_lo_a;
assign o_m_pwm_lo_b[a] = ax_pwm_lo_b;
assign o_m_pwm_lo_c[a] = ax_pwm_lo_c;
assign o_m_step_pul[a] = ax_step_pul;
assign o_m_step_dir[a] = ax_step_dir;
// 输入方向同理反向展开
```

---

## C. 子模块间连接（`axis_ctrl` 内部）

每个 `axis_ctrl` 实例内部的连接关系。四个实例结构完全相同，仅参数不同。

| # | 生产者 | 信号 | 消费者 | 协议 | 延迟/背压 |
|---|--------|------|--------|------|-----------|
| C1 | `abz_decoder` | `pos_cnt[31:0]` | `feedback_fusion`、`pid_ctrl`(经 fusion) | 数据（连续） | 每 clk 更新，无背压 |
| C2 | `abz_decoder` | `pos_snap[31:0]` | `feedback_fusion` | 数据（快照） | 与 SPI 帧完成同拍有效 |
| C3 | `spi_master_angle` | `frame_done` | `abz_decoder`.`i_snap_req`、`angle_frame_decode`、`feedback_fusion` | 单拍脉冲 | 触发原子快照（不变量 F1） |
| C4 | `spi_master_angle` | `rx_data[31:0]` | `angle_frame_decode` | 数据 | 随 `frame_done` 有效 |
| C5 | `angle_frame_decode` | `angle[15:0]`、`valid` | `feedback_fusion` | 数据 + 有效 | — |
| C6 | `feedback_fusion` | `pos_meas[31:0]`、`vel_meas[31:0]` | `pid_ctrl` | 数据 | 每 `en_ctrl_tick` 更新 |
| C7 | `feedback_fusion` | `elec_angle[15:0]` | `drive_gen` → `pwm3ph_deadtime` | 数据 | 换相/Park 变换用 |
| C8 | `feedback_fusion` | `aligned` | `pid_ctrl`（抑制）、顶层状态 | 电平 | `0` 时 PID 输出被抑制 |
| C9 | `feedback_fusion` | `fusion_err` | 顶层状态 → `reg_file` | 电平 | 只标记不纠错（不变量 F2） |
| C10 | `pid_ctrl` | `duty_a/b/c[15:0]` | `drive_gen` → `pwm3ph_deadtime` | 数据 | 三相模式 |
| C11 | `pid_ctrl` | `step_rate[31:0]` | `drive_gen` → `stepdir_gen` | 数据 | 步进模式 |
| C12 | `drive_gen` | `pwm_hi/lo_a/b/c` | 顶层 `o_m_pwm_hi/lo_*` | 电平 | 死区已插入 |
| C13 | `drive_gen` | `step_pul`、`step_dir` | 顶层 `o_m_step_pul/dir` | 电平 | 最小脉宽已保证 |
| C14 | `spi_master_angle` | `spi_timeout` | 顶层 → `o_fault`、`reg_file` | 电平 | 传感器无响应 |

### C.1 关键连接的设计约束

**C3（快照触发）是全设计时序最关键的一条单拍脉冲。** 它必须从 `spi_master_angle` 直连到 `abz_decoder` 的 `i_snap_req`，**不得经过任何额外的打拍或门控**。任何插入的延迟都会破坏 `pos_snap` 与 `angle_abs` 的时刻一致性，从而在融合偏移中引入与转速相关的抖动。

**C7（电角度反馈）使 `drive_gen` 不是纯前向模块。** 这形成了一条回路：`feedback_fusion` → `drive_gen` → `pwm3ph_deadtime` → 物理电机 → 编码器 → `abz_decoder` → `feedback_fusion`。这是闭环的物理回路，其稳定性由 `pid_ctrl` 的增益决定。**这也是为什么 PID 默认增益必须为 0**（边界 B8）：增益未整定时，这条回路可能自激。

**C10 与 C11 互斥但共用同一个 PID 本体。** `pid_ctrl` 同时输出 `duty_a/b/c` 与 `step_rate`，由 `drive_gen` 按 `DRIVE_MODE` 选择。这意味着：

- 步进模式下 `pid_ctrl` 的积分器仍以"电机位置误差"为输入，输出被解释为脉冲速率而非占空比。
- 两种模式的切换**不需要切换 PID 结构**，只需切换命令解释方式。这是双模式设计在架构上的收益。
- **注意**：切换模式时积分器状态不会自动清零。若运行中切换模式，需要显式复位积分器。**此项为待定细节，记入 risks.md。**

---

## D. 时钟域标注汇总

| 连接 | 源域 | 目标域 | 处理 |
|------|------|--------|------|
| 全部内部连接（B 与 C 节） | `clk_100m` | `clk_100m` | **同域，无需 CDC** |
| `i_abz_a/b/z` → `abz_decoder` | async | `clk_100m` | 2-FF 同步（+ A/B 数字滤波；Z 无深度滤波） |
| `i_spi_miso` → `spi_master_angle` | async | `clk_100m` | 2-FF 同步 + 采样窗口裕量 |
| `i_sw` → `debounce` | async | `clk_100m` | 2-FF 同步 + 10 ms 去抖 |
| `i_rst_n` → `clk_reset_gen` | async | `clk_100m` | 异步置位 / 同步释放 |
| （若启用 PS）AXI-Lite ⇄ `reg_file` | `ps_clk` | `clk_100m` | **未实现**，需握手/FIFO，见 `D5` 与 `clock_reset_cdc.md` §5 |

**结论**：当前架构中除异步输入同步外，**不存在跨时钟域数据通路**。这是本设计最重要的架构简化，直接消除了异步 FIFO、握手协议、跨域约束这一整类风险。
