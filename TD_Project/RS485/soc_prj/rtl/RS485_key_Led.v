`timescale 1ns / 1ps

module rs485_key_led(
    input        sys_clk,         //外部 50M 时钟

    input  [1:0] key,             //按键
    output [1:0] led,             //LED 灯

    //uart 接口
    input        rs485_uart_rxd,  //rs485 串口接收端口
    output       rs485_uart_txd,  //rs485 串口发送端口
    output       RS485_DE0
);

//parameter define
parameter CLK_FREQ = 50000000;    //定义系统时钟频率，这个的输入时钟是100MHZ
parameter UART_BPS = 115200;      //定义串口波特率
parameter DEBOUNCE_MS = 20;       //硬件默认消抖20ms，TB可缩短仿真时间

reg [15:0] power_on_count = 16'd0;
reg sys_rst_n = 1'b0;

always @(posedge sys_clk) begin
    if (!sys_rst_n) begin
        if (&power_on_count)
            sys_rst_n <= 1'b1;
        else
            power_on_count <= power_on_count + 1'b1;
    end
end

//wire define
wire       uart_tx_en;            //UART 发送使能
wire       uart_rx_done;          //UART 接收完毕信号
wire [7:0] uart_tx_data;          //UART 发送数据
wire [7:0] uart_rx_data;          //UART 接收数据
wire [1:0] key_data;              //按键数据

//*****************************************************
//** main code
//*****************************************************

//将 2 位按键数据编码为 8 位的串口数据
assign uart_tx_data = {6'b0, key_data};

//串口接收模块
uart_rx #(
    .CLK_FREQ (CLK_FREQ),         //设置系统时钟频率
    .UART_BPS (UART_BPS)          //设置串口接收波特率
) u_uart_rx(
    .clk          (sys_clk),
    .rst_n        (sys_rst_n && !RS485_DE0),
    .uart_rxd     (rs485_uart_rxd),
    .uart_rx_done (uart_rx_done),
    .uart_rx_data (uart_rx_data)
);

//LED 控制模块
led_ctrl u_led_ctrl(
    .clk      (sys_clk),
    .rst_n    (sys_rst_n),
    .led_en   (uart_rx_done),     //LED 控制使能
    .led_data (uart_rx_data[1:0]),//LED 控制数据
    .led      (led)
);

//按键触发模块
key_trig #(
    .CLK_FREQ    (CLK_FREQ),
    .DEBOUNCE_MS (DEBOUNCE_MS)
) u_key_trig(
    .clk            (sys_clk),
    .rst_n          (sys_rst_n),
    .key            (key),
    .key_data_valid (uart_tx_en), //按键有效通知信号
    .key_data       (key_data)    //按键数据
);

//串口发送模块
uart_tx #(
    .CLK_FREQ (CLK_FREQ),         //设置系统时钟频率
    .UART_BPS (UART_BPS),         //设置串口发送波特率
    .TX_SETUP_CYCLES ((CLK_FREQ + UART_BPS / 2) / UART_BPS)
) u_uart_tx(
    .clk          (sys_clk),
    .rst_n        (sys_rst_n),
    .uart_tx_en   (uart_tx_en),
    .uart_tx_data (uart_tx_data),
    .uart_txd     (rs485_uart_txd),
    .uart_tx_busy (RS485_DE0)
);

endmodule
