`timescale 1ns / 1ps

module led_ctrl(
    input clk , //外部 50M 时钟
    input rst_n , //外部复位信号，低有效

    input led_en , //LED 控制使能
    input [1:0] led_data, //LED 控制数据

    output reg [1:0] led //LED 灯
);

//*****************************************************
//** main code
//*****************************************************
//控制 LED 灯的变化
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        led <= 2'b00;
    else if(led_en) //在 led_en 使能时，改变 LED 灯的状态
        led <= ~led_data; //按键按下时为低电平，而 LED 高电平时点亮
    else
        led <= led; //在 led_en 不使能时，保持 LED 灯的状态不变
end
endmodule
