# 架构交接包

工程：四轴电机闭环控制 FPGA 系统
器件：安路 Anlogic DR1M90GEG400（米联客 MLK-F3P-CZ02 DR1）
阶段：**架构设计完成，可进入 RTL 实现**

---

## 1. 本阶段产出

| 文件 | 内容 |
|------|------|
| `doc/arch/interface_contract.yaml` | 顶层 22 个端口 + 13 个子模块的完整接口契约（方向/位宽/时钟域/复位域/协议/语义），以及 7 项未决决策 |
| `doc/arch/clock_reset_cdc.md` | 单时钟域决策与理由、复位树、异步输入同步策略、四轴同步的时间基实现、CDC 验证证据清单（CDC-1~CDC-9） |
| `doc/arch/module_partition.md` | 14 个模块的层次、职责、状态所有权、10 条硬边界（B1~B10）、"可立即实现 vs 待输入"分组与建议实现顺序 |
| `doc/arch/connection_matrix.md` | 板级引脚预算（69 根 / 可用 72 根）、连接器分配提案、顶层内部连线、子模块间 14 条连接（C1~C14） |
| `rtl/top_skeleton.sv` | 顶层骨架：端口 + 参数 + 内部连线 + 子模块实例化，**不含业务逻辑** |
| `doc/arch/risks.md` | 16 条架构假设、7 项未解决硬件事实、8 项时序/功能风险、下游各阶段验证要求、11 项阻塞优先级 |
| `doc/arch/handoff_packet.md` | 本文件 |

---

## 2. 已冻结的契约（下游不得更改）

### 2.1 顶层端口

```
时钟复位   : i_clk (100MHz), i_rst_n
电机驱动   : o_m_pwm_hi_{a,b,c}[3:0], o_m_pwm_lo_{a,b,c}[3:0],
             o_m_step_pul[3:0], o_m_step_dir[3:0]
SPI 角度   : o_spi_sck[3:0], o_spi_mosi[3:0], i_spi_miso[3:0], o_spi_cs_n[3:0]
ABZ 编码器 : i_abz_a[3:0], i_abz_b[3:0], i_abz_z[3:0]
微动开关   : i_sw[3:0]
数字输出   : o_dout[3:0]
状态指示   : o_led[1:0]
```

**命名约定（必须沿用）**：输入前缀 `i_`，输出前缀 `o_`；四路信号组一律用"位-每-轴"总线 `[3:0]`，`bit[a]` 属于第 a 轴。

### 2.2 模块划分

```
top
├── clk_reset_gen          复位 + 全部 tick
├── sync_timebase          四轴共享时基（唯一载波来源）
├── 4 × debounce           微动开关去抖
├── digital_out_safe       安全数字输出（4 通道）
├── reg_file               命令/状态寄存器（可选，D5）
└── 4 × axis_ctrl
    ├── drive_gen → { pwm3ph_deadtime | stepdir_gen }
    ├── abz_decoder
    ├── spi_master_angle → angle_frame_decode
    ├── feedback_fusion
    └── pid_ctrl
```

### 2.3 十条硬边界（B1~B10）

摘要（完整表述见 `module_partition.md` §5）：

- **B1** 只有 `sync_timebase` 持有载波计数器
- **B2** 只有 `pwm3ph_deadtime` 产生上下管信号对
- **B3** 只有 `abz_decoder` 持有位置计数器
- **B4** 只有 `feedback_fusion` 持有 `pos_offset`
- **B5** 异步输入必须在进入的第一个模块内 2-FF 同步
- **B6** 除 `clk_reset_gen` 外不得直接引用 `i_rst_n`
- **B7** `pwm3ph_deadtime` 必须满足 `!(o_hi_x & o_lo_x)`
- **B8** `pid_ctrl` 增益默认全 0、限幅默认 0
- **B9** `digital_out_safe` 在 `por_done=0` 期间强制安全电平
- **B10** 只有 `angle_frame_decode` 允许含型号相关解析

### 2.4 三条功能不变量

- **F1** `o_pos_snap` 与 `o_pos_cnt` 在 `i_snap_req` 有效拍严格相等（融合数据一致性）
- **F2** 融合只做检测与标记，不静默改写 ABZ 计数
- **F3** `aligned = 0` 时 `pos_meas` 无效，PID 输出被抑制

---

## 3. 建议的下一步

### 3.1 立即可以做的（无任何阻塞）

按 `module_partition.md` §6.3 的分批顺序，**第一批 5 个模块完全不依赖任何缺失信息**：

| 顺序 | 模块 | 为什么无阻塞 |
|------|------|--------------|
| 1 | `clk_reset_gen` | 时钟 100 MHz 已确认，POR 与 tick 均为参数 |
| 2 | `sync_timebase` | 载波频率为参数，逻辑与型号无关 |
| 3 | `debounce` | 去抖时间为参数 |
| 4 | `digital_out_safe` | 极性/安全电平为参数 |
| 5 | `abz_decoder` | 单端 3.3V 已确认，四倍频已确认 |

第二批（`pwm3ph_deadtime`、`pid_ctrl`、`feedback_fusion`）接口稳定，仅参数待整定，也可同步推进。

### 3.2 需要补充输入才能做的

