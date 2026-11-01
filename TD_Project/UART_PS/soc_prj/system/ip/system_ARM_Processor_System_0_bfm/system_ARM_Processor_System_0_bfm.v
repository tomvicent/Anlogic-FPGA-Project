/************************************************************\
**	Copyright (c) 2012-2026 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Gen time	:	Oct 10 2026 20:48:19
**	IpTool version	:	2026.03(193873 2026/03/31)
**	App version	:	Release_2026.1_SP2
**	Ip Version	:	1.0
\************************************************************/
`timescale 1ns/1ps
module system_ARM_Processor_System_0_bfm
(
  output                        master_fahb_clk_glb,
  output                        master_fahb_clk_lcl,
  input                         master_fahb_hresp,
  input   [31:0]                master_fahb_hrdata,
  output                        master_fahb_hsel,
  output  [32:0]                master_fahb_haddr,
  output  [2:0]                 master_fahb_hsize,
  output                        master_fahb_hwrite,
  output  [2:0]                 master_fahb_hburst,
  output  [3:0]                 master_fahb_hprot,
  output  [1:0]                 master_fahb_htrans,
  output                        master_fahb_hready,
  input                         pl2ps_fahb_fbclk,
  input                         master_fahb_hreadyout,
  output  [31:0]                master_fahb_hwdata,
  output                        p2f_clk3,
  output                        p2f_clk2,
  output                        p2f_clk1,
  output                        p2f_clk0,
  output                        p2f_rst3_n,
  output                        p2f_rst2_n,
  output                        p2f_rst1_n,
  output                        p2f_rst0_n,
  input   [15:0]                f2p_irq,
  input                         ps_srstb,
  input                         ps_clk,
  input                         ps_porb
);

  ps_bfm_top_system_ARM_Processor_System_0_bfm
  #(
      .AL_MEM_CLK_FREQ(400),
      .AL_FAHB_HCLK_FREQ(100),
      .AL_FCLK_CLK0_FREQ(50),
      .AL_FCLK_CLK1_FREQ(50),
      .AL_FCLK_CLK2_FREQ(50),
      .AL_FCLK_CLK3_FREQ(50),
      .AL_M_FAHB_ENABLE(1),
      .AL_S_AXI_HP0_ENABLE(0),
      .AL_S_AXI_HP1_ENABLE(0),
      .AL_M_AXI_GP0_ENABLE(0),
      .AL_M_AXI_GP1_ENABLE(0),
      .AL_S_AXI_GP0_ENABLE(0),
      .AL_S_AXI_GP1_ENABLE(0),
      .AL_S_AXI_ACP_ENABLE(0),
      .AL_M_AXI_GP0_THREAD_ID_WIDTH(12),
      .AL_M_AXI_GP1_THREAD_ID_WIDTH(12),
      .AL_IRQ_WIDTH(16),
      .AL_AXI_SGP_DATA_WIDTH(32)
  )ps_bfm_top_Inst
  (
      .master_fahb_clk_glb(master_fahb_clk_glb),
      .master_fahb_clk_lcl(master_fahb_clk_lcl),
      .master_fahb_hresp(master_fahb_hresp),
      .master_fahb_hrdata(master_fahb_hrdata),
      .master_fahb_hsel(master_fahb_hsel),
      .master_fahb_haddr(master_fahb_haddr),
      .master_fahb_hsize(master_fahb_hsize),
      .master_fahb_hwrite(master_fahb_hwrite),
      .master_fahb_hburst(master_fahb_hburst),
      .master_fahb_hprot(master_fahb_hprot),
      .master_fahb_htrans(master_fahb_htrans),
      .master_fahb_hready(master_fahb_hready),
      .pl2ps_fahb_fbclk(pl2ps_fahb_fbclk),
      .master_fahb_hreadyout(master_fahb_hreadyout),
      .master_fahb_hwdata(master_fahb_hwdata),
      .p2f_clk3(p2f_clk3),
      .p2f_clk2(p2f_clk2),
      .p2f_clk1(p2f_clk1),
      .p2f_clk0(p2f_clk0),
      .p2f_rst3_n(p2f_rst3_n),
      .p2f_rst2_n(p2f_rst2_n),
      .p2f_rst1_n(p2f_rst1_n),
      .p2f_rst0_n(p2f_rst0_n),
      .f2p_irq(f2p_irq),
      .ps_srstb(ps_srstb),
      .ps_clk(ps_clk),
      .ps_porb(ps_porb)
  );
endmodule
