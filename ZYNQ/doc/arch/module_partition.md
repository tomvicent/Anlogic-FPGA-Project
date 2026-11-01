# 模块划分与职责边界

工程：四轴电机闭环控制 FPGA 系统
顶层模块：`top`（`rtl/top_skeleton.sv`）
目标器件：安路 Anlogic DR1M90GEG400（米联客 MLK-F3P-CZ02 DR1）

---

## 1. 层次结构总览

```
top                                    (rtl/top_skeleton.sv, 仅骨架)
├── clk_reset_gen                      [L1]  复位 + 全部 tick 生成
├── sync_timebase                      [L1]  四轴共享时基 + 同步启停
├── g_sw[0..3].u_sw_debounce           [L1]  微动开关去抖 (debounce 实例 x4)
├── digital_out_safe                   [L1]  4 通道安全数字输出
├── reg_file                           [L1]  命令/状态寄存器 (可选, 见 D5)
└── g_axis[0..3].u_axis_ctrl           [L1]  轴控制器 x4
    ├── drive_gen                      [L2]  驱动模式选择
    │   ├── pwm3ph_deadtime            [L3]  三相中心对齐 PWM + 死区
    │   └── stepdir_gen                [L3]  STEP/DIR 脉冲发生器
    ├── abz_decoder                    [L2]  正交解码 + 位置计数
    ├── spi_master_angle               [L2]  SPI 主控
    │   └── angle_frame_decode         [L3]  型号相关帧解析
    ├── feedback_fusion                [L2]  ABZ + SPI 互补融合
    └── pid_ctrl                       [L2]  位置环 + 速度环级联
```

层级统计：L1 = 5 类（6 个实例组），L2 = 5，L3 = 3。合计 **14 个模块定义**，其中 `axis_ctrl` 子树实例化 4 次。

---

## 2. 模块表

| 模块 | 层 | 实例数 | 职责 | 时钟域 | 状态所有权 | 黑盒 |
|------|----|--------|------|--------|-----------|------|
| `clk_reset_gen` | L1 | 1 | 上电复位、复位同步、tick 分频 | `clk_100m` | POR 计数器、复位同步 FF、分频计数器 | 否 |
| `sync_timebase` | L1 | 1 | 全局载波计数器、全局 run/stop 广播 | `clk_100m` | 载波计数器（唯一） | 否 |
| `axis_ctrl` | L1 | 4 | 单轴闭环容器 | `clk_100m` | 无自身状态（纯容器） | 否 |
| `drive_gen` | L2 | 4 | 按模式在两条驱动分支间选择 | `clk_100m` | 无（组合选择） | 否 |
| `pwm3ph_deadtime` | L3 | 4 | 三相 PWM + 死区 | `clk_100m` | 死区移位寄存器、比较器 | 否 |
| `stepdir_gen` | L3 | 4 | 步进脉冲生成 | `clk_100m` | 速率累加器、脉冲计数 | 否 |
| `abz_decoder` | L2 | 4 | 正交解码、位置计数 | `clk_100m` | 2FF 同步、滤波器、位置计数器、Z 锁存 | 否 |
| `spi_master_angle` | L2 | 4 | SPI 事务状态机 | `clk_100m` | SCK 分频、位计数、移位寄存器、超时 | 否 |
| `angle_frame_decode` | L3 | 4 | 型号相关帧解析 | `clk_100m` | 无（纯组合+小寄存） | 否 |
| `feedback_fusion` | L2 | 4 | 双路反馈融合 | `clk_100m` | 偏移寄存器、速度估计、一致性计数器 | 否 |
| `pid_ctrl` | L2 | 4 | 双环 PID | `clk_100m` | 积分器、微分历史、限幅 | 否 |
| `debounce` | L1/L2 | 4（顶层开关）+ 可选 | 参数化去抖 | `clk_100m` | 计数器 + 稳定值 | 否 |
| `digital_out_safe` | L1 | 1 | 安全数字输出（4 通道） | `clk_100m` | 极性映射寄存器 | 否 |
| `reg_file` | L1 | 0 或 1 | 命令/状态寄存器 | `clk_100m` | 全部命令与状态寄存器 | 条件 |

**没有任何模块是真正的黑盒 IP。** 本设计不使用 PLL、不使用外部存储器控制器、不使用高速收发器、不使用厂商硬核。若最终启用 PS 控制面，`axi_lite_wrapper` 才作为黑盒引入（见 D5）。

---

## 3. 状态与资源所有权

