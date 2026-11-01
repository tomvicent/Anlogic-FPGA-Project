/************************************************************\
**	Copyright (c) 2012-2026 anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Gen time	:	2026-10-10 20:48:21
**	DI version	:	197563 2026/05/12
**	App version	:	(build number:6.2.2.200067)
\************************************************************/

module system_sim (
    output    wire       [31:0] p2f_clk0
); 
    wire              w_port__ARM_Processor_System_0__p2f_clk0 ;
    wire              w_net__ARM_Processor_System_0__p2f_clk0 ; 

    assign w_net__ARM_Processor_System_0__p2f_clk0 = w_port__ARM_Processor_System_0__p2f_clk0 ;
    assign p2f_clk0 = {31'b0,w_net__ARM_Processor_System_0__p2f_clk0} ;

    system_ARM_Processor_System_0_bfm system_ARM_Processor_System_0_bfm_Inst ( 
                                                                                .pl2ps_fahb_fbclk(1'b0)
                                                                              , .master_fahb_hreadyout(1'b0)
                                                                              , .f2p_irq(16'b0)
                                                                              , .ps_srstb(1'b0)
                                                                              , .ps_clk(1'b0)
                                                                              , .ps_porb(1'b0)
                                                                              , .master_fahb_hresp(1'b0)
                                                                              , .master_fahb_hrdata(32'b0)
                                                                              , .master_fahb_haddr()
                                                                              , .master_fahb_hsize()
                                                                              , .master_fahb_hwrite()
                                                                              , .master_fahb_hburst()
                                                                              , .master_fahb_hprot()
                                                                              , .master_fahb_htrans()
                                                                              , .master_fahb_hwdata()
                                                                              , .master_fahb_clk_glb()
                                                                              , .master_fahb_clk_lcl()
                                                                              , .master_fahb_hsel()
                                                                              , .master_fahb_hready()
                                                                              , .p2f_clk3()
                                                                              , .p2f_clk2()
                                                                              , .p2f_clk1()
                                                                              , .p2f_clk0(w_port__ARM_Processor_System_0__p2f_clk0)
                                                                              , .p2f_rst3_n()
                                                                              , .p2f_rst2_n()
                                                                              , .p2f_rst1_n()
                                                                              , .p2f_rst0_n() );

endmodule
