`timescale 1ns / 1ps

module top_rs485_key_led(
    input         ref_clk,         // 外部100MHz时钟输入，接板上H16引脚
    input  [1:0]  key,             // 按键输入
    output [1:0]  led,             // LED输出
    input         rs485_uart_rxd,  // RS485接收线
    output        rs485_uart_txd,  // RS485发送线
    output        RS485_DE0        // RS485方向控制
);

// ====================== 内部信号定义 ======================
wire        sys_clk;      // PLL输出的50MHz系统工作时钟
wire        pll_lock;     // PLL锁定指示，高电平=时钟稳定
reg        sys_rst_n;    // 系统复位，低有效
reg  [15:0] power_on_count;
reg         pll_rst;      // PLL复位信号，高有效

// ====================== 1. PLL IP例化 ======================
PLL u_pll(
    .refclk   (ref_clk),    // 输入：外部100MHz参考时钟
    .clk0_out (sys_clk),    // 输出：50MHz系统时钟（走BUFG全局时钟网络）
    .lock     (pll_lock),   // 输出：锁定状态
    .reset    (pll_rst)     // 输入：PLL复位，高有效
);

// ====================== 2. PLL上电复位 ======================
// 上电后给PLL一个短复位脉冲，保证PLL正常启动
initial begin
    pll_rst = 1'b1;
    #2000;   // 2us复位脉冲
    pll_rst = 1'b0;
end

// ====================== 3. 系统复位逻辑 ======================
// PLL锁定后才开始上电计数，计数满后释放系统复位
always @(posedge sys_clk or negedge pll_lock) begin
    if(!pll_lock) begin
        power_on_count <= 16'd0;
        sys_rst_n      <= 1'b0;
    end else begin
        if(&power_on_count)
            sys_rst_n <= 1'b1;
        else
            power_on_count <= power_on_count + 1'b1;
    end
end

// ====================== 4. 原有功能模块例化 ======================
rs485_key_led #(
    .CLK_FREQ     (50_000_000),   // 关键：系统时钟改为50MHz，覆盖原模块默认值
    .UART_BPS     (115200),
    .DEBOUNCE_MS  (20)
) u_rs485_key_led(
    .sys_clk          (sys_clk),
    .key              (key),
    .led              (led),
    .rs485_uart_rxd   (rs485_uart_rxd),
    .rs485_uart_txd   (rs485_uart_txd),
    .RS485_DE0        (RS485_DE0)
);

endmodule