明确"谁拥有什么状态"是避免 RTL 阶段出现多驱动或隐式共享的关键。本设计的状态所有权划分如下：

| 状态 | 所有者 | 独占性说明 |
|------|--------|-----------|
| 载波计数器 | `sync_timebase` | **全局唯一**。四轴只读。任何轴自建载波计数器都是违规 |
| 全局 run/stop | `sync_timebase` | 全局唯一，广播使用 |
| 死区移位寄存器 | `pwm3ph_deadtime` | 每轴独占 1 份 |
| 位置计数器 | `abz_decoder` | 每轴独占 1 份，32 bit |
| 位置快照 | `abz_decoder` → `feedback_fusion` | 由 `abz_decoder` 产生，`feedback_fusion` 只读 |
| 融合偏移 `pos_offset` | `feedback_fusion` | 每轴独占 1 份，是对齐的唯一产物 |
| 速度估计 | `feedback_fusion` | 每轴独占 1 份 |
| PID 积分器 | `pid_ctrl` | 每轴独占 1 份（位置环、速度环各一） |
| 去抖状态 | `debounce` | 每通道独占 1 份 |
| 数字输出极性映射 | `digital_out_safe` | 全局 1 份（4 通道共用参数） |
| 命令与状态寄存器 | `reg_file` | 全局 1 份（若存在） |

### 3.1 存储器与缓冲

| 资源类型 | 是否使用 | 理由 |
|----------|----------|------|
| 分布式 RAM | **不使用** | 无查表/系数表需求；PID 系数走参数或寄存器 |
| Block RAM | **不使用**（当前） | 无数据缓冲、无跨域 FIFO、无波形缓存需求 |
| FIFO | **不使用** | 单时钟域，无跨域缓冲；SPI 逐帧处理无需排队 |
| 乘法器 / DSP | **使用** | PID 的 Kp/Ki/Kd 乘法。DR1M90GEG400 有 240 个 DSP，四轴双环共 8 个 PID 通道，资源充裕 |

**这是本架构最值得注意的资源特征：整个设计几乎不用存储器。** 原因是它是一个"控制密集型"而非"数据流密集型"设计——没有图像行缓存、没有帧缓冲、没有采样深度缓冲。

若 `D2` 确认需要 FOC，将引入电流采样缓冲（每轴 2~3 个 ADC 通道的低深度 FIFO 或双口 RAM），届时需重新评估此项。

### 3.2 资源预估（粗粒度，仅供后续综合参照）

| 资源 | 预估占用 | 芯片可用 | 裕量 |
|------|----------|----------|------|
| LUT | 约 6k ~ 15k | 94,464 | 充裕 |
| FF | 约 4k ~ 8k | 94,464（同量级） | 充裕 |
| DSP | 约 16 ~ 40 | 240 | 充裕 |
| BUFG | 1（单时钟） | 8 PLL 相关资源 | 充裕 |
| RAM | ~0 | — | — |

预估区间跨度大是因为 `pid_ctrl` 的位宽/流水级数、以及是否启用 FOC 尚未确定。即便取上限，94K LUT 的芯片也远超需求——**本设计的瓶颈在引脚数（详见 risks.md），不在逻辑资源**。

---

## 4. 数据通路

### 4.1 前向通路（控制侧）

```
命令 (pos_cmd) 
   |
   v
 pid_ctrl[位置环] --vel_cmd--> pid_ctrl[速度环] --+--> duty_a/b/c ──> drive_gen ──> pwm3ph_deadtime ──> o_m_pwm_hi/lo_*
                                                  |
                                                  +--> step_rate ────> drive_gen ──> stepdir_gen ─────> o_m_step_pul/dir
```

关键设计点：

- **`pid_ctrl` 输出两种形式的命令**：三相模式的占空比（`duty_a/b/c`）与步进模式的速率（`step_rate`）。`drive_gen` 按 `DRIVE_MODE` 选择其一，未被选中的分支输入被忽略、输出被强制到安全电平。
- **步进模式与三相模式共用同一个 PID 结构**。差异只体现在命令解释方式与输出生成方式上，闭环算法本体不变。这是"双模式可配置"在架构上的实现方式——**不是两套闭环，是一套闭环 + 两个执行器**。
- **`o_elec_angle` 从 `feedback_fusion` 反馈给 `drive_gen`**：三相模式需要电角度来做换相或 Park 变换。这条反馈路径使 `drive_gen` 不是纯前向的。

### 4.2 反馈通路

