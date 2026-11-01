module breath_led (
input       sys_clk ,      //系统时钟 50MHz 
input       sys_rst_n ,    //系统复位，低电平有效        
output reg  led            //LED灯 
);

//parameter define  
parameter CNT_2US_MAX = 7'd100;  
parameter CNT_2MS_MAX = 10'd1000;  
parameter CNT_2S_MAX  = 10'd1000; 

//reg define 
reg [6:0] cnt_2us;
reg [9:0] cnt_2ms;
reg [9:0] cnt_2s;
reg       inc_dec_flag; //亮度递增/递减 0:递增 1:递减

//***************************************************** 
//**                  main code 
//***************************************************** 

//cnt_2us:计数2us 
always@(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        cnt_2us <= 7'b0;//复位把2us的寄存器进行清0处理，重新计数
    else if(cnt_2us == (CNT_2US_MAX - 7'b1 ))
        cnt_2us <= 7'b0;
    else 
        cnt_2us <= cnt_2us + 7'b1;
end

//cnt_2ms:计数2ms 
always@(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        cnt_2ms <= 10'b0;
    else if(cnt_2ms == (CNT_2MS_MAX - 10'b1) && cnt_2us == (CNT_2US_MAX - 7'b1))
        cnt_2ms <= 10'b0;
    else if((cnt_2us == CNT_2US_MAX - 7'b1))
        cnt_2ms <= cnt_2ms + 10'b1;
    else 
        cnt_2ms <= cnt_2ms;
end

//cnt_2s：计数器
always@(posedge sys_clk or negedge sys_rst_n) begin 
    if(!sys_rst_n) 
        cnt_2s <= 10'b0;
    else if(cnt_2s == (CNT_2S_MAX - 10'b1) && cnt_2ms == (CNT_2MS_MAX - 10'b1)
                                            && cnt_2us == (CNT_2US_MAX - 7'b1))
        cnt_2s <= 10'b0;                                        
    else if(cnt_2ms == (CNT_2MS_MAX - 10'b1) && cnt_2us == (CNT_2US_MAX - 7'b1))
        cnt_2s <= cnt_2s + 10'b1;
    else
        cnt_2s <= cnt_2s;
end
//inc_dec_flag为低电平，LED灯由暗变亮，inc_dec_flag为高电平，LED灯由亮变暗 
always@(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        inc_dec_flag <= 1'b0;
    else if(cnt_2s == (CNT_2S_MAX - 10'b1) && cnt_2ms ==( CNT_2MS_MAX - 10'b1)
                                            && cnt_2us == (CNT_2US_MAX - 7'b1))
        inc_dec_flag <= ~inc_dec_flag;
    else
        inc_dec_flag <= inc_dec_flag;
end

//led:输出信号连接到外部的LED灯
always@(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        led <= 1'b0;
    else if((inc_dec_flag == 1'b1 && cnt_2ms >= cnt_2s)|| (inc_dec_flag == 1'b0 && cnt_2ms <= cnt_2s))
        led <= 1'b1;
    else
        led <= 1'b0;
end


endmodule 
