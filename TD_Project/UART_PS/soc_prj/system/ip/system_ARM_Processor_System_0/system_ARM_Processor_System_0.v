/************************************************************\
**	Copyright (c) 2012-2026 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Gen time	:	Oct 09 2026 18:17:36
**	IpTool version	:	2026.03(193873 2026/03/31)
**	App version	:	Release_2026.1_SP2
**	Ip Version	:	1.0
\************************************************************/
`timescale 1ns/1ps
module system_ARM_Processor_System_0
(
  output                        p2f_clk0
);

  ARM_Processor_System_system_ARM_Processor_System_0
  #(
      .GBE0_TXCLK_PHA(0),
      .P2F_CLK0_DIV(8)
  )ARM_Processor_System_Inst
  (
      .p2f_clk0(p2f_clk0)
  );
endmodule