```
                    i_abz_a/b/z
                         |
                         v
                 [2FF 同步 + 滤波]
                         |
                         v
                  abz_decoder ──pos_cnt──> feedback_fusion ──pos_meas──> pid_ctrl
                         |                       ^                           ^
                    (snap_req)                   |                           |
                         |                  angle_abs                        |
                         v                       |                           |
                    pos_snap ────────────────>  |                           |
                                                 |                           |
        i_spi_miso ──> spi_master_angle ──rx_data──> angle_frame_decode ─────┘
                             |
                        frame_done ──> 同时触发 abz_decoder 快照
```

### 4.3 快照一致性机制（关键设计点）

融合的前提是"SPI 绝对角"与"ABZ 计数"必须描述**同一个时刻**的转子位置。若二者相差几个时钟周期，融合出的偏移就会有抖动。

实现方式：

1. `spi_master_angle` 在帧接收完成的同一拍产生 `o_frame_done`。
2. 该脉冲同时送 `abz_decoder` 的 `i_snap_req`，`abz_decoder` 在**同一拍**把 `o_pos_cnt` 复制到 `o_pos_snap`。
3. `feedback_fusion` 使用 `(pos_snap, angle_abs)` 这一对**原子快照**计算偏移。

```systemverilog
// abz_decoder 中的快照逻辑（契约示意，非最终实现）
always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n)      o_pos_snap <= '0;
    else if (i_snap_req) o_pos_snap <= o_pos_cnt;   // 同拍捕获
end
```

**不变量 F1**：`o_pos_snap` 与 `o_pos_cnt` 在 `i_snap_req` 有效拍严格相等。此条列入 CDC 验证证据清单（CDC-8）。

### 4.4 融合策略（`feedback_fusion` 内部）

| 阶段 | 行为 |
|------|------|
| 未对齐 (`aligned = 0`) | 等待第一个有效的 `angle_valid`。捕获 `(pos_snap, angle_abs)`，计算 `pos_offset`，置 `aligned = 1`。此期间 PID 被抑制 |
| 已对齐 (§运行) | `pos_meas = pos_cnt - pos_offset`。以 ABZ 为高分辨率位置源，SPI 绝对角**不参与位置计算**，只做校验 |
| 一致性校验 | 每个控制 tick 计算 `pos_cnt mod cnt_per_rev` 与 `angle_abs` 的等效差值。若偏差 > `FUSION_ERR_THRESH` 且持续 `FUSION_ERR_PERSIST` 个 tick，置 `o_fusion_err` |
| 重新对齐 | 收到 `i_align_req` 时回到未对齐状态重新建立偏移（用于上电后或检测到故障后） |

**关键设计决策：SPI 角不参与实时位置计算。**

理由：SPI 读取有帧传输延迟（16 bit @ 10 MHz ≈ 1.6 µs，加 CS 建立/保持与帧间隔，实际更新率远低于 ABZ 计数更新率）。若把 SPI 角直接用于位置反馈，闭环带宽会被 SPI 更新率限制。因此架构上明确划分：

- **ABZ = 实时位置源**（高分辨率、低延迟）
- **SPI 绝对角 = 绝对基准 + 完整性校验**（低更新率、无累积误差）

这正是"互补融合"的工程含义，也直接满足用户表述的"ABZ 提供高分辨率增量，SPI 提供绝对位置"。

**不变量 F2**：`o_fusion_err` 只做检测与标记，**不静默改写 ABZ 计数**。若需要纠错（如脉冲丢失恢复），必须由上层显式发起 `align_req`，使纠错动作可观测。

**不变量 F3**：`aligned = 0` 时 `o_pos_meas` 无效，`pid_ctrl` 的 `i_aligned` 为 0 且输出被强制为安全值。

### 4.5 速度估计

速度由 `feedback_fusion` 在每个 `en_ctrl_tick`（1 kHz）对 `pos_cnt` 做差分得到。

| 特性 | 取值 | 说明 |
|------|------|------|
| 估计方法 | 固定窗口差分（M 法） | 简单、无额外硬件 |
| 更新率 | 1 kHz | 与闭环控制周期一致 |
| 分辨率 | `[TBD]` | 低速时 1 kHz 差分量化误差显著 |
| 符号 | 有符号 | 正转/反转 |

**已知局限**：M 法在低速时速度估计分辨率差（1 kHz 周期内可能只计 0~1 个脉冲）。若应用要求低速高精度速度环，需改为 M/T 法或加长/自适应测量窗口。**此项为风险，已记入 risks.md**。当前默认实现为 M 法。

---

## 5. 边界与禁止事项（下游 RTL 必须遵守）

