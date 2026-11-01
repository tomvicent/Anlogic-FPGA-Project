//==============================================================================
// clk_reset_gen.v
// 时钟/复位生成器 -- 四轴电机闭环控制 FPGA 系统
//
// 功能概述：
//   1. 复位同步链：异步置位、同步释放，保证全设计复位释放时刻一致
//   2. 上电复位 (POR)：即使 i_rst_n 未翻转，也保证一次确定的上电复位
//   3. 时钟使能 tick 生成：控制周期、PWM 载波、去抖采样
//
// 架构边界 B6：本模块是全设计唯一允许引用 i_rst_n 的模块。
//              下游所有寄存器统一使用 o_sys_rst_n。
//==============================================================================

module clk_reset_gen #(
    parameter CLK_FREQ_HZ  = 100000000,  // 输入时钟频率 (Hz)
    parameter CTRL_TICK_HZ = 1000,       // 闭环节拍频率 (Hz)
    parameter POR_CYCLES   = 1024        // 上电复位保持周期数
)(
    input  wire i_clk,          // 100MHz 主时钟 (PL_CLK / H16 / bank33 / LVCMOS33)
    input  wire i_rst_n,        // 外部低有效复位，异步；可为常 1（不使用）
    output wire o_sys_rst_n,    // 异步置位/同步释放后的全局复位，低有效
    output wire o_en_ctrl_tick, // 控制周期单拍使能，1 kHz
    output wire o_en_pwm_tick,  // PWM 载波推进使能（恒 1，载波自由运行）
    output wire o_en_deb_tick,  // 去抖计数器采样使能，1 ms 周期
    output wire o_por_done      // 上电复位过程完成，高有效
);

    // =========================================================================
    // clog2 函数（Verilog-2001 兼容的 ceil(log2(n)) 计算）
    // 用于根据分频比推导计数器位宽，保证计数器不发生回绕歧义。
    // =========================================================================
    function integer clog2_f;
        input integer value;
        integer i;
        begin
            clog2_f = 0;
            for (i = value - 1; i > 0; i = i >> 1)
                clog2_f = clog2_f + 1;
        end
    endfunction

    // =========================================================================
    // 参数推导
    // =========================================================================

    // 控制周期分频比：CLK_FREQ_HZ / CTRL_TICK_HZ
    // 默认 100000000 / 1000 = 100000
    localparam CTRL_DIV = CLK_FREQ_HZ / CTRL_TICK_HZ;

    // 去抖采样分频比：CLK_FREQ_HZ / 1000（1 ms 周期）
    // 默认 100000000 / 1000 = 100000
    localparam DEB_DIV  = CLK_FREQ_HZ / 1000;

    // 计数器位宽
    // CTRL_CNT_W: ceil(log2(CTRL_DIV))，默认 17 位（2^17=131072 > 100000）
    // DEB_CNT_W : ceil(log2(DEB_DIV)) ，默认 17 位
    // POR_CNT_W : ceil(log2(POR_CYCLES+1))，默认 11 位（2^11=2048 > 1025）
    localparam CTRL_CNT_W = (CTRL_DIV <= 1) ? 1 : clog2_f(CTRL_DIV);
    localparam DEB_CNT_W  = (DEB_DIV  <= 1) ? 1 : clog2_f(DEB_DIV);
    localparam POR_CNT_W  = (POR_CYCLES <= 0) ? 1 : clog2_f(POR_CYCLES + 1);

    // =========================================================================
    // 1) 复位同步链（异步置位 / 同步释放）
    //
    // 原理：
    //   当 i_rst_n 为低时，两级 FF 通过异步置位端立即清零，复位不依赖时钟。
    //   当 i_rst_n 恢复为高时，数据端输入 1'b1 经两级 FF 逐级传递：
    //     第 1 拍：rst_sync_ff1 <= 1'b1
    //     第 2 拍：rst_sync_ff2 <= rst_sync_ff1 = 1'b1
    //   rst_sync_ff2 从 0 跳变到 1 的时刻即为"同步释放完成"。
    //
    // 目的：
    //   避免复位释放时刻在不同 FF 之间产生不一致。如果直接用 i_rst_n
    //   作为异步复位，不同 FF 的异步复位释放可能跨越时钟沿，导致部分
    //   FF 在同一周期退出复位、部分在下一周期退出。经 2 级同步后，
    //   rst_sync_ff2 的跳变严格对齐时钟沿，所有下游 FF 同拍释放。
    // =========================================================================
    reg rst_sync_ff1;
    reg rst_sync_ff2;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            rst_sync_ff1 <= 1'b0;
            rst_sync_ff2 <= 1'b0;
        end else begin
            rst_sync_ff1 <= 1'b1;
            rst_sync_ff2 <= rst_sync_ff1;
        end
    end

    // =========================================================================
    // 2) 上电复位 (POR) 计数器
    //
    // 兜底机制：
    //   即使 i_rst_n 一直为高（未接/未翻转），FPGA 配置完成后所有寄存器
    //   初始化为 0。por_cnt 从 0 开始递增，por_done_raw 为 0，从而产生
    //   持续 POR_CYCLES 个周期的确定复位过程。
    //
    // Sticky 行为：
    //   por_done_raw 一旦置 1 便永不回退（除非 i_rst_n 重新拉低触发异步复位）。
    //   这保证上电安全态释放是一次性事件，不会因后续逻辑误操作而重新进入
    //   "POR 未完成"状态。
    //
    // 计数过程：
    //   por_cnt 从 0 递增到 POR_CYCLES-1 时，por_done_raw 置 1，
    //   计数器停止递增。共计 POR_CYCLES 个有效计数周期。
    // =========================================================================
    reg [POR_CNT_W-1:0] por_cnt;
    reg                  por_done_raw;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            por_cnt      <= {POR_CNT_W{1'b0}};
            por_done_raw <= 1'b0;
        end else if (!por_done_raw) begin
            if (por_cnt >= POR_CYCLES - 1) begin
                por_done_raw <= 1'b1;
                // por_cnt 停止计数，保持最终值
            end else begin
                por_cnt <= por_cnt + 1'b1;
            end
        end
        // por_done_raw = 1 后，整个 else if 分支不再进入，状态锁定
    end

    // =========================================================================
    // 3) 合并复位输出寄存器
    //
    // 两条复位释放路径在此合并为 o_sys_rst_n：
    //
    //   路径 A — 外部复位同步释放：
    //     i_rst_n 恢复高 → 2 级 FF 同步 → rst_sync_ff2 = 1
    //
    //   路径 B — 上电 POR 计数完成：
    //     por_cnt 计满 POR_CYCLES → por_done_raw = 1
    //
    // 合并逻辑：
    //   sys_rst_n_r <= rst_sync_ff2 & por_done_raw
    //   两者必须同时为 1，sys_rst_n_r 才释放（变为高）。
    //   任一为 0，sys_rst_n_r 保持低（复位中）。
    //
    // 输出寄存器本身使用 i_rst_n 作为异步置位端：
    //   i_rst_n 拉低 → sys_rst_n_r 立即清零（异步，不依赖时钟）
    //   i_rst_n 为高 → 在时钟沿采样 AND 结果，同步释放
    //
    // o_por_done 与 o_sys_rst_n 取同一信号：
    //   架构不变量要求"o_sys_rst_n 为低期间 o_por_done 必须为 0"。
    //   两者在同一时钟沿释放，满足"复位释放是全设计统一的单一时刻"。
    // =========================================================================
    reg sys_rst_n_r;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            sys_rst_n_r <= 1'b0;
        end else begin
            sys_rst_n_r <= rst_sync_ff2 & por_done_raw;
        end
    end

    assign o_sys_rst_n = sys_rst_n_r;
    assign o_por_done  = sys_rst_n_r;

    // =========================================================================
    // 4) 控制周期 tick 生成（o_en_ctrl_tick）
    //
    // 分频比 = CLK_FREQ_HZ / CTRL_TICK_HZ
    // 默认 100MHz / 1kHz = 100000，即每 100000 个时钟产生 1 拍脉冲。
    //
    // 计数器 ctrl_cnt 从 0 递增到 CTRL_DIV-1 时回绕到 0，
    // 同时在回绕拍产生 en_ctrl_tick_r = 1（单周期脉冲）。
    // 其余周期 en_ctrl_tick_r = 0。
    //
    // 使用 sys_rst_n_r 作为异步复位，保证与其他输出统一释放。
    // =========================================================================
    reg [CTRL_CNT_W-1:0] ctrl_cnt;
    reg                   en_ctrl_tick_r;

    always @(posedge i_clk or negedge sys_rst_n_r) begin
        if (!sys_rst_n_r) begin
            ctrl_cnt       <= {CTRL_CNT_W{1'b0}};
            en_ctrl_tick_r <= 1'b0;
        end else begin
            if (ctrl_cnt >= CTRL_DIV - 1) begin
                ctrl_cnt       <= {CTRL_CNT_W{1'b0}};
                en_ctrl_tick_r <= 1'b1;
            end else begin
                ctrl_cnt       <= ctrl_cnt + 1'b1;
                en_ctrl_tick_r <= 1'b0;
            end
        end
    end

    assign o_en_ctrl_tick = en_ctrl_tick_r;

    // =========================================================================
    // 5) 去抖采样 tick 生成（o_en_deb_tick）
    //
    // 节拍周期为 1 ms（分频比 = CLK_FREQ_HZ / 1000）。
    // 默认 100MHz 下分频比 = 100000，与控制周期 tick 相同。
    //
    // 约定：o_en_deb_tick 节拍周期为 1 ms，去抖模块用 DEBOUNCE_MS 个
    // tick 计数实现去抖。例如 DEBOUNCE_MS = 10 表示连续 10 个 tick
    // （即 10 ms）电平一致才更新去抖输出。
    //
    // 虽然默认参数下 o_en_deb_tick 与 o_en_ctrl_tick 频率相同，
    // 但两者使用独立计数器，解耦控制环与去抖的参数调整空间。
    // =========================================================================
    reg [DEB_CNT_W-1:0] deb_cnt;
    reg                  en_deb_tick_r;

    always @(posedge i_clk or negedge sys_rst_n_r) begin
        if (!sys_rst_n_r) begin
            deb_cnt       <= {DEB_CNT_W{1'b0}};
            en_deb_tick_r <= 1'b0;
        end else begin
            if (deb_cnt >= DEB_DIV - 1) begin
                deb_cnt       <= {DEB_CNT_W{1'b0}};
                en_deb_tick_r <= 1'b1;
            end else begin
                deb_cnt       <= deb_cnt + 1'b1;
                en_deb_tick_r <= 1'b0;
            end
        end
    end

    assign o_en_deb_tick = en_deb_tick_r;

    // =========================================================================
    // 6) PWM 载波推进使能（o_en_pwm_tick）
    //
    // 恒为 1'b1：每个时钟都推进载波计数器，载波自由运行。
    //
    // 载波频率由 sync_timebase 模块按 PWM_CARRIER_HZ 参数自行分频，
    // 本模块不感知载波频率。此处恒 1 表示让载波以最高精度自由运行。
    // 若将来需要载波降速（如低功耗模式），可在此处插入分频逻辑
    // 而不改变本模块的对外接口。
    // =========================================================================
    assign o_en_pwm_tick = 1'b1;

endmodule
