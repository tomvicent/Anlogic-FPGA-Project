//****************************************Copyright (c)***********************************//
//原子哥在线教学平台：www.yuanzige.com
//技术支持：http://www.openedv.com/forum.php
//淘宝店铺：https://zhengdianyuanzi.tmall.com
//关注微信公众平台微信号："正点原子"，免费获取ZYNQ & FPGA & STM32 & LINUX资料。
//版权所有，盗版必究。
//Copyright(C) 正点原子 2023-2033
//All rights reserved                                  
//----------------------------------------------------------------------------------------
// File name:           ov5640_data_8b
// Created by:          正点原子
// Created date:        2025年10月13日14:17:02
// Version:             V1.0
// Descriptions:        ov5640数据采集模块
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

module ov5640_data_8b(
    input           rst_n,            //复位信号，低电平有效
                                       
    //摄像头接口                       
    input           cam_pclk,         //Camera像素时钟
    input           cam_vsync,        //Camera场同步信号
    input           cam_href,         //Camera行同步信号
    input   [7:0]   cam_data,         //Camera数据
    output          cam_rst_n,        //Camera复位信号，低电平有效
    output          cam_pwdn,         //Camera电源休眠信号，高电平有效
                                       
    //Video接口                        
    output          vid_clk,          //Video时钟
    output          vid_ce,           //Video时钟使能信号，高电平有效
    output          vid_vsync,        //Video场同步信号
    output          vid_active_video, //Video数据有效信号
    output   [7:0]  vid_data          //Video数据，RGB888格式
    );

//parameter define
parameter WAIT_FRAME = 10;            //等待摄像头输出的帧个数

//reg define
reg            rst_n_d0 ;
reg            rst_n_sync ;
reg            cam_vsync_d0;
reg            cam_vsync_d1;
reg            cam_href_d0;
reg            cam_href_d1;

reg  [5:0]     frame_cnt;      //对摄像头输出的帧进行计数   
reg            wait_done;      //等待摄像头输出的帧数完成
reg  [7:0]     cam_data_d0;
reg  [7:0]     cam_data_d1;

//wire define
wire           pos_vsync;

//输入场同步信号的上升沿
assign pos_vsync = ~cam_vsync_d1 & cam_vsync_d0;

//摄像头复位信号，低电平有效  1：不复位
assign cam_rst_n = 1'b1;

//电源休眠信号，高电平有效  0：电源不休眠
assign cam_pwdn = 1'b0;

assign vid_clk = cam_pclk;

assign vid_data = wait_done ?  cam_data_d1 : 8'b0;
assign vid_vsync = wait_done ? cam_vsync_d1 : 1'd0;
assign vid_active_video = wait_done ? cam_href_d1 : 1'b0;
assign vid_ce = wait_done ;

//对复位信号做异步复位，同步释放的处理
always @(posedge cam_pclk or negedge rst_n) begin
    if(!rst_n) begin
        rst_n_d0 <= 1'b0;
        rst_n_sync <= 1'b0;
    end
    else begin
        rst_n_d0 <= 1'b1;
        rst_n_sync <= rst_n_d0;
    end
end

//对行场同步信号进行打拍
always @(posedge cam_pclk or negedge rst_n_sync) begin
    if(!rst_n_sync) begin
        cam_vsync_d0 <= 1'b0;
        cam_vsync_d1 <= 1'b0;
        cam_href_d0 <= 1'b0;
        cam_href_d1 <= 1'b0;
    end
    else begin
        cam_vsync_d0 <= cam_vsync;
        cam_vsync_d1 <= cam_vsync_d0;
        cam_href_d0 <= cam_href;
        cam_href_d1 <= cam_href_d0;
    end
end

//统计摄像头输出的帧数
always @(posedge cam_pclk or negedge rst_n_sync) begin
    if(!rst_n_sync)
        frame_cnt <= 4'd0;
    else if(pos_vsync && (frame_cnt < WAIT_FRAME))
        frame_cnt <= frame_cnt + 4'd1;
end 

//摄像头输出的帧个数达到预设的参数，拉高等待完成信号
always @(posedge cam_pclk or negedge rst_n_sync) begin
    if(!rst_n_sync)
        wait_done <= 1'b0;
    else if(pos_vsync && (frame_cnt == WAIT_FRAME))  
        wait_done <= 1'b1;
end    

//对8位数据进行打拍
always @(posedge cam_pclk or negedge rst_n_sync) begin
    if(!rst_n_sync) begin
        cam_data_d0 <= 8'd0;
        cam_data_d1 <= 8'd0; 
    end
    else begin
        cam_data_d0 <= cam_data;
        cam_data_d1 <= cam_data_d0;
    end
end    
    
endmodule    