这些是架构阶段冻结的硬边界，`fpga-rtl-build` 阶段不得违反：

| # | 边界 |
|---|------|
| B1 | 只有 `sync_timebase` 可以持有载波计数器。**任何 `axis_ctrl` 子树不得自建载波** |
| B2 | 只有 `pwm3ph_deadtime` 可以产生上下管信号对。死区逻辑不得散落在其他模块 |
| B3 | 只有 `abz_decoder` 持有位置计数器。`feedback_fusion` 通过 `pos_cnt`/`pos_snap` 只读访问 |
| B4 | 只有 `feedback_fusion` 持有 `pos_offset`。对齐逻辑不得复制到 `abz_decoder` 或 `pid_ctrl` |
| B5 | 异步输入（`i_abz_*`、`i_spi_miso`、`i_sw`）必须在**进入的第一个模块**内完成 2-FF 同步。不得把未同步信号跨模块传递 |
| B6 | 除 `clk_reset_gen` 外，任何模块不得直接引用 `i_rst_n`；统一使用 `o_sys_rst_n` |
| B7 | `pwm3ph_deadtime` 的输出必须满足 `!(o_hi_x & o_lo_x)`。此不变量优先于任何占空比精度要求 |
| B8 | `pid_ctrl` 的增益默认全 0、限幅默认 0。不得为了"让它能转"而预置非零默认值 |
| B9 | `digital_out_safe` 在 `por_done = 0` 期间必须强制安全电平。不得由上层逻辑旁路 |
| B10 | `angle_frame_decode` 是**唯一**允许包含型号相关解析的模块。`spi_master_angle` 必须保持型号无关 |

---

## 6. 可独立实现 vs 依赖待定信息

架构阶段将模块按"是否依赖未确认硬件信息"分为两组。这是**下游 RTL 阶段可以立即推进的范围**。

### 6.1 不依赖任何待定信息，可立即实现

| 模块 | 依赖状态 |
|------|----------|
| `clk_reset_gen` | 不依赖（时钟 100 MHz 已确认） |
| `sync_timebase` | 不依赖（载波频率为参数） |
| `debounce` | 不依赖（去抖时间为参数） |
| `digital_out_safe` | 不依赖（极性/安全电平为参数） |
| `pwm3ph_deadtime` | 不依赖（死区为参数；上板前需按器件确认参数值，但接口与逻辑结构不受影响） |
| `abz_decoder` | 不依赖（单端 3.3V 已确认；四倍频已确认） |
| `feedback_fusion` | 依赖 `ANGLE_BITS`、`MOTOR_POLE_PAIRS`（参数，可用默认值实现） |
| `pid_ctrl` | 不依赖结构，仅增益为参数 |

### 6.2 依赖待定信息，需等待输入

| 模块 | 阻塞项 | 阻塞原因 |
|------|--------|----------|
| `angle_frame_decode` | `D3`（SPI 传感器型号） | 帧格式/命令字/角度位宽逐型号定制 |
| `spi_master_angle` | `D3` | 部分是参数（帧长/模式/SCK），但**推荐在型号确定后实现**以确保时序正确 |
| `stepdir_gen` | `D1`（驱动器最小脉宽） | 结构不依赖，但其输出正确性依赖最小脉宽参数 |
| `reg_file` | `D5`（是否启用 PS） | 若启用 PS，需要 AXI-Lite 通路与 CDC |
| FOC 相关（尚未定义） | `D2` | 若需要电流环，需新增 `adc_if`、`clarke_park` 等模块 |
| `drive_gen` | `D1` / `D4` | 结构可先实现（模式选择是 mux），但 `AXIS_DRIVE_MODE` 取值未定 |

### 6.3 建议的实现顺序

```
第一批（完全无阻塞，先做公共基础设施）:
    1. clk_reset_gen
    2. sync_timebase
    3. debounce
    4. digital_out_safe
    5. abz_decoder

第二批（参数化，接口稳定）:
    6. pwm3ph_deadtime
    7. pid_ctrl
    8. feedback_fusion

第三批（等 D1/D3/D4 确认后）:
    9.  stepdir_gen
    10. spi_master_angle
    11. angle_frame_decode
    12. drive_gen
    13. axis_ctrl（容器，最后组装）

第四批（等 D5 确认后）:
    14. reg_file（或加 axi_lite_wrapper）
```

这个顺序的价值：**第一批 5 个模块完全不依赖任何缺失信息**，可以立刻开始 RTL，同时给用户时间补齐 D1/D2/D3。
