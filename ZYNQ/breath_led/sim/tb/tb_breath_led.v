`timescale 1ns/1ns

module tb_breath_led();

//parameter define
parameter CLK_PERIOD  = 20;       //时钟周期 20ns 
parameter CNT_2US_MAX = 7'd2; 
parameter CNT_2MS_MAX = 10'd10; 
parameter CNT_2S_MAX  = 10'd10;

//reg define 
reg           sys_clk; 
reg           sys_rst_n;

//wire define 
wire          led; 

//信号初始化 
initial begin 
    sys_clk <= 1'b0;
    sys_rst_n <= 1'b0;
    #200
    sys_rst_n <= 1'b1;
end

//产生时钟，每隔20ns就将sys_clk取反一次，所以这里是一个50MHZ的一个方波信号
always #(CLK_PERIOD/2) sys_clk = ~sys_clk;

//例化待测设计 
breath_led #( 
    .CNT_2US_MAX      (CNT_2US_MAX), 
    .CNT_2MS_MAX      (CNT_2MS_MAX),
    .CNT_2S_MAX        (CNT_2S_MAX)
)

u_breath_led(
    .sys_clk          (sys_clk),
    .sys_rst_n        (sys_rst_n),
    .led              (led)
);

endmodule