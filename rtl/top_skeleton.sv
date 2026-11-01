// =============================================================================
// 四轴电机闭环控制 FPGA 系统 —— 顶层骨架
// =============================================================================
// Project    : four_axis_motor_closed_loop
// Target     : 安路 Anlogic DR1M90GEG400 (米联客 MLK-F3P-CZ02 DR1)
// Toolchain  : Tang Dynasty  (物理约束 .adc / 时序约束 .sdc)
// Clock      : 单一时钟域 clk_100m  (PL_CLK / H16 / 100MHz / LVCMOS33)
// Language   : SystemVerilog
//
// -----------------------------------------------------------------------------
// 【本文件的性质】
// 这是**架构契约骨架**，不是可独立综合的完整设计：
//   - 端口清单、参数清单、内部连线、子模块边界均已冻结
//   - 子模块本身尚未实现，因此本文件在子模块 RTL 生成前
//     **无法通过编译/综合**（会报 unknown module type）
//   - 文件中**不含任何业务逻辑**（无 always 块、无状态机、无算术）
//
// 契约来源：doc/arch/interface_contract.yaml
// 模块划分：doc/arch/module_partition.md
// 连接关系：doc/arch/connection_matrix.md
// 时钟复位：doc/arch/clock_reset_cdc.md
// 风险与未决：doc/arch/risks.md
//
// -----------------------------------------------------------------------------
// 【边界约束（下游 RTL 不得违反，详见 module_partition.md §5）】
//   B1  只有 sync_timebase 持有载波计数器，任何轴不得自建载波
//   B2  只有 pwm3ph_deadtime 产生上下管信号对
//   B3  只有 abz_decoder 持有位置计数器
//   B4  只有 feedback_fusion 持有 pos_offset
//   B5  异步输入必须在进入的第一个模块内完成 2-FF 同步
//   B6  除 clk_reset_gen 外不得直接引用 i_rst_n，统一用 sys_rst_n
//   B7  pwm3ph_deadtime 必须满足 !(o_hi_x & o_lo_x)
//   B8  pid_ctrl 增益默认全 0、限幅默认 0
//   B9  digital_out_safe 在 por_done=0 期间必须强制安全电平
//   B10 只有 angle_frame_decode 允许含型号相关解析
// =============================================================================

