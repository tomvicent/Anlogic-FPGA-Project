/************************************************************\
**	Copyright (c) 2012-2026 anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Gen time	:	2026-10-10 20:48:17
**	DI version	:	197563 2026/05/12
**	App version	:	(build number:6.2.2.200067)
\************************************************************/

module system (
    output    wire       [31:0] p2f_clk0
); 
    wire              w_port__ARM_Processor_System_0__p2f_clk0 ;
    wire              w_net__ARM_Processor_System_0__p2f_clk0 ; 

    assign w_net__ARM_Processor_System_0__p2f_clk0 = w_port__ARM_Processor_System_0__p2f_clk0 ;
    assign p2f_clk0 = {31'b0,w_net__ARM_Processor_System_0__p2f_clk0} ;

    system_ARM_Processor_System_0 system_ARM_Processor_System_0_Inst ( 
                                                                        .p2f_clk0(w_port__ARM_Processor_System_0__p2f_clk0) );

endmodule
