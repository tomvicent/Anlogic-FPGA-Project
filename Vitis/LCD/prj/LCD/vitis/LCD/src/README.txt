LCD 白屏问题记录
================================================================
[2026-10-26]

现象：LCD 背光亮，整屏白色，无图像。

错误1（主因）：Vivado Block Design 漏接一根线
  v_axi4s_vid_out_0/vtg_ce  ->  v_tc_0/gen_clken
  说明：v_axi4s_vid_out 配置为 Slave 模式（C_VTG_MASTER_SLAVE=0），
        必须由 vtg_ce 控制外部 VTC 的 gen_clken，Video Out 才能
        和 VTC 对齐并 lock。漏接后 gen_clken 被综合工具默认接成 1
        （VTC 自由运行），Video Out 无法同步，不输出有效的 DE/像素
        数据，所以背光亮但显示白屏。
  修复：Vivado Tcl Console 执行：
        connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vtg_ce] [get_bd_pins v_tc_0/gen_clken]
        validate_bd_design
        save_bd_design
        然后重新综合、实现、生成 bitstream，重新导出 XSA，
        在 Vitis 里更新 platform 后重新下载运行。

错误2（次要）：design.xdc 引脚写错
  lcd_rgb_0_tri_io[1] 原来写的是 R19，正确应为 W19。
  R19 是触摸屏的 SCL，不是 LCD 的 B1。该错误只影响蓝色最低位，
  会造成颜色异常，但不是白屏主因。（已改正为 W19）

排查方法：
  1. 串口 115200 应打印 "LCD ID: xxxx" 和 "show color bar"。
     如果 LCD ID=0 或与实物屏不匹配，说明 LCD ID 读取/排线有问题，
     分辨率选错也会白屏，需要先确认 ID。
  2. 确认 FPGA 下载的是修复后新生成的 bitstream。
  3. 用示波器测 lcd_clk（800x480 约 33.3MHz）、DE/HS/VS 是否有波形。

参考工程：Example/alientek-zynq7020-examples/ZYNQ_Vitis_7020/24_vdma_lcd
================================================================

这里进行更改之后，需要在RTL ANALYSIS下面再进行更改不然导出的硬件会出现错误

================================================================
[2026-10-26 补充] 最终定位：Vitis 里下载的还是旧 bitstream
  现象：BD 已补 vtg_ce -> gen_clken、xdc 已改 W19、重新综合实现也成功，
        但下载运行后依旧白屏。
  原因：Vitis 平台的 hw\system_wrapper.xsa 仍是修复前那份（10-19），
        Launch 配置实际下载的 _ide\bitstream\system_wrapper.bit
        也是旧码流（MD5 06479C3C...），FPGA 里跑的不是修复后的设计。
  确认方法：
    1. 解压 XSA，看 system.hwh 里 vtg_ce 是否有
       SIGNAME="v_axi4s_vid_out_0_vtg_ce"；
    2. 比较 XSA 内嵌 bitstream 与 _ide\bitstream\*.bit 的 MD5。
  正确流程：
    Vivado 里 Generate Bitstream -> Export Hardware（含 bitstream）
    -> Vitis 里 Update Hardware Specification 选
       prj\LCD\system_wrapper.xsa（不要用平台 hw\ 下那份旧的）
    -> 重建 BSP -> Run/Debug（勾 Program FPGA）
  结果：LCD 链路跑通，彩条正常显示。下一步开始学习 OV5640。
================================================================