`default_nettype none

module top #(
    // ------------------------------------------------------------- 全局时基
    parameter int unsigned CLK_FREQ_HZ      = 100_000_000,
    parameter int unsigned POR_CYCLES       = 1024,
    parameter int unsigned CTRL_TICK_HZ     = 1_000,
    parameter int unsigned PWM_CARRIER_HZ   = 20_000,
    parameter int unsigned PWM_DEADTIME_NS  = 1_000,
    parameter int unsigned DEBOUNCE_MS      = 10,

    // ----------------------------------------- SPI 角度传感器（[TBD] 逐型号复核）
    // !!! 以下 4 个参数在 SPI 传感器型号确定后必须重新核对 !!!  见 open_decision D3
    parameter int unsigned SPI_SCK_HZ       = 10_000_000,
    parameter int unsigned SPI_CPOL         = 0,
    parameter int unsigned SPI_CPHA         = 1,
    parameter int unsigned SPI_FRAME_BITS   = 16,
    parameter int unsigned SPI_ANGLE_BITS   = 14,
    parameter int unsigned CS_SETUP_NS      = 100,
    parameter int unsigned CS_HOLD_NS       = 100,
    parameter int unsigned FRAME_TIMEOUT_NS = 100_000,

    // ----------------------------------------------------------- ABZ 编码器
    parameter int unsigned ABZ_POS_WIDTH    = 32,
    parameter bit          ABZ_QUAD4        = 1'b1,
    parameter int unsigned ABZ_FILTER_DEPTH = 2,
    parameter int unsigned ABZ_CNT_PER_REV  = 4096,   // [TBD] 编码器线数 x 4

    // -------------------------------------------------- 每轴驱动模式选择
    // bit[a] : 0 = 三相 PWM 模式, 1 = STEP/DIR 模式
    // 默认四轴均为三相模式。实际取值待 open_decision D4 确认。
    parameter [3:0]        AXIS_DRIVE_MODE  = 4'b0000,
    parameter int unsigned MOTOR_POLE_PAIRS = 7,      // [TBD] 按实际电机
    parameter int unsigned STEP_PUL_MIN_NS  = 500,    // [TBD] 按步进驱动器

    // ------------------------------------------------------ 电气极性与安全态
    parameter bit          SW_ACTIVE_LOW    = 1'b1,
    parameter bit          DOUT_ACTIVE_LOW  = 1'b0,
    parameter bit          DOUT_SAFE_LEVEL  = 1'b0,

    // ------------------------------------------------ 闭环（默认全关，安全）
    // !!! CURRENT_LOOP_EN 为高危默认值，见 open_decision D2 !!!
    parameter bit          CURRENT_LOOP_EN  = 1'b0,
    // PID 默认增益与限幅全部为 0 —— 未整定的闭环不得产生任何驱动输出
    parameter int unsigned POS_KP           = 0,
    parameter int unsigned POS_KI           = 0,
    parameter int unsigned POS_KD           = 0,
    parameter int unsigned VEL_KP           = 0,
    parameter int unsigned VEL_KI           = 0,
    parameter int unsigned VEL_KD           = 0,
    parameter int unsigned PID_OUT_MAX      = 0,
    parameter int unsigned PID_OUT_MIN      = 0,

    // ------------------------------------------------------------ 融合校验
    parameter int unsigned FUSION_ERR_THRESH  = 8,
    parameter int unsigned FUSION_ERR_PERSIST = 10
)(
    // ---------------------------------------------------------- 时钟与复位
    input  logic        i_clk,          // 100MHz, PL_CLK, H16, bank33, LVCMOS33
    input  logic        i_rst_n,        // 低有效, 外部; 内部经 reset_sync; pin [TBD] D7

    // ---------------------------------------------- 电机驱动（位-每-轴总线）
    // 三相 PWM 模式使用 pwm_hi_* / pwm_lo_*；STEP/DIR 模式使用 step_*
    // 未被选中模式的输出必须保持"非激活安全电平"（默认低），不得悬空/三态
    output logic [3:0]  o_m_pwm_hi_a,   // bit[a] = 第 a 轴 A 相上管
    output logic [3:0]  o_m_pwm_hi_b,   // bit[a] = 第 a 轴 B 相上管
    output logic [3:0]  o_m_pwm_hi_c,   // bit[a] = 第 a 轴 C 相上管
    output logic [3:0]  o_m_pwm_lo_a,   // bit[a] = 第 a 轴 A 相下管 (D1: 是否引出待定)
    output logic [3:0]  o_m_pwm_lo_b,   // bit[a] = 第 a 轴 B 相下管
    output logic [3:0]  o_m_pwm_lo_c,   // bit[a] = 第 a 轴 C 相下管
    output logic [3:0]  o_m_step_pul,   // bit[a] = 第 a 轴步进脉冲
    output logic [3:0]  o_m_step_dir,   // bit[a] = 第 a 轴方向电平

    // ------------------------------------------------ SPI 角度传感器（4 路独立）
    output logic [3:0]  o_spi_sck,      // bit[a] = 第 a 轴 SCK
    output logic [3:0]  o_spi_mosi,     // bit[a] = 第 a 轴 MOSI
    input  logic [3:0]  i_spi_miso,     // bit[a] = 第 a 轴 MISO (异步, 内部 2-FF 同步)
    output logic [3:0]  o_spi_cs_n,     // bit[a] = 第 a 轴片选, 低有效

    // ------------------------------------------ ABZ 正交编码器（4 路, 单端 3.3V）
    input  logic [3:0]  i_abz_a,        // 异步输入, 内部 2-FF 同步 + 滤波
    input  logic [3:0]  i_abz_b,        // 异步输入, 内部 2-FF 同步 + 滤波
    input  logic [3:0]  i_abz_z,        // 异步输入, 内部仅 2-FF 同步(不做深度去抖)

    // ------------------------------------------------------ 微动开关（4 路）
    input  logic [3:0]  i_sw,           // 异步输入, 内部 2-FF 同步 + 去抖

    // ------------------------------------------------ 数字输出（使能/抱闸 4 路）
    output logic [3:0]  o_dout,         // 上电期强制安全态; 极性由参数决定; D6: 4 或 8 路

    // ------------------------------------------------------------ 状态指示
    output logic [1:0]  o_led            // [0]=无故障, [1]=四轴全部 aligned
                                         // 板载 LED3=J15 / LED4=M20 / bank33
);

    // =========================================================================
    // 内部连线声明
    // =========================================================================

    // ---- 时钟/复位生成 ----
    logic        sys_rst_n;         // 同步释放后的全局复位 (边界 B6)
    logic        por_done;          // 上电复位完成
    logic        en_ctrl_tick;      // 1 kHz 闭环节拍
    logic        en_pwm_tick;       // 载波推进节拍
    logic        en_deb_tick;       // 去抖采样节拍

    // ---- 四轴共享时基 (唯一载波来源, 边界 B1) ----
    logic        tb_run;            // 全局启停
    logic [15:0] tb_carrier_cnt;    // 载波计数, 四轴共用
    logic        tb_carrier_dir;    // 1=上升段 0=下降段
    logic        tb_carrier_wrap;   // 载波回绕
    logic        tb_carrier_zero;   // 载波过零
    logic [15:0] tb_phase;          // 相位基准广播

    // ---- 每轴驱动输出 (位-每-轴) ----
    logic [3:0]  ax_pwm_hi_a;
    logic [3:0]  ax_pwm_hi_b;
    logic [3:0]  ax_pwm_hi_c;
    logic [3:0]  ax_pwm_lo_a;
    logic [3:0]  ax_pwm_lo_b;
    logic [3:0]  ax_pwm_lo_c;
    logic [3:0]  ax_step_pul;
    logic [3:0]  ax_step_dir;

    // ---- 每轴命令面 (来源: reg_file / PS, 见 D5) ----
    logic [31:0] ax_pos_cmd      [0:3];
    logic [31:0] ax_vel_ff       [0:3];
    logic [3:0]  ax_cmd_enable;
    logic [3:0]  ax_align_req;

    // ---- 每轴观测面 ----
    logic [31:0] ax_pos_meas     [0:3];
    logic [31:0] ax_vel_meas     [0:3];
    logic [15:0] ax_angle_abs    [0:3];
    logic [3:0]  ax_angle_valid;
    logic [3:0]  ax_aligned;
    logic [3:0]  ax_spi_err;
    logic [3:0]  ax_fusion_err;
    logic [3:0]  ax_fault;
    logic [3:0]  ax_dout_req;

    // ---- 去抖后的开关输入 ----
    logic [3:0]  sw_stable;

    // =========================================================================
    // L1-1  时钟与复位生成
    // =========================================================================
    clk_reset_gen #(
        .CLK_FREQ_HZ    (CLK_FREQ_HZ),
        .CTRL_TICK_HZ   (CTRL_TICK_HZ),
        .POR_CYCLES     (POR_CYCLES)
    ) u_clk_reset_gen (
        .i_clk          (i_clk),
        .i_rst_n        (i_rst_n),
        .o_sys_rst_n    (sys_rst_n),
        .o_en_ctrl_tick (en_ctrl_tick),
        .o_en_pwm_tick  (en_pwm_tick),
        .o_en_deb_tick  (en_deb_tick),
        .o_por_done     (por_done)
    );

    // =========================================================================
    // L1-2  四轴共享时基 —— "同频同相 / 同时启停" 的唯一实现点
    //       载波计数器在此全局唯一产生，四轴只读引用 (边界 B1)
    // =========================================================================
    sync_timebase #(
        .CLK_FREQ_HZ    (CLK_FREQ_HZ),
        .PWM_CARRIER_HZ (PWM_CARRIER_HZ)
    ) u_sync_timebase (
        .i_clk          (i_clk),
        .i_rst_n        (sys_rst_n),
        .i_en_pwm_tick  (en_pwm_tick),
        .i_run          (tb_run),           // 由命令面驱动, 见下方 tie-off 说明
        .i_align_start  (1'b0),             // [TBD] 全局对齐启动源
        .o_carrier_cnt  (tb_carrier_cnt),
        .o_carrier_dir  (tb_carrier_dir),
        .o_carrier_wrap (tb_carrier_wrap),
        .o_carrier_zero (tb_carrier_zero),
        .o_tb_phase     (tb_phase)
    );

    // =========================================================================
    // L1-3  微动开关去抖 (4 通道)
    // =========================================================================
    genvar s;
    generate
        for (s = 0; s < 4; s = s + 1) begin : g_sw_debounce
            debounce #(
                .CLK_FREQ_HZ  (CLK_FREQ_HZ),
                .DEBOUNCE_MS  (DEBOUNCE_MS)
            ) u_debounce (
                .i_clk        (i_clk),
                .i_rst_n      (sys_rst_n),
                .i_en_tick    (en_deb_tick),
                .i_raw        (i_sw[s]),          // 异步, 模块内 2-FF 同步 (边界 B5)
                .i_active_low (SW_ACTIVE_LOW),
                .o_stable     (sw_stable[s]),
                .o_rise       (),
                .o_fall       ()
            );
        end
    endgenerate

    // =========================================================================
    // L1-4  每轴闭环控制器 (4 实例, 结构相同, 参数不同)
    // =========================================================================
    genvar a;
    generate
        for (a = 0; a < 4; a = a + 1) begin : g_axis

            axis_ctrl #(
                .AXIS_INDEX         (a),
                .DRIVE_MODE         (AXIS_DRIVE_MODE[a]),
                .MOTOR_POLE_PAIRS   (MOTOR_POLE_PAIRS),
                .PWM_CARRIER_HZ     (PWM_CARRIER_HZ),
                .PWM_DEADTIME_NS    (PWM_DEADTIME_NS),
                .STEP_PUL_MIN_NS    (STEP_PUL_MIN_NS),
                .SPI_SCK_HZ         (SPI_SCK_HZ),
                .SPI_CPOL           (SPI_CPOL),
                .SPI_CPHA           (SPI_CPHA),
                .SPI_FRAME_BITS     (SPI_FRAME_BITS),
                .SPI_ANGLE_BITS     (SPI_ANGLE_BITS),
                .CS_SETUP_NS        (CS_SETUP_NS),
                .CS_HOLD_NS         (CS_HOLD_NS),
                .FRAME_TIMEOUT_NS   (FRAME_TIMEOUT_NS),
                .ABZ_POS_WIDTH      (ABZ_POS_WIDTH),
                .ABZ_QUAD4          (ABZ_QUAD4),
                .ABZ_FILTER_DEPTH   (ABZ_FILTER_DEPTH),
                .ABZ_CNT_PER_REV    (ABZ_CNT_PER_REV),
                .CURRENT_LOOP_EN    (CURRENT_LOOP_EN),
                .POS_KP             (POS_KP),
                .POS_KI             (POS_KI),
                .POS_KD             (POS_KD),
                .VEL_KP             (VEL_KP),
                .VEL_KI             (VEL_KI),
                .VEL_KD             (VEL_KD),
                .PID_OUT_MAX        (PID_OUT_MAX),
                .PID_OUT_MIN        (PID_OUT_MIN),
                .FUSION_ERR_THRESH  (FUSION_ERR_THRESH),
                .FUSION_ERR_PERSIST (FUSION_ERR_PERSIST)
            ) u_axis_ctrl (
                // 时钟与节拍
                .i_clk          (i_clk),
                .i_rst_n        (sys_rst_n),
                .i_en_ctrl_tick (en_ctrl_tick),
                .i_en_deb_tick  (en_deb_tick),
                // 共享时基 (只读, 不得自建载波 —— 边界 B1)
                .i_run          (tb_run),
                .i_carrier_cnt  (tb_carrier_cnt),
                .i_carrier_dir  (tb_carrier_dir),
                // 命令面
                .i_axis_enable  (ax_cmd_enable[a]),
                .i_pos_cmd      (ax_pos_cmd[a]),
                .i_vel_cmd      (ax_vel_ff[a]),
                .i_align_req    (ax_align_req[a]),
                // 驱动输出 -> 顶层 4 位总线的第 a 位
                .o_pwm_hi_a     (ax_pwm_hi_a[a]),
                .o_pwm_hi_b     (ax_pwm_hi_b[a]),
                .o_pwm_hi_c     (ax_pwm_hi_c[a]),
                .o_pwm_lo_a     (ax_pwm_lo_a[a]),
                .o_pwm_lo_b     (ax_pwm_lo_b[a]),
                .o_pwm_lo_c     (ax_pwm_lo_c[a]),
                .o_step_pul     (ax_step_pul[a]),
                .o_step_dir     (ax_step_dir[a]),
                // SPI (每轴独立)
                .o_spi_sck      (o_spi_sck[a]),
                .o_spi_mosi     (o_spi_mosi[a]),
                .i_spi_miso     (i_spi_miso[a]),   // 异步, 模块内同步 (B5)
                .o_spi_cs_n     (o_spi_cs_n[a]),
                // ABZ (单端 3.3V, 异步, 模块内同步)
                .i_abz_a        (i_abz_a[a]),
                .i_abz_b        (i_abz_b[a]),
                .i_abz_z        (i_abz_z[a]),
                // 观测面
                .o_pos_meas     (ax_pos_meas[a]),
                .o_vel_meas     (ax_vel_meas[a]),
                .o_angle_abs    (ax_angle_abs[a]),
                .o_angle_valid  (ax_angle_valid[a]),
                .o_aligned      (ax_aligned[a]),
                .o_spi_err      (ax_spi_err[a]),
                .o_fusion_err   (ax_fusion_err[a]),
                .o_fault        (ax_fault[a]),
                .o_dout_req     (ax_dout_req[a])
            );
        end
    endgenerate

    // =========================================================================
    // L1-5  安全数字输出 (4 通道) —— 上电安全态的唯一保障点 (边界 B9)
    // =========================================================================
    digital_out_safe #(
        .DOUT_ACTIVE_LOW (DOUT_ACTIVE_LOW),
        .DOUT_SAFE_LEVEL (DOUT_SAFE_LEVEL)
    ) u_digital_out_safe (
        .i_clk       (i_clk),
        .i_rst_n     (sys_rst_n),
        .i_por_done  (por_done),
        .i_req       (ax_dout_req),
        .o_dout      (o_dout)
    );

    // =========================================================================
    // L1-6  命令/状态寄存器  —— 条件模块, 见 open_decision D5
    // =========================================================================
    // 当前架构默认【不启用 PS】, 命令面为 PL 内部同步寄存器接口。
    // 本骨架阶段 reg_file 尚未实例化, 命令面按下述安全缺省值 tie-off。
    //
    // 加入 reg_file (或 PS + AXI-Lite 通路) 时, 把下列 assign 替换为
    // 由 reg_file 驱动的连线, 并补齐 clock_reset_cdc.md §5 的 CDC 通路。
    //
    //   reg_file u_reg_file ( ... .o_pos_cmd(ax_pos_cmd), .o_axis_enable(ax_cmd_enable),
    //                             .o_align_req(ax_align_req), .o_run(tb_run),
    //                             .i_sw_stable(sw_stable), .i_pos_meas(ax_pos_meas), ... );
    //
    // 缺省安全态: 全部轴禁止、全部命令清零、全局停机、不请求对齐。
    assign tb_run          = 1'b0;                  // 全局停机, 无驱动输出
    assign ax_cmd_enable   = 4'b0000;               // 四轴闭环均禁止
    assign ax_align_req    = 4'b0000;
    assign ax_pos_cmd[0]   = 32'd0;
    assign ax_pos_cmd[1]   = 32'd0;
    assign ax_pos_cmd[2]   = 32'd0;
    assign ax_pos_cmd[3]   = 32'd0;
    assign ax_vel_ff[0]    = 32'd0;
    assign ax_vel_ff[1]    = 32'd0;
    assign ax_vel_ff[2]    = 32'd0;
    assign ax_vel_ff[3]    = 32'd0;

    // =========================================================================
    // 顶层输出汇总 (位-每-轴总线 -> 端口)
    // =========================================================================
    assign o_m_pwm_hi_a = ax_pwm_hi_a;
    assign o_m_pwm_hi_b = ax_pwm_hi_b;
    assign o_m_pwm_hi_c = ax_pwm_hi_c;
    assign o_m_pwm_lo_a = ax_pwm_lo_a;
    assign o_m_pwm_lo_b = ax_pwm_lo_b;
    assign o_m_pwm_lo_c = ax_pwm_lo_c;
    assign o_m_step_pul = ax_step_pul;
    assign o_m_step_dir = ax_step_dir;

    // =========================================================================
    // 状态指示 (板载 LED3=J15 / LED4=M20, bank33, 高有效)
    // =========================================================================
    assign o_led[0] = ~(|ax_fault);      // 任一轴故障则熄灭
    assign o_led[1] =  &ax_aligned;      // 四轴全部对齐才点亮

    // =========================================================================
    // 未使用观测信号的显式占位
    // 说明: 观测面在 reg_file 实例化后才有消费者。此处保留连线声明,
    //       不做任何逻辑处理, 避免综合工具产生 "unconnected" 告警歧义。
    // =========================================================================
    logic unused_obs;
    assign unused_obs = ^{ ax_pos_meas[0], ax_pos_meas[1], ax_pos_meas[2], ax_pos_meas[3],
                           ax_vel_meas[0], ax_vel_meas[1], ax_vel_meas[2], ax_vel_meas[3],
                           ax_angle_abs[0], ax_angle_abs[1], ax_angle_abs[2], ax_angle_abs[3],
                           ax_angle_valid, ax_spi_err, ax_fusion_err,
                           sw_stable, tb_carrier_wrap, tb_carrier_zero, tb_phase };

endmodule

`default_nettype wire
