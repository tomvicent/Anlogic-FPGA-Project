`timescale 1ns / 1ps

module key_trig #(
    parameter integer CLK_FREQ = 50_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input clk , //外部 50M 时钟
    input rst_n , //外部复位信号，低有效
    input [1:0] key , //外部按键输入
    output reg key_data_valid, //按键数据有效标志
    output [1:0] key_data //按键数据
 );

//reg define
reg [1:0] key_data_d0;
reg [1:0] key_data_d1;

//*****************************************************
//** main code
//*****************************************************

//对 key_data 信号打两拍用于判断按键是否发生改变
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        key_data_d0 <= 2'b11;
        key_data_d1 <= 2'b11;
    end
    else begin
        key_data_d0 <= key_data;
        key_data_d1 <= key_data_d0;
    end
end

//当检测到按键数据发生改变时，key_data_valid 拉高
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        key_data_valid <= 1'b0;
    end
    else if (key_data_d1 != key_data_d0) begin
        key_data_valid <= 1'b1;
    end
    else begin
        key_data_valid <= 1'b0;
    end
end

//按键 0 消抖模块
key_debounce #(
    .CLK_FREQ    (CLK_FREQ),
    .DEBOUNCE_MS (DEBOUNCE_MS)
) u_key_debounce_0(
    .clk (clk ),
    .rst_n (rst_n ),
    .key_in (key[0] ),
    .key_value (key_data[0]),
    .key_flag  ()
);

//按键 1 消抖模块
key_debounce #(
    .CLK_FREQ    (CLK_FREQ),
    .DEBOUNCE_MS (DEBOUNCE_MS)
) u_key_debounce_1(
    .clk (clk ),
    .rst_n (rst_n ),
    .key_in (key[1] ),
    .key_value (key_data[1]),
    .key_flag  ()
);
endmodule