| 模块 | 需要的输入 | 对应的未决决策 |
|------|-----------|----------------|
| `stepdir_gen` | 步进驱动器最小脉宽 | D1 |
| `spi_master_angle` / `angle_frame_decode` | SPI 传感器型号 | D3 |
| `drive_gen` | 驱动器输入路数（3 或 6）、轴级模式分配 | D1, D4 |
| `reg_file`（或 + AXI-Lite） | 是否启用 PS | D5 |
| FOC 相关模块 | 是否需要电流环 | **D2（架构级分叉）** |

### 3.3 关于顶层骨架的说明

`rtl/top_skeleton.sv` **不含业务逻辑、不含子模块实现**，因此在子模块 RTL 生成前**无法通过编译**（会报 unknown module type）。这是骨架的正常状态，不是错误。子模块齐全后再做编译检查。

骨架中的命令面按**安全缺省值 tie-off**（全局停机、四轴禁止、命令清零），替换为 `reg_file` 驱动即可接入控制面。注释中已给出替换位置。

---

## 4. 进入约束阶段前的阻塞项

本板约束格式为 **`.adc`（安路 IO 约束）+ `.sdc`（时序约束）**，不是 Xilinx 的 `.xdc`。

约束生成需要三个前提：

1. **顶层模块存在**（`rtl/top_skeleton.sv` 已提供端口契约，但约束通常需要一个可综合的顶层，即 `rtl/top.v`）
2. **硬件事实齐备**（`doc/hw/config.json` 中 FEP/CEP 引脚映射已齐备）
3. **以下 P0 阻塞项解决**

| 优先级 | 阻塞项 | 解决者 |
|--------|--------|--------|
| **P0** | J3 (bank32) 电压确认 = **3.3V** | 用户（物理跳线确认） |
| **P0** | FEP 48 根引脚可用性核对 | 用户 + 底板原理图 |
| **P0** | 顶层端口最终签字确认 | 用户 |
| P1 | D1 驱动器输入路数 / D3 SPI 型号 / D4 轴级分配 | 用户 |
| P2 | D2 电流环 / D5 PS / D6 数字输出路数 / D7 外部复位 | 用户 |

**引脚预算关键提示**：当前方案把 **FEP 的 48 根全部占满，余量为 0**。若确认 D1（驱动器自带死区），可立即释放 12 根；若再确认 D3（SPI 共享 SCK+MOSI），再释放 6 根。**建议在约束阶段前先解决 D1 与 D3，可显著降低溢出风险。**

---

## 5. 需要用户决策的清单（按影响排序）

| 顺序 | 决策 | 影响 |
|------|------|------|
| 1 | **D2：是否需要相电流环（FOC）？** | **架构级分叉**。需要则新增电流采样与 Clarke/Park 模块；不需要则当前架构直接可用 |
| 2 | **D1：外部栅极驱动是 3 输入还是 6 输入？** | 影响 12 根引脚（FEP 余量 0 → 12） |
| 3 | **D3：SPI 传感器型号？4 路 SPI 是否共享 SCK/MOSI？** | 影响 SPI 模块正确性 + 6 根引脚 |
| 4 | **D4：4 轴的电机类型逐轴分配** | 影响 `AXIS_DRIVE_MODE` 取值（当前引脚已按最大需求预留，不返工） |
| 5 | D5：是否启用 PS(ARM) 控制面 | 决定是否需要总线接口与 CDC |
| 6 | D7：是否引出外部复位引脚 | 影响 CEP-J12 占用 1 根 |
| 7 | D6：数字输出每轴 1 路还是 2 路 | 影响 `o_dout` 宽度 4 或 8 |
| 8 | `PWM_DEADTIME_NS` 实际值 | **安全关键**，上板前必须确认 |

---

## 6. 验证证据清单（供后续阶段直接引用）

架构阶段已把验收标准（`doc/intake/summary.md` AC1~AC14）落到可观测形式：

| 证据类别 | 条目 | 所在文件 |
|----------|------|----------|
| CDC 验证 | CDC-1 ~ CDC-9 | `clock_reset_cdc.md` §6 |
| 同步验证 | 四轴相位差 = 0 拍；同时启停同拍生效 | `clock_reset_cdc.md` §4 |
| 死区验证 | 上下管互斥不变量 + 死区宽度扫描 | `module_partition.md` B7 + `interface_contract.yaml` invariants |
| 融合验证 | 快照一致性（F1）、只检测不纠错（F2）、未对齐抑制（F3） | `module_partition.md` §4.3~§4.4 |
| 安全验证 | 上电安全态、PID 默认零输出 | `clock_reset_cdc.md` 不变量 R2/R3 + B8/B9 |
| 引脚验证 | 69 根占用 / 72 根可用；零猜测引脚 | `connection_matrix.md` §A |

---

## 7. 已知的架构级技术债

见 `risks.md` §6（TD-1 ~ TD-6）。摘要：

- TD-1：速度估计为 M 法，低速分辨率不足
- TD-2：位置计数器无溢出扩展（32 bit 上限）
- TD-3：融合只检测不纠错，需人工 `align_req`
- TD-4：模式切换需外部受控序列（R-5）
- TD-5：`reg_file` 与 PS 通路未实现
- TD-6：FOC 通路完全未实现
