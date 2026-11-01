`timescale 1ns/1ps

module tb();

reg                             aclk;
reg                             aresetn;
reg                             sresetn;

parameter AW_CH0_M  =  33   ;       // Addr width
parameter IW_CH0_M  =  12   ;       // Id width
parameter BW_CH0_M  =   4   ;       // Id width
parameter DW_CH0_M  =  32   ;       // data bus width

parameter AW_CH1_M  =  33   ;       // Addr width
parameter IW_CH1_M  =  12   ;       // Id width
parameter BW_CH1_M  =   4   ;       // Id width
parameter DW_CH1_M  =  32   ;       // data bus width


parameter AW_CH0_S  =  33   ;       // Addr width
parameter IW_CH0_S  =   6   ;       // Id width //less than master id width
parameter BW_CH0_S  =   4   ;       // Len width
parameter DW_CH0_S  =   32   ;       // data bus width

parameter AW_CH1_S  =  33   ;       // Addr width
parameter IW_CH1_S  =   6   ;       // Id width
parameter BW_CH1_S  =   4   ;       // Len width
parameter DW_CH1_S  =   32   ;       // data bus width

parameter AW_CH2_S  =  33   ;       // Addr width
parameter IW_CH2_S  =   5   ;       // Id width
parameter BW_CH2_S  =   3   ;       // Len width
parameter DW_CH2_S  =   64   ;       // data bus width

parameter AW_CH3_S  =  33   ;       // Addr width
parameter IW_CH3_S  =   6   ;       // Id width
parameter BW_CH3_S  =   4   ;       // Len width
parameter DW_CH3_S  =   64   ;       // data bus width

parameter AW_CH4_S  =  33   ;       // Addr width
parameter IW_CH4_S  =   6   ;       // Id width
parameter BW_CH4_S  =   4   ;       // Len width
parameter DW_CH4_S  =   64   ;       // data bus width

parameter AL_S_AXI_HP0_DATA_WIDTH = 64;
parameter AL_S_AXI_HP1_DATA_WIDTH = 64;

parameter AL_M_AXI_GP0_THREAD_ID_WIDTH = 12;
parameter AL_M_AXI_GP1_THREAD_ID_WIDTH = 12; 

reg [16-1:0] IRQ_F2P;
wire PS_CLK;

wire M_AXI_GP0_ARVALID;
wire M_AXI_GP0_AWVALID;
wire M_AXI_GP0_BREADY;
wire M_AXI_GP0_RREADY;
wire M_AXI_GP0_WLAST;
wire M_AXI_GP0_WVALID;
wire [AL_M_AXI_GP0_THREAD_ID_WIDTH-1:0] M_AXI_GP0_ARID;
wire [AL_M_AXI_GP0_THREAD_ID_WIDTH-1:0] M_AXI_GP0_AWID;
wire [1:0] M_AXI_GP0_ARBURST;
wire M_AXI_GP0_ARLOCK;
wire [1:0] M_AXI_GP0_ARSIZE;
wire [1:0] M_AXI_GP0_AWBURST;
wire M_AXI_GP0_AWLOCK;
wire [1:0] M_AXI_GP0_AWSIZE;
wire [2:0] M_AXI_GP0_ARPROT;
wire [2:0] M_AXI_GP0_AWPROT;
wire [32:0] M_AXI_GP0_ARADDR;
wire [32:0] M_AXI_GP0_AWADDR;
wire [31:0] M_AXI_GP0_WDATA;
wire [3:0] M_AXI_GP0_ARCACHE;
wire [3:0] M_AXI_GP0_ARLEN;
wire [3:0] M_AXI_GP0_AWCACHE;
wire [3:0] M_AXI_GP0_AWLEN;
wire [3:0] M_AXI_GP0_WSTRB;
wire M_AXI_GP0_ARREADY;
wire M_AXI_GP0_AWREADY;
wire M_AXI_GP0_BVALID;
wire M_AXI_GP0_RLAST;
wire M_AXI_GP0_RVALID;
wire M_AXI_GP0_WREADY;
wire [AL_M_AXI_GP0_THREAD_ID_WIDTH-1:0] M_AXI_GP0_BID;
wire [AL_M_AXI_GP0_THREAD_ID_WIDTH-1:0] M_AXI_GP0_RID;
wire [1:0] M_AXI_GP0_BRESP;
wire [1:0] M_AXI_GP0_RRESP;
wire [31:0] M_AXI_GP0_RDATA;
wire M_AXI_GP1_ARVALID;
wire M_AXI_GP1_AWVALID;
wire M_AXI_GP1_BREADY;
wire M_AXI_GP1_RREADY;
wire M_AXI_GP1_WLAST;
wire M_AXI_GP1_WVALID;
wire [AL_M_AXI_GP1_THREAD_ID_WIDTH-1:0] M_AXI_GP1_ARID;
wire [AL_M_AXI_GP1_THREAD_ID_WIDTH-1:0] M_AXI_GP1_AWID;
wire [1:0] M_AXI_GP1_ARBURST;
wire M_AXI_GP1_ARLOCK;
wire [1:0] M_AXI_GP1_ARSIZE;
wire [1:0] M_AXI_GP1_AWBURST;
wire M_AXI_GP1_AWLOCK;
wire [1:0] M_AXI_GP1_AWSIZE;
wire [2:0] M_AXI_GP1_ARPROT;
wire [2:0] M_AXI_GP1_AWPROT;
wire [32:0] M_AXI_GP1_ARADDR;
wire [32:0] M_AXI_GP1_AWADDR;
wire [31:0] M_AXI_GP1_WDATA;
wire [3:0] M_AXI_GP1_ARCACHE;
wire [3:0] M_AXI_GP1_ARLEN;
wire [3:0] M_AXI_GP1_AWCACHE;
wire [3:0] M_AXI_GP1_AWLEN;
wire [3:0] M_AXI_GP1_WSTRB;
wire M_AXI_GP1_ARREADY;
wire M_AXI_GP1_AWREADY;
wire M_AXI_GP1_BVALID;
wire M_AXI_GP1_RLAST;
wire M_AXI_GP1_RVALID;
wire M_AXI_GP1_WREADY;
wire [AL_M_AXI_GP1_THREAD_ID_WIDTH-1:0] M_AXI_GP1_BID;
wire [AL_M_AXI_GP1_THREAD_ID_WIDTH-1:0] M_AXI_GP1_RID;
wire [1:0] M_AXI_GP1_BRESP;
wire [1:0] M_AXI_GP1_RRESP;
wire [31:0] M_AXI_GP1_RDATA;
wire S_AXI_GP0_ARREADY;
wire S_AXI_GP0_AWREADY;
wire S_AXI_GP0_BVALID;
wire S_AXI_GP0_RLAST;
wire S_AXI_GP0_RVALID; 
wire S_AXI_GP0_WREADY;
wire [1:0] S_AXI_GP0_BRESP;
wire [1:0] S_AXI_GP0_RRESP;
wire [31:0] S_AXI_GP0_RDATA;
wire [5:0] S_AXI_GP0_BID;
wire [5:0] S_AXI_GP0_RID;
wire S_AXI_GP0_ARVALID; 
wire S_AXI_GP0_AWVALID; 
wire S_AXI_GP0_BREADY; 
wire S_AXI_GP0_RREADY; 
wire S_AXI_GP0_WLAST;
wire S_AXI_GP0_WVALID; 
wire [1:0] S_AXI_GP0_ARBURST;
wire S_AXI_GP0_ARLOCK;
wire [1:0] S_AXI_GP0_ARSIZE;
wire [1:0] S_AXI_GP0_AWBURST;
wire S_AXI_GP0_AWLOCK;
wire [1:0] S_AXI_GP0_AWSIZE;
wire [2:0] S_AXI_GP0_ARPROT;
wire [2:0] S_AXI_GP0_AWPROT;
wire [32:0] S_AXI_GP0_ARADDR;
wire [32:0] S_AXI_GP0_AWADDR;
wire [31:0] S_AXI_GP0_WDATA;
wire [3:0] S_AXI_GP0_ARCACHE;
wire [3:0] S_AXI_GP0_ARLEN;
wire [3:0] S_AXI_GP0_AWCACHE;
wire [3:0] S_AXI_GP0_AWLEN;
wire [3:0] S_AXI_GP0_WSTRB;
wire [5:0] S_AXI_GP0_ARID;
wire [5:0] S_AXI_GP0_AWID;
wire S_AXI_GP1_ARREADY;
wire S_AXI_GP1_AWREADY;
wire S_AXI_GP1_BVALID;
wire S_AXI_GP1_RLAST;
wire S_AXI_GP1_RVALID; 
wire S_AXI_GP1_WREADY;
wire [1:0] S_AXI_GP1_BRESP;
wire [1:0] S_AXI_GP1_RRESP;
wire [31:0] S_AXI_GP1_RDATA;
wire [5:0] S_AXI_GP1_BID;
wire [5:0] S_AXI_GP1_RID;
wire S_AXI_GP1_ARVALID; 
wire S_AXI_GP1_AWVALID; 
wire S_AXI_GP1_BREADY; 
wire S_AXI_GP1_RREADY; 
wire S_AXI_GP1_WLAST;
wire S_AXI_GP1_WVALID; 
wire [1:0] S_AXI_GP1_ARBURST;
wire S_AXI_GP1_ARLOCK;
wire [1:0] S_AXI_GP1_ARSIZE;
wire [1:0] S_AXI_GP1_AWBURST;
wire S_AXI_GP1_AWLOCK;
wire [1:0] S_AXI_GP1_AWSIZE;
wire [2:0] S_AXI_GP1_ARPROT;
wire [2:0] S_AXI_GP1_AWPROT;
wire [32:0] S_AXI_GP1_ARADDR;
wire [32:0] S_AXI_GP1_AWADDR;
wire [31:0] S_AXI_GP1_WDATA;
wire [3:0] S_AXI_GP1_ARCACHE;
wire [3:0] S_AXI_GP1_ARLEN;
wire [3:0] S_AXI_GP1_AWCACHE;
wire [3:0] S_AXI_GP1_AWLEN;
wire [3:0] S_AXI_GP1_WSTRB;
wire [5:0] S_AXI_GP1_ARID;
wire [5:0] S_AXI_GP1_AWID;
wire S_AXI_ACP_AWREADY;
wire S_AXI_ACP_ARREADY;
wire S_AXI_ACP_BVALID;
wire S_AXI_ACP_RLAST;
wire S_AXI_ACP_RVALID;
wire S_AXI_ACP_WREADY;
wire [1:0] S_AXI_ACP_BRESP;
wire [1:0] S_AXI_ACP_RRESP;
wire [4:0] S_AXI_ACP_BID;
wire [4:0] S_AXI_ACP_RID;
wire [63:0] S_AXI_ACP_RDATA;
wire S_AXI_ACP_ARVALID;
wire S_AXI_ACP_AWVALID;
wire S_AXI_ACP_BREADY;
wire S_AXI_ACP_RREADY;
wire S_AXI_ACP_WLAST;
wire S_AXI_ACP_WVALID;
wire [4:0] S_AXI_ACP_ARID;
wire [2:0] S_AXI_ACP_ARPROT;
wire [4:0] S_AXI_ACP_AWID;
wire [2:0] S_AXI_ACP_AWPROT;
wire [32:0] S_AXI_ACP_ARADDR;
wire [32:0] S_AXI_ACP_AWADDR;
wire [3:0] S_AXI_ACP_ARCACHE;
wire [2:0] S_AXI_ACP_ARLEN;
wire [3:0] S_AXI_ACP_AWCACHE;
wire [2:0] S_AXI_ACP_AWLEN;
wire [1:0] S_AXI_ACP_ARUSER;
wire [1:0] S_AXI_ACP_AWUSER;
wire [63:0] S_AXI_ACP_WDATA;
wire [7:0] S_AXI_ACP_WSTRB;
wire S_AXI_HP0_ARREADY;
wire S_AXI_HP0_AWREADY;
wire S_AXI_HP0_BVALID;
wire S_AXI_HP0_RLAST;
wire S_AXI_HP0_RVALID; 
wire S_AXI_HP0_WREADY;
wire [1:0] S_AXI_HP0_BRESP;
wire [1:0] S_AXI_HP0_RRESP;
wire [5:0] S_AXI_HP0_BID;
wire [5:0] S_AXI_HP0_RID;
wire [AL_S_AXI_HP0_DATA_WIDTH-1:0] S_AXI_HP0_RDATA;
wire S_AXI_HP0_ARVALID; 
wire S_AXI_HP0_AWVALID; 
wire S_AXI_HP0_BREADY; 
wire S_AXI_HP0_RREADY; 
wire S_AXI_HP0_WLAST;
wire S_AXI_HP0_WVALID; 
wire [1:0] S_AXI_HP0_ARBURST;
wire S_AXI_HP0_ARLOCK;
wire [1:0] S_AXI_HP0_ARSIZE;
wire [1:0] S_AXI_HP0_AWBURST;
wire S_AXI_HP0_AWLOCK;
wire [1:0] S_AXI_HP0_AWSIZE;
wire [2:0] S_AXI_HP0_ARPROT;
wire [2:0] S_AXI_HP0_AWPROT;
wire [32:0] S_AXI_HP0_ARADDR;
wire [32:0] S_AXI_HP0_AWADDR;
wire [3:0] S_AXI_HP0_ARCACHE;
wire [3:0] S_AXI_HP0_ARLEN;
wire [3:0] S_AXI_HP0_ARQOS;
wire [3:0] S_AXI_HP0_AWCACHE;
wire [3:0] S_AXI_HP0_AWLEN;
wire [3:0] S_AXI_HP0_AWQOS;
wire [5:0] S_AXI_HP0_ARID;
wire [5:0] S_AXI_HP0_AWID;
wire [AL_S_AXI_HP0_DATA_WIDTH-1:0] S_AXI_HP0_WDATA;
wire [AL_S_AXI_HP0_DATA_WIDTH/8-1:0] S_AXI_HP0_WSTRB;
wire S_AXI_HP1_ARREADY;
wire S_AXI_HP1_AWREADY;
wire S_AXI_HP1_BVALID;
wire S_AXI_HP1_RLAST;
wire S_AXI_HP1_RVALID; 
wire S_AXI_HP1_WREADY;
wire [1:0] S_AXI_HP1_BRESP;
wire [1:0] S_AXI_HP1_RRESP;
wire [5:0] S_AXI_HP1_BID;
wire [5:0] S_AXI_HP1_RID;
wire [AL_S_AXI_HP1_DATA_WIDTH-1:0] S_AXI_HP1_RDATA;
wire S_AXI_HP1_ARVALID; 
wire S_AXI_HP1_AWVALID; 
wire S_AXI_HP1_BREADY; 
wire S_AXI_HP1_RREADY; 
wire S_AXI_HP1_WLAST;
wire S_AXI_HP1_WVALID; 
wire [1:0] S_AXI_HP1_ARBURST;
wire S_AXI_HP1_ARLOCK;
wire [1:0] S_AXI_HP1_ARSIZE;
wire [1:0] S_AXI_HP1_AWBURST;
wire S_AXI_HP1_AWLOCK;
wire [1:0] S_AXI_HP1_AWSIZE;
wire [2:0] S_AXI_HP1_ARPROT;
wire [2:0] S_AXI_HP1_AWPROT;
wire [32:0] S_AXI_HP1_ARADDR;
wire [32:0] S_AXI_HP1_AWADDR;
wire [3:0] S_AXI_HP1_ARCACHE;
wire [3:0] S_AXI_HP1_ARLEN;
wire [3:0] S_AXI_HP1_ARQOS;
wire [3:0] S_AXI_HP1_AWCACHE;
wire [3:0] S_AXI_HP1_AWLEN;
wire [3:0] S_AXI_HP1_AWQOS;
wire [5:0] S_AXI_HP1_ARID;
wire [5:0] S_AXI_HP1_AWID;
wire [AL_S_AXI_HP1_DATA_WIDTH-1:0] S_AXI_HP1_WDATA;
wire [AL_S_AXI_HP1_DATA_WIDTH/8-1:0] S_AXI_HP1_WSTRB;

wire FAHB_HCLK_GLB;
wire FAHB_HCLK_LCL;
wire FAHB_HRESETN;
wire FAHB_HRESP;
wire [31:0] FAHB_HRDATA;
wire FAHB_HSEL;
wire [32:0] FAHB_HADDR;
wire [2:0] FAHB_HSIZE;
wire FAHB_HWRITE;
wire [2:0] FAHB_HBURST;
wire [3:0] FAHB_HPROT;
wire [1:0] FAHB_HTRANS;
wire FAHB_HREADY;
wire FAHB_FBHCLK;
wire FAHB_HREADYOUT;
wire [31:0] FAHB_HWDATA;

wire FCLK_CLK3;
wire FCLK_CLK2;
wire FCLK_CLK1;
wire FCLK_CLK0;
wire FCLK_RESET3_N;
wire FCLK_RESET2_N;
wire FCLK_RESET1_N;
wire FCLK_RESET0_N;


axi_slave_du #(
    .S_AXI_ID_WIDTH(IW_CH0_M),
	.S_AXI_DATA_WIDTH(DW_CH0_M),
	.S_AXI_ADDR_WIDTH(AW_CH0_M)
)
U_axi_slave_du_gp0(/*autoinst*/
    		// Ports of Axi Slave Bus Interface S00_AXI
    .s_axi_aclk                   (aclk                                ), // input 
    .s_axi_aresetn                (aresetn                             ), // input 
    .s_axi_awaddr                 (M_AXI_GP0_AWADDR), // input 
    .s_axi_awlen                  ({4'b0, M_AXI_GP0_AWLEN[3:0]}                          ), // input 
    .s_axi_awsize                 (M_AXI_GP0_AWSIZE                         ), // input 
    .s_axi_awburst                (M_AXI_GP0_AWBURST[1:0]                        ), // input 
    .s_axi_awlock                 (M_AXI_GP0_AWLOCK                              ), // input 
    .s_axi_awcache                (M_AXI_GP0_AWCACHE[3:0]                        ), // input 
    .s_axi_awprot                 (M_AXI_GP0_AWPROT[2:0]                         ), // input 
    //.s_axi_awqos                  (M_AXI_GP0_AWQOS[3:0]                          ), // input 
    .s_axi_bid                    (M_AXI_GP0_BID),
    .s_axi_awvalid                (M_AXI_GP0_AWVALID                             ), // input 
    .s_axi_awready                (M_AXI_GP0_AWREADY                             ), // output
    .s_axi_wdata                  (M_AXI_GP0_WDATA), // input 
    .s_axi_wstrb                  (M_AXI_GP0_WSTRB), // input 
    .s_axi_wlast                  (M_AXI_GP0_WLAST                               ), // input 
    .s_axi_wvalid                 (M_AXI_GP0_WVALID                              ), // input 
    .s_axi_wready                 (M_AXI_GP0_WREADY                              ), // output
    .s_axi_bresp                  (M_AXI_GP0_BRESP[1:0]                          ), // output
    		//output wire [C_S00_AXI_BUSER_WIDTH-1 : 0] s_axi_buser,
    .s_axi_bvalid                 (M_AXI_GP0_BVALID                              ), // output
    .s_axi_bready                 (M_AXI_GP0_BREADY                              ), // input 
    .s_axi_arid		            (M_AXI_GP0_ARID),
    .s_axi_awid                   (M_AXI_GP0_AWID),
    .s_axi_araddr                 (M_AXI_GP0_ARADDR), // input 
    .s_axi_arlen                  ({4'b0, M_AXI_GP0_ARLEN[3:0]}                          ), // input 
    .s_axi_arsize                 (M_AXI_GP0_ARSIZE                         ), // input 
    .s_axi_arburst                (M_AXI_GP0_ARBURST[1:0]                        ), // input 
    .s_axi_arlock                 (M_AXI_GP0_ARLOCK                              ), // input 
    .s_axi_arcache                (M_AXI_GP0_ARCACHE[3:0]                        ), // input 
    .s_axi_arprot                 (M_AXI_GP0_ARPROT[2:0]                         ), // input 
    //.s_axi_arqos                  (M_AXI_GP0_ARQOS[3:0]                          ), // input 
    		//input wire [3 : 0] s_axi_arregion,
    		//input wire [C_S00_AXI_ARUSER_WIDTH-1 : 0] s_axi_aruser,
    .s_axi_arvalid                (M_AXI_GP0_ARVALID                             ), // input 
    .s_axi_arready                (M_AXI_GP0_ARREADY                             ), // output
    .s_axi_rid                    (M_AXI_GP0_RID),
    .s_axi_rdata                  (M_AXI_GP0_RDATA), // output
    .s_axi_rresp                  (M_AXI_GP0_RRESP[1:0]                          ), // output
    .s_axi_rlast                  (M_AXI_GP0_RLAST                               ), // output
    		//output wire [C_S00_AXI_RUSER_WIDTH-1 : 0] s_axi_ruser,
    .s_axi_rvalid                 (M_AXI_GP0_RVALID                              ), // output
    .s_axi_rready                 (M_AXI_GP0_RREADY                              )  // input 

);

axi_slave_du #(
    .S_AXI_ID_WIDTH(IW_CH1_M),
	.S_AXI_DATA_WIDTH(DW_CH1_M),
	.S_AXI_ADDR_WIDTH(AW_CH1_M)
)
U_axi_slave_du_gp1(/*autoinst*/
    		// Ports of Axi Slave Bus Interface S00_AXI
    .s_axi_aclk                   (aclk                                ), // input 
    .s_axi_aresetn                (aresetn                             ), // input 
    .s_axi_awaddr                 (M_AXI_GP1_AWADDR), // input 
    .s_axi_awlen                  ({4'b0, M_AXI_GP1_AWLEN[3:0]}                          ), // input 
    .s_axi_awsize                 (M_AXI_GP1_AWSIZE                         ), // input 
    .s_axi_awburst                (M_AXI_GP1_AWBURST[1:0]                        ), // input 
    .s_axi_awlock                 (M_AXI_GP1_AWLOCK                              ), // input 
    .s_axi_awcache                (M_AXI_GP1_AWCACHE[3:0]                        ), // input 
    .s_axi_awprot                 (M_AXI_GP1_AWPROT[2:0]                         ), // input 
    //.s_axi_awqos                  (M_AXI_GP1_AWQOS[3:0]                          ), // input 
    .s_axi_bid                    (M_AXI_GP1_BID),
    .s_axi_awvalid                (M_AXI_GP1_AWVALID                             ), // input 
    .s_axi_awready                (M_AXI_GP1_AWREADY                             ), // output
    .s_axi_wdata                  (M_AXI_GP1_WDATA), // input 
    .s_axi_wstrb                  (M_AXI_GP1_WSTRB), // input 
    .s_axi_wlast                  (M_AXI_GP1_WLAST                               ), // input 
    .s_axi_wvalid                 (M_AXI_GP1_WVALID                              ), // input 
    .s_axi_wready                 (M_AXI_GP1_WREADY                              ), // output
    .s_axi_bresp                  (M_AXI_GP1_BRESP[1:0]                          ), // output
    		//output wire [C_S00_AXI_BUSER_WIDTH-1 : 0] s_axi_buser,
    .s_axi_bvalid                 (M_AXI_GP1_BVALID                              ), // output
    .s_axi_bready                 (M_AXI_GP1_BREADY                              ), // input 
    .s_axi_arid		            (M_AXI_GP1_ARID),
    .s_axi_awid                   (M_AXI_GP1_AWID),
    .s_axi_araddr                 (M_AXI_GP1_ARADDR), // input 
    .s_axi_arlen                  ({4'b0, M_AXI_GP1_ARLEN[3:0]}                          ), // input 
    .s_axi_arsize                 (M_AXI_GP1_ARSIZE                         ), // input 
    .s_axi_arburst                (M_AXI_GP1_ARBURST[1:0]                        ), // input 
    .s_axi_arlock                 (M_AXI_GP1_ARLOCK                              ), // input 
    .s_axi_arcache                (M_AXI_GP1_ARCACHE[3:0]                        ), // input 
    .s_axi_arprot                 (M_AXI_GP1_ARPROT[2:0]                         ), // input 
    //.s_axi_arqos                  (M_AXI_GP1_ARQOS[3:0]                          ), // input 
    		//input wire [3 : 0] s_axi_arregion,
    		//input wire [C_S00_AXI_ARUSER_WIDTH-1 : 0] s_axi_aruser,
    .s_axi_arvalid                (M_AXI_GP1_ARVALID                             ), // input 
    .s_axi_arready                (M_AXI_GP1_ARREADY                             ), // output
    .s_axi_rid                    (M_AXI_GP1_RID),
    .s_axi_rdata                  (M_AXI_GP1_RDATA), // output
    .s_axi_rresp                  (M_AXI_GP1_RRESP[1:0]                          ), // output
    .s_axi_rlast                  (M_AXI_GP1_RLAST                               ), // output
    		//output wire [C_S00_AXI_RUSER_WIDTH-1 : 0] s_axi_ruser,
    .s_axi_rvalid                 (M_AXI_GP1_RVALID                              ), // output
    .s_axi_rready                 (M_AXI_GP1_RREADY                              )  // input 

);

axi_master_du #(
    .IW(IW_CH0_S),
    .AW(AW_CH0_S),
    .BW(BW_CH0_S),
    .DW(DW_CH0_S)
)  U_axi_master_du_gp0(
    .CLK                      (aclk), // input
    .RSTN                     (aresetn), // input

    .AWID                     (S_AXI_GP0_AWID[IW_CH0_S-1:0]                           ), // output
    .AWADDR                   (S_AXI_GP0_AWADDR                        ), // output
    .AWLEN                    (S_AXI_GP0_AWLEN                            ), // output
    .AWSIZE                   (S_AXI_GP0_AWSIZE                           ), // output
    .AWBURST                  (S_AXI_GP0_AWBURST                          ), // output
    .AWLOCK                   (S_AXI_GP0_AWLOCK                               ), //output
    .AWCACHE                  (S_AXI_GP0_AWCACHE                          ), // output
    .AWPROT                   (S_AXI_GP0_AWPROT                           ), // output
    .AWVALID                  (S_AXI_GP0_AWVALID                              ), //output
    .AWREADY                  (S_AXI_GP0_AWREADY                              ), // input
    .WDATA                    (S_AXI_GP0_WDATA                           ), // output
    .WSTRB                    (S_AXI_GP0_WSTRB                            ), // output
    .WLAST                    (S_AXI_GP0_WLAST                                ), //output
    .WVALID                   (S_AXI_GP0_WVALID                               ), //output
    .WREADY                   (S_AXI_GP0_WREADY                               ), // input
    .BID                      (S_AXI_GP0_BID), // input
    .BRESP                    (S_AXI_GP0_BRESP                            ), // input
    .BVALID                   (S_AXI_GP0_BVALID                               ), // input
    .BREADY                   (S_AXI_GP0_BREADY                               ), //output
    .AWUSER                   (),
    .AWQOS                    (),
    .ARUSER                   (),
    .ARQOS                    (),
    .ARID                     (S_AXI_GP0_ARID[IW_CH0_S-1:0]                           ), // output
    .ARADDR                   (S_AXI_GP0_ARADDR                        ), // output
    .ARLEN                    (S_AXI_GP0_ARLEN                            ), // output
    .ARSIZE                   (S_AXI_GP0_ARSIZE                           ), // output
    .ARBURST                  (S_AXI_GP0_ARBURST                          ), // output
    .ARLOCK                   (S_AXI_GP0_ARLOCK                               ), //output
    .ARCACHE                  (S_AXI_GP0_ARCACHE                          ), // output
    .ARPROT                   (S_AXI_GP0_ARPROT                           ), // output
    .ARVALID                  (S_AXI_GP0_ARVALID                              ), //output
    .ARREADY                  (S_AXI_GP0_ARREADY                              ), // input
    .RID                      (S_AXI_GP0_RID), // input
    .RDATA                    (S_AXI_GP0_RDATA                           ), // input
    .RRESP                    (S_AXI_GP0_RRESP                            ), // input
    .RLAST                    (S_AXI_GP0_RLAST                                ), // input
    .RVALID                   (S_AXI_GP0_RVALID                               ), // input
    .RREADY                   (S_AXI_GP0_RREADY                               )  //output

);

axi_master_du #(
    .IW(IW_CH1_S),
    .AW(AW_CH1_S),
    .BW(BW_CH1_S),
    .DW(DW_CH1_S)
)  U_axi_master_du_gp1(
    .CLK                      (aclk), // input
    .RSTN                     (aresetn), // input

    .AWID                     (S_AXI_GP1_AWID[IW_CH1_S-1:0]                           ), // output
    .AWADDR                   (S_AXI_GP1_AWADDR                        ), // output
    .AWLEN                    (S_AXI_GP1_AWLEN                            ), // output
    .AWSIZE                   (S_AXI_GP1_AWSIZE                           ), // output
    .AWBURST                  (S_AXI_GP1_AWBURST                          ), // output
    .AWLOCK                   (S_AXI_GP1_AWLOCK                               ), //output
    .AWCACHE                  (S_AXI_GP1_AWCACHE                          ), // output
    .AWPROT                   (S_AXI_GP1_AWPROT                           ), // output
    .AWVALID                  (S_AXI_GP1_AWVALID                              ), //output
    .AWREADY                  (S_AXI_GP1_AWREADY                              ), // input
    .WDATA                    (S_AXI_GP1_WDATA                           ), // output
    .WSTRB                    (S_AXI_GP1_WSTRB                            ), // output
    .WLAST                    (S_AXI_GP1_WLAST                                ), //output
    .WVALID                   (S_AXI_GP1_WVALID                               ), //output
    .WREADY                   (S_AXI_GP1_WREADY                               ), // input
    .BID                      (S_AXI_GP1_BID), // input
    .BRESP                    (S_AXI_GP1_BRESP                            ), // input
    .BVALID                   (S_AXI_GP1_BVALID                               ), // input
    .BREADY                   (S_AXI_GP1_BREADY                               ), //output
    .AWUSER                   (),
    .AWQOS                    (),
    .ARUSER                   (),
    .ARQOS                    (),
    .ARID                     (S_AXI_GP1_ARID[IW_CH1_S-1:0]                           ), // output
    .ARADDR                   (S_AXI_GP1_ARADDR                        ), // output
    .ARLEN                    (S_AXI_GP1_ARLEN                            ), // output
    .ARSIZE                   (S_AXI_GP1_ARSIZE                           ), // output
    .ARBURST                  (S_AXI_GP1_ARBURST                          ), // output
    .ARLOCK                   (S_AXI_GP1_ARLOCK                               ), //output
    .ARCACHE                  (S_AXI_GP1_ARCACHE                          ), // output
    .ARPROT                   (S_AXI_GP1_ARPROT                           ), // output
    .ARVALID                  (S_AXI_GP1_ARVALID                              ), //output
    .ARREADY                  (S_AXI_GP1_ARREADY                              ), // input
    .RID                      (S_AXI_GP1_RID), // input
    .RDATA                    (S_AXI_GP1_RDATA                           ), // input
    .RRESP                    (S_AXI_GP1_RRESP                            ), // input
    .RLAST                    (S_AXI_GP1_RLAST                                ), // input
    .RVALID                   (S_AXI_GP1_RVALID                               ), // input
    .RREADY                   (S_AXI_GP1_RREADY                               )  //output

);

axi_master_du #(
    .IW(IW_CH2_S),
    .AW(AW_CH2_S),
    .BW(BW_CH2_S),
    .DW(DW_CH2_S)
)  U_axi_master_du_acp(
    .CLK                      (aclk), // input
    .RSTN                     (aresetn), // input

    .AWID                     (S_AXI_ACP_AWID[IW_CH2_S-1:0]                           ), // output
    .AWADDR                   (S_AXI_ACP_AWADDR                        ), // output
    .AWLEN                    (S_AXI_ACP_AWLEN                            ), // output
    .AWCACHE                  (S_AXI_ACP_AWCACHE                          ), // output
    .AWPROT                   (S_AXI_ACP_AWPROT                           ), // output
    .AWVALID                  (S_AXI_ACP_AWVALID                              ), //output
    .AWREADY                  (S_AXI_ACP_AWREADY                              ), // input
    .AWUSER                   (S_AXI_ACP_AWUSER                              ), // input
    .WDATA                    (S_AXI_ACP_WDATA                           ), // output
    .WSTRB                    (S_AXI_ACP_WSTRB                            ), // output
    .WLAST                    (S_AXI_ACP_WLAST                                ), //output
    .WVALID                   (S_AXI_ACP_WVALID                               ), //output
    .WREADY                   (S_AXI_ACP_WREADY                               ), // input
    .BID                      (S_AXI_ACP_BID), // input
    .BRESP                    (S_AXI_ACP_BRESP                            ), // input
    .BVALID                   (S_AXI_ACP_BVALID                               ), // input
    .BREADY                   (S_AXI_ACP_BREADY                               ), //output
    .AWQOS                    (),
    .AWLOCK                   (),
    .AWBURST                  (),
    .AWSIZE                   (),
    .ARQOS                    (),
    .ARLOCK                   (),
    .ARBURST                  (),
    .ARSIZE                   (),
    .ARID                     (S_AXI_ACP_ARID[IW_CH2_S-1:0]                           ), // output
    .ARADDR                   (S_AXI_ACP_ARADDR                        ), // output
    .ARLEN                    (S_AXI_ACP_ARLEN                            ), // output
    .ARCACHE                  (S_AXI_ACP_ARCACHE                          ), // output
    .ARPROT                   (S_AXI_ACP_ARPROT                           ), // output
    .ARVALID                  (S_AXI_ACP_ARVALID                              ), //output
    .ARREADY                  (S_AXI_ACP_ARREADY                              ), // input
    .ARUSER                   (S_AXI_ACP_ARUSER                              ), // input
    .RID                      (S_AXI_ACP_RID), // input
    .RDATA                    (S_AXI_ACP_RDATA                           ), // input
    .RRESP                    (S_AXI_ACP_RRESP                            ), // input
    .RLAST                    (S_AXI_ACP_RLAST                                ), // input
    .RVALID                   (S_AXI_ACP_RVALID                               ), // input
    .RREADY                   (S_AXI_ACP_RREADY                               )  //output

);

axi_master_du #(
    .IW(IW_CH3_S),
    .AW(AW_CH3_S),
    .BW(BW_CH3_S),
    .DW(AL_S_AXI_HP0_DATA_WIDTH)
)  U_axi_master_du_hp0(
    .CLK                      (aclk), // input
    .RSTN                     (aresetn), // input

    .AWID                     (S_AXI_HP0_AWID[IW_CH3_S-1:0]                           ), // output
    .AWADDR                   (S_AXI_HP0_AWADDR                        ), // output
    .AWLEN                    (S_AXI_HP0_AWLEN                            ), // output
    .AWSIZE                   (S_AXI_HP0_AWSIZE                           ), // output
    .AWBURST                  (S_AXI_HP0_AWBURST                          ), // output
    .AWLOCK                   (S_AXI_HP0_AWLOCK                               ), //output
    .AWCACHE                  (S_AXI_HP0_AWCACHE                          ), // output
    .AWPROT                   (S_AXI_HP0_AWPROT                           ), // output
    .AWQOS                    (S_AXI_HP0_AWQOS                           ), // output
    .AWVALID                  (S_AXI_HP0_AWVALID                              ), //output
    .AWREADY                  (S_AXI_HP0_AWREADY                              ), // input
    .WDATA                    (S_AXI_HP0_WDATA                           ), // output
    .WSTRB                    (S_AXI_HP0_WSTRB                            ), // output
    .WLAST                    (S_AXI_HP0_WLAST                                ), //output
    .WVALID                   (S_AXI_HP0_WVALID                               ), //output
    .WREADY                   (S_AXI_HP0_WREADY                               ), // input
    .BID                      (S_AXI_HP0_BID), // input
    .BRESP                    (S_AXI_HP0_BRESP                            ), // input
    .BVALID                   (S_AXI_HP0_BVALID                               ), // input
    .BREADY                   (S_AXI_HP0_BREADY                               ), //output
    .AWUSER                   (),
    .ARUSER                   (),
    .ARID                     (S_AXI_HP0_ARID[IW_CH3_S-1:0]                           ), // output
    .ARADDR                   (S_AXI_HP0_ARADDR                        ), // output
    .ARLEN                    (S_AXI_HP0_ARLEN                            ), // output
    .ARSIZE                   (S_AXI_HP0_ARSIZE                           ), // output
    .ARBURST                  (S_AXI_HP0_ARBURST                          ), // output
    .ARLOCK                   (S_AXI_HP0_ARLOCK                               ), //output
    .ARCACHE                  (S_AXI_HP0_ARCACHE                          ), // output
    .ARPROT                   (S_AXI_HP0_ARPROT                           ), // output
    .ARQOS                    (S_AXI_HP0_ARQOS                           ), // output
    .ARVALID                  (S_AXI_HP0_ARVALID                              ), //output
    .ARREADY                  (S_AXI_HP0_ARREADY                              ), // input
    .RID                      (S_AXI_HP0_RID), // input
    .RDATA                    (S_AXI_HP0_RDATA                           ), // input
    .RRESP                    (S_AXI_HP0_RRESP                            ), // input
    .RLAST                    (S_AXI_HP0_RLAST                                ), // input
    .RVALID                   (S_AXI_HP0_RVALID                               ), // input
    .RREADY                   (S_AXI_HP0_RREADY                               )  //output

);

axi_master_du #(
    .IW(IW_CH4_S),
    .AW(AW_CH4_S),
    .BW(BW_CH4_S),
    .DW(AL_S_AXI_HP1_DATA_WIDTH)
)  U_axi_master_du_hp1(
    .CLK                      (aclk), // input
    .RSTN                     (aresetn), // input

    .AWID                     (S_AXI_HP1_AWID[IW_CH4_S-1:0]                           ), // output
    .AWADDR                   (S_AXI_HP1_AWADDR                        ), // output
    .AWLEN                    (S_AXI_HP1_AWLEN                            ), // output
    .AWSIZE                   (S_AXI_HP1_AWSIZE                           ), // output
    .AWBURST                  (S_AXI_HP1_AWBURST                          ), // output
    .AWLOCK                   (S_AXI_HP1_AWLOCK                               ), //output
    .AWCACHE                  (S_AXI_HP1_AWCACHE                          ), // output
    .AWPROT                   (S_AXI_HP1_AWPROT                           ), // output
    .AWQOS                    (S_AXI_HP1_AWQOS                           ), // output
    .AWVALID                  (S_AXI_HP1_AWVALID                              ), //output
    .AWREADY                  (S_AXI_HP1_AWREADY                              ), // input
    .WDATA                    (S_AXI_HP1_WDATA                           ), // output
    .WSTRB                    (S_AXI_HP1_WSTRB                            ), // output
    .WLAST                    (S_AXI_HP1_WLAST                                ), //output
    .WVALID                   (S_AXI_HP1_WVALID                               ), //output
    .WREADY                   (S_AXI_HP1_WREADY                               ), // input
    .BID                      (S_AXI_HP1_BID), // input
    .BRESP                    (S_AXI_HP1_BRESP                            ), // input
    .BVALID                   (S_AXI_HP1_BVALID                               ), // input
    .BREADY                   (S_AXI_HP1_BREADY                               ), //output
    .AWUSER                   (),
    .ARUSER                   (),
    .ARID                     (S_AXI_HP1_ARID[IW_CH4_S-1:0]                           ), // output
    .ARADDR                   (S_AXI_HP1_ARADDR                        ), // output
    .ARLEN                    (S_AXI_HP1_ARLEN                            ), // output
    .ARSIZE                   (S_AXI_HP1_ARSIZE                           ), // output
    .ARBURST                  (S_AXI_HP1_ARBURST                          ), // output
    .ARLOCK                   (S_AXI_HP1_ARLOCK                               ), //output
    .ARCACHE                  (S_AXI_HP1_ARCACHE                          ), // output
    .ARPROT                   (S_AXI_HP1_ARPROT                           ), // output
    .ARQOS                    (S_AXI_HP1_ARQOS                           ), // output
    .ARVALID                  (S_AXI_HP1_ARVALID                              ), //output
    .ARREADY                  (S_AXI_HP1_ARREADY                              ), // input
    .RID                      (S_AXI_HP1_RID), // input
    .RDATA                    (S_AXI_HP1_RDATA                           ), // input
    .RRESP                    (S_AXI_HP1_RRESP                            ), // input
    .RLAST                    (S_AXI_HP1_RLAST                                ), // input
    .RVALID                   (S_AXI_HP1_RVALID                               ), // input
    .RREADY                   (S_AXI_HP1_RREADY                               )  //output

);

ahb_slave_du #(
    .ADDR_WDT(33)
)
U_ahb_slave_du(
    .i_hclk(FAHB_HCLK_GLB),
    .i_hreset_n(FAHB_HRESETN),
    .i_hburst(FAHB_HBURST),
    .i_htrans(FAHB_HTRANS),
    .i_hwdata(FAHB_HWDATA),
    .i_hsel(FAHB_HSEL),
    .i_haddr(FAHB_HADDR),
    .i_hwrite(FAHB_HWRITE),
    .i_hsize(FAHB_HSIZE),
    .i_hprot(FAHB_HPROT),
    .o_hrdata(FAHB_HRDATA),
    .i_hready(FAHB_HREADY),
    .o_fbhclk(FAHB_FBHCLK),
    .o_hready(FAHB_HREADYOUT),
    .o_hresp(FAHB_HRESP)

);

ps_bfm_top #(
    .AL_MEM_CLK_FREQ (400),
    .AL_FAHB_HCLK_FREQ (100),
	.AL_FCLK_CLK0_FREQ (50),
    .AL_FCLK_CLK1_FREQ (50),
    .AL_FCLK_CLK2_FREQ (50),
    .AL_FCLK_CLK3_FREQ (50),
    .AL_S_AXI_HP0_DATA_WIDTH (AL_S_AXI_HP0_DATA_WIDTH),
    .AL_S_AXI_HP1_DATA_WIDTH (AL_S_AXI_HP1_DATA_WIDTH),
    .AL_M_AXI_GP0_ENABLE (1),
    .AL_M_AXI_GP1_ENABLE (1),
    .AL_S_AXI_GP0_ENABLE (1),
    .AL_S_AXI_GP1_ENABLE (1),
    .AL_S_AXI_HP0_ENABLE (1),
    .AL_S_AXI_HP1_ENABLE (1),
    .AL_S_AXI_ACP_ENABLE (1),
    .AL_M_FAHB_ENABLE (1)
) U_PS_BFM(/*autoinst*/
    .master_gp0_axi_arvalid         (M_AXI_GP0_ARVALID),
    .master_gp0_axi_awvalid         (M_AXI_GP0_AWVALID),
    .master_gp0_axi_bready          (M_AXI_GP0_BREADY),
    .master_gp0_axi_rready          (M_AXI_GP0_RREADY),
    .master_gp0_axi_wlast           (M_AXI_GP0_WLAST),
    .master_gp0_axi_wvalid          (M_AXI_GP0_WVALID),
    .master_gp0_axi_arid            (M_AXI_GP0_ARID),
    .master_gp0_axi_awid            (M_AXI_GP0_AWID),
    .master_gp0_axi_arburst         (M_AXI_GP0_ARBURST),
    .master_gp0_axi_arlock          (M_AXI_GP0_ARLOCK),
    .master_gp0_axi_arsize          (M_AXI_GP0_ARSIZE),
    .master_gp0_axi_awburst         (M_AXI_GP0_AWBURST),
    .master_gp0_axi_awlock          (M_AXI_GP0_AWLOCK),
    .master_gp0_axi_awsize          (M_AXI_GP0_AWSIZE),
    .master_gp0_axi_arprot          (M_AXI_GP0_ARPROT),
    .master_gp0_axi_awprot          (M_AXI_GP0_AWPROT),
    .master_gp0_axi_araddr          (M_AXI_GP0_ARADDR),
    .master_gp0_axi_awaddr          (M_AXI_GP0_AWADDR),
    .master_gp0_axi_wdata           (M_AXI_GP0_WDATA),
    .master_gp0_axi_arcache         (M_AXI_GP0_ARCACHE),
    .master_gp0_axi_arlen           (M_AXI_GP0_ARLEN),
    .master_gp0_axi_awcache         (M_AXI_GP0_AWCACHE),
    .master_gp0_axi_awlen           (M_AXI_GP0_AWLEN),
    .master_gp0_axi_wstrb           (M_AXI_GP0_WSTRB),
    .master_gp0_axi_aclk            (M_AXI_GP0_ACLK),
    .master_gp0_axi_arready         (M_AXI_GP0_ARREADY),
    .master_gp0_axi_awready         (M_AXI_GP0_AWREADY),
    .master_gp0_axi_bvalid          (M_AXI_GP0_BVALID),
    .master_gp0_axi_rlast           (M_AXI_GP0_RLAST),
    .master_gp0_axi_rvalid          (M_AXI_GP0_RVALID),
    .master_gp0_axi_wready          (M_AXI_GP0_WREADY),
    .master_gp0_axi_bid             (M_AXI_GP0_BID),
    .master_gp0_axi_rid             (M_AXI_GP0_RID),
    .master_gp0_axi_bresp           (M_AXI_GP0_BRESP),
    .master_gp0_axi_rresp           (M_AXI_GP0_RRESP),
    .master_gp0_axi_rdata           (M_AXI_GP0_RDATA),
    
    .master_gp1_axi_arvalid         (M_AXI_GP1_ARVALID),
    .master_gp1_axi_awvalid         (M_AXI_GP1_AWVALID),
    .master_gp1_axi_bready          (M_AXI_GP1_BREADY),
    .master_gp1_axi_rready          (M_AXI_GP1_RREADY),
    .master_gp1_axi_wlast           (M_AXI_GP1_WLAST),
    .master_gp1_axi_wvalid          (M_AXI_GP1_WVALID),
    .master_gp1_axi_arid            (M_AXI_GP1_ARID),
    .master_gp1_axi_awid            (M_AXI_GP1_AWID),
    .master_gp1_axi_arburst         (M_AXI_GP1_ARBURST),
    .master_gp1_axi_arlock          (M_AXI_GP1_ARLOCK),
    .master_gp1_axi_arsize          (M_AXI_GP1_ARSIZE),
    .master_gp1_axi_awburst         (M_AXI_GP1_AWBURST),
    .master_gp1_axi_awlock          (M_AXI_GP1_AWLOCK),
    .master_gp1_axi_awsize          (M_AXI_GP1_AWSIZE),
    .master_gp1_axi_arprot          (M_AXI_GP1_ARPROT),
    .master_gp1_axi_awprot          (M_AXI_GP1_AWPROT),
    .master_gp1_axi_araddr          (M_AXI_GP1_ARADDR),
    .master_gp1_axi_awaddr          (M_AXI_GP1_AWADDR),
    .master_gp1_axi_wdata           (M_AXI_GP1_WDATA),
    .master_gp1_axi_arcache         (M_AXI_GP1_ARCACHE),
    .master_gp1_axi_arlen           (M_AXI_GP1_ARLEN),
    .master_gp1_axi_awcache         (M_AXI_GP1_AWCACHE),
    .master_gp1_axi_awlen           (M_AXI_GP1_AWLEN),
    .master_gp1_axi_wstrb           (M_AXI_GP1_WSTRB),
    .master_gp1_axi_aclk            (M_AXI_GP1_ACLK),
    .master_gp1_axi_arready         (M_AXI_GP1_ARREADY),
    .master_gp1_axi_awready         (M_AXI_GP1_AWREADY),
    .master_gp1_axi_bvalid          (M_AXI_GP1_BVALID),
    .master_gp1_axi_rlast           (M_AXI_GP1_RLAST),
    .master_gp1_axi_rvalid          (M_AXI_GP1_RVALID),
    .master_gp1_axi_wready          (M_AXI_GP1_WREADY),
    .master_gp1_axi_bid             (M_AXI_GP1_BID),
    .master_gp1_axi_rid             (M_AXI_GP1_RID),
    .master_gp1_axi_bresp           (M_AXI_GP1_BRESP),
    .master_gp1_axi_rresp           (M_AXI_GP1_RRESP),
    .master_gp1_axi_rdata           (M_AXI_GP1_RDATA),

    .slave_gp0_axi_arready          (S_AXI_GP0_ARREADY),
    .slave_gp0_axi_awready          (S_AXI_GP0_AWREADY),
    .slave_gp0_axi_bvalid           (S_AXI_GP0_BVALID),
    .slave_gp0_axi_rlast            (S_AXI_GP0_RLAST),
    .slave_gp0_axi_rvalid           (S_AXI_GP0_RVALID),
    .slave_gp0_axi_wready           (S_AXI_GP0_WREADY),
    .slave_gp0_axi_bresp            (S_AXI_GP0_BRESP),
    .slave_gp0_axi_rresp            (S_AXI_GP0_RRESP),
    .slave_gp0_axi_rdata            (S_AXI_GP0_RDATA),
    .slave_gp0_axi_bid              (S_AXI_GP0_BID),
    .slave_gp0_axi_rid              (S_AXI_GP0_RID),
    .slave_gp0_axi_aclk             (S_AXI_GP0_ACLK),
    .slave_gp0_axi_arvalid          (S_AXI_GP0_ARVALID),
    .slave_gp0_axi_awvalid          (S_AXI_GP0_AWVALID),
    .slave_gp0_axi_bready           (S_AXI_GP0_BREADY),
    .slave_gp0_axi_rready           (S_AXI_GP0_RREADY),
    .slave_gp0_axi_wlast            (S_AXI_GP0_WLAST),
    .slave_gp0_axi_wvalid           (S_AXI_GP0_WVALID),
    .slave_gp0_axi_arburst          (S_AXI_GP0_ARBURST),
    .slave_gp0_axi_arlock           (S_AXI_GP0_ARLOCK),
    .slave_gp0_axi_arsize           (S_AXI_GP0_ARSIZE),
    .slave_gp0_axi_awburst          (S_AXI_GP0_AWBURST),
    .slave_gp0_axi_awlock           (S_AXI_GP0_AWLOCK),
    .slave_gp0_axi_awsize           (S_AXI_GP0_AWSIZE),
    .slave_gp0_axi_arprot           (S_AXI_GP0_ARPROT),
    .slave_gp0_axi_awprot           (S_AXI_GP0_AWPROT),
    .slave_gp0_axi_araddr           (S_AXI_GP0_ARADDR),
    .slave_gp0_axi_awaddr           (S_AXI_GP0_AWADDR),
    .slave_gp0_axi_wdata            (S_AXI_GP0_WDATA),
    .slave_gp0_axi_arcache          (S_AXI_GP0_ARCACHE),
    .slave_gp0_axi_arlen            (S_AXI_GP0_ARLEN),
    .slave_gp0_axi_awcache          (S_AXI_GP0_AWCACHE),
    .slave_gp0_axi_awlen            (S_AXI_GP0_AWLEN),
    .slave_gp0_axi_wstrb            (S_AXI_GP0_WSTRB),
    .slave_gp0_axi_arid             (S_AXI_GP0_ARID),
    .slave_gp0_axi_awid             (S_AXI_GP0_AWID),

    .slave_gp1_axi_arready          (S_AXI_GP1_ARREADY),
    .slave_gp1_axi_awready          (S_AXI_GP1_AWREADY),
    .slave_gp1_axi_bvalid           (S_AXI_GP1_BVALID),
    .slave_gp1_axi_rlast            (S_AXI_GP1_RLAST),
    .slave_gp1_axi_rvalid           (S_AXI_GP1_RVALID),
    .slave_gp1_axi_wready           (S_AXI_GP1_WREADY),
    .slave_gp1_axi_bresp            (S_AXI_GP1_BRESP),
    .slave_gp1_axi_rresp            (S_AXI_GP1_RRESP),
    .slave_gp1_axi_rdata            (S_AXI_GP1_RDATA),
    .slave_gp1_axi_bid              (S_AXI_GP1_BID),
    .slave_gp1_axi_rid              (S_AXI_GP1_RID),
    .slave_gp1_axi_aclk             (S_AXI_GP1_ACLK),
    .slave_gp1_axi_arvalid          (S_AXI_GP1_ARVALID),
    .slave_gp1_axi_awvalid          (S_AXI_GP1_AWVALID),
    .slave_gp1_axi_bready           (S_AXI_GP1_BREADY),
    .slave_gp1_axi_rready           (S_AXI_GP1_RREADY),
    .slave_gp1_axi_wlast            (S_AXI_GP1_WLAST),
    .slave_gp1_axi_wvalid           (S_AXI_GP1_WVALID),
    .slave_gp1_axi_arburst          (S_AXI_GP1_ARBURST),
    .slave_gp1_axi_arlock           (S_AXI_GP1_ARLOCK),
    .slave_gp1_axi_arsize           (S_AXI_GP1_ARSIZE),
    .slave_gp1_axi_awburst          (S_AXI_GP1_AWBURST),
    .slave_gp1_axi_awlock           (S_AXI_GP1_AWLOCK),
    .slave_gp1_axi_awsize           (S_AXI_GP1_AWSIZE),
    .slave_gp1_axi_arprot           (S_AXI_GP1_ARPROT),
    .slave_gp1_axi_awprot           (S_AXI_GP1_AWPROT),
    .slave_gp1_axi_araddr           (S_AXI_GP1_ARADDR),
    .slave_gp1_axi_awaddr           (S_AXI_GP1_AWADDR),
    .slave_gp1_axi_wdata            (S_AXI_GP1_WDATA),
    .slave_gp1_axi_arcache          (S_AXI_GP1_ARCACHE),
    .slave_gp1_axi_arlen            (S_AXI_GP1_ARLEN),
    .slave_gp1_axi_awcache          (S_AXI_GP1_AWCACHE),
    .slave_gp1_axi_awlen            (S_AXI_GP1_AWLEN),
    .slave_gp1_axi_wstrb            (S_AXI_GP1_WSTRB),
    .slave_gp1_axi_arid             (S_AXI_GP1_ARID),
    .slave_gp1_axi_awid             (S_AXI_GP1_AWID),

    .slave_acp_awready              (S_AXI_ACP_AWREADY),
    .slave_acp_arready              (S_AXI_ACP_ARREADY),
    .slave_acp_bvalid               (S_AXI_ACP_BVALID),
    .slave_acp_rlast                (S_AXI_ACP_RLAST),
    .slave_acp_rvalid               (S_AXI_ACP_RVALID),
    .slave_acp_wready               (S_AXI_ACP_WREADY),
    .slave_acp_bresp                (S_AXI_ACP_BRESP),
    .slave_acp_rresp                (S_AXI_ACP_RRESP),
    .slave_acp_bid                  (S_AXI_ACP_BID),
    .slave_acp_rid                  (S_AXI_ACP_RID),
    .slave_acp_rdata                (S_AXI_ACP_RDATA),
    .slave_acp_aclk_in              (S_AXI_ACP_ACLK),
    .slave_acp_arvalid              (S_AXI_ACP_ARVALID),
    .slave_acp_awvalid              (S_AXI_ACP_AWVALID),
    .slave_acp_bready               (S_AXI_ACP_BREADY),
    .slave_acp_rready               (S_AXI_ACP_RREADY),
    .slave_acp_wlast                (S_AXI_ACP_WLAST),
    .slave_acp_wvalid               (S_AXI_ACP_WVALID),
    .slave_acp_arid                 (S_AXI_ACP_ARID),
    .slave_acp_arprot               (S_AXI_ACP_ARPROT),
    .slave_acp_awid                 (S_AXI_ACP_AWID),
    .slave_acp_awprot               (S_AXI_ACP_AWPROT),
    .slave_acp_araddr               (S_AXI_ACP_ARADDR),
    .slave_acp_awaddr               (S_AXI_ACP_AWADDR),
    .slave_acp_arcache              (S_AXI_ACP_ARCACHE),
    .slave_acp_arlen                (S_AXI_ACP_ARLEN),
    .slave_acp_awcache              (S_AXI_ACP_AWCACHE),
    .slave_acp_awlen                (S_AXI_ACP_AWLEN),
    .slave_acp_arusers              (S_AXI_ACP_ARUSER),
    .slave_acp_awusers              (S_AXI_ACP_AWUSER),
    .slave_acp_wdata                (S_AXI_ACP_WDATA),
    .slave_acp_wstrb                (S_AXI_ACP_WSTRB),

    .slave_hp0_axi_arready          (S_AXI_HP0_ARREADY),
    .slave_hp0_axi_awready          (S_AXI_HP0_AWREADY),
    .slave_hp0_axi_bvalid           (S_AXI_HP0_BVALID),
    .slave_hp0_axi_rlast            (S_AXI_HP0_RLAST),
    .slave_hp0_axi_rvalid           (S_AXI_HP0_RVALID),
    .slave_hp0_axi_wready           (S_AXI_HP0_WREADY),
    .slave_hp0_axi_bresp            (S_AXI_HP0_BRESP),
    .slave_hp0_axi_rresp            (S_AXI_HP0_RRESP),
    .slave_hp0_axi_bid              (S_AXI_HP0_BID),
    .slave_hp0_axi_rid              (S_AXI_HP0_RID),
    .slave_hp0_axi_rdata            (S_AXI_HP0_RDATA),
    .slave_hp0_axi_aclk             (S_AXI_HP0_ACLK),
    .slave_hp0_axi_arvalid          (S_AXI_HP0_ARVALID),
    .slave_hp0_axi_awvalid          (S_AXI_HP0_AWVALID),
    .slave_hp0_axi_bready           (S_AXI_HP0_BREADY),
    .slave_hp0_axi_rready           (S_AXI_HP0_RREADY),
    .slave_hp0_axi_wlast            (S_AXI_HP0_WLAST),
    .slave_hp0_axi_wvalid           (S_AXI_HP0_WVALID),
    .slave_hp0_axi_arburst          (S_AXI_HP0_ARBURST),
    .slave_hp0_axi_arlock           (S_AXI_HP0_ARLOCK),
    .slave_hp0_axi_arsize           (S_AXI_HP0_ARSIZE),
    .slave_hp0_axi_awburst          (S_AXI_HP0_AWBURST),
    .slave_hp0_axi_awlock           (S_AXI_HP0_AWLOCK),
    .slave_hp0_axi_awsize           (S_AXI_HP0_AWSIZE),
    .slave_hp0_axi_arprot           (S_AXI_HP0_ARPROT),
    .slave_hp0_axi_awprot           (S_AXI_HP0_AWPROT),
    .slave_hp0_axi_araddr           (S_AXI_HP0_ARADDR),
    .slave_hp0_axi_awaddr           (S_AXI_HP0_AWADDR),
    .slave_hp0_axi_arcache          (S_AXI_HP0_ARCACHE),
    .slave_hp0_axi_arlen            (S_AXI_HP0_ARLEN),
    .slave_hp0_axi_arqos            (S_AXI_HP0_ARQOS),
    .slave_hp0_axi_awcache          (S_AXI_HP0_AWCACHE),
    .slave_hp0_axi_awlen            (S_AXI_HP0_AWLEN),
    .slave_hp0_axi_awqos            (S_AXI_HP0_AWQOS),
    .slave_hp0_axi_arid             (S_AXI_HP0_ARID),
    .slave_hp0_axi_awid             (S_AXI_HP0_AWID),
    .slave_hp0_axi_wdata            (S_AXI_HP0_WDATA),
    .slave_hp0_axi_wstrb            (S_AXI_HP0_WSTRB),

    .slave_hp1_axi_arready          (S_AXI_HP1_ARREADY),
    .slave_hp1_axi_awready          (S_AXI_HP1_AWREADY),
    .slave_hp1_axi_bvalid           (S_AXI_HP1_BVALID),
    .slave_hp1_axi_rlast            (S_AXI_HP1_RLAST),
    .slave_hp1_axi_rvalid           (S_AXI_HP1_RVALID),
    .slave_hp1_axi_wready           (S_AXI_HP1_WREADY),
    .slave_hp1_axi_bresp            (S_AXI_HP1_BRESP),
    .slave_hp1_axi_rresp            (S_AXI_HP1_RRESP),
    .slave_hp1_axi_bid              (S_AXI_HP1_BID),
    .slave_hp1_axi_rid              (S_AXI_HP1_RID),
    .slave_hp1_axi_rdata            (S_AXI_HP1_RDATA),
    .slave_hp1_axi_aclk             (S_AXI_HP1_ACLK),
    .slave_hp1_axi_arvalid          (S_AXI_HP1_ARVALID),
    .slave_hp1_axi_awvalid          (S_AXI_HP1_AWVALID),
    .slave_hp1_axi_bready           (S_AXI_HP1_BREADY),
    .slave_hp1_axi_rready           (S_AXI_HP1_RREADY),
    .slave_hp1_axi_wlast            (S_AXI_HP1_WLAST),
    .slave_hp1_axi_wvalid           (S_AXI_HP1_WVALID),
    .slave_hp1_axi_arburst          (S_AXI_HP1_ARBURST),
    .slave_hp1_axi_arlock           (S_AXI_HP1_ARLOCK),
    .slave_hp1_axi_arsize           (S_AXI_HP1_ARSIZE),
    .slave_hp1_axi_awburst          (S_AXI_HP1_AWBURST),
    .slave_hp1_axi_awlock           (S_AXI_HP1_AWLOCK),
    .slave_hp1_axi_awsize           (S_AXI_HP1_AWSIZE),
    .slave_hp1_axi_arprot           (S_AXI_HP1_ARPROT),
    .slave_hp1_axi_awprot           (S_AXI_HP1_AWPROT),
    .slave_hp1_axi_araddr           (S_AXI_HP1_ARADDR),
    .slave_hp1_axi_awaddr           (S_AXI_HP1_AWADDR),
    .slave_hp1_axi_arcache          (S_AXI_HP1_ARCACHE),
    .slave_hp1_axi_arlen            (S_AXI_HP1_ARLEN),
    .slave_hp1_axi_arqos            (S_AXI_HP1_ARQOS),
    .slave_hp1_axi_awcache          (S_AXI_HP1_AWCACHE),
    .slave_hp1_axi_awlen            (S_AXI_HP1_AWLEN),
    .slave_hp1_axi_awqos            (S_AXI_HP1_AWQOS),
    .slave_hp1_axi_arid             (S_AXI_HP1_ARID),
    .slave_hp1_axi_awid             (S_AXI_HP1_AWID),
    .slave_hp1_axi_wdata            (S_AXI_HP1_WDATA),
    .slave_hp1_axi_wstrb            (S_AXI_HP1_WSTRB),

    .master_fahb_clk_glb            (FAHB_HCLK_GLB),
    .master_fahb_clk_lcl            (FAHB_HCLK_LCL),
    .master_fahb_hresp              (FAHB_HRESP),
    .master_fahb_hrdata             (FAHB_HRDATA),
    .master_fahb_hsel               (FAHB_HSEL),
    .master_fahb_haddr              (FAHB_HADDR),
    .master_fahb_hsize              (FAHB_HSIZE),
    .master_fahb_hwrite             (FAHB_HWRITE),
    .master_fahb_hburst             (FAHB_HBURST),
    .master_fahb_hprot              (FAHB_HPROT),
    .master_fahb_htrans             (FAHB_HTRANS),
    .master_fahb_hready             (FAHB_HREADY),
    .pl2ps_fahb_fbclk               (FAHB_FBHCLK),
    .master_fahb_hreadyout          (FAHB_HREADYOUT),
    .master_fahb_hwdata             (FAHB_HWDATA),
    .p2f_clk3                       (FCLK_CLK3),
    .p2f_clk2                       (FCLK_CLK2),
    .p2f_clk1                       (FCLK_CLK1),
    .p2f_clk0                       (FCLK_CLK0),
    .p2f_rst3_n                     (FCLK_RESET3_N),
    .p2f_rst2_n                     (FCLK_RESET2_N),
    .p2f_rst1_n                     (FCLK_RESET1_N),
    .p2f_rst0_n                     (FCLK_RESET0_N),

    .f2p_irq                        (IRQ_F2P                          ), // input 
    .ps_srstb                       (sresetn), // input 
    .ps_clk                         (PS_CLK                                          ), // input 
    .ps_porb                        (aresetn)
    );

//////////////////////////////////////////////////////////////////////
//init

always #5  aclk =~aclk ; //100M
assign PS_CLK = aclk ; //100M
assign FAHB_HRESETN = aresetn;
assign M_AXI_GP0_ACLK = aclk;
assign M_AXI_GP1_ACLK = aclk;

assign S_AXI_GP0_ACLK = aclk;
assign S_AXI_GP1_ACLK = aclk;
assign S_AXI_ACP_ACLK = aclk;
assign S_AXI_HP0_ACLK = aclk;
assign S_AXI_HP1_ACLK = aclk;

//clk/reset start
initial begin

#10;
aclk =0;
aresetn =0;
sresetn =0;


#100;
aresetn =0;
sresetn =0;
#100;
aresetn =1;
sresetn =1;
#100;

end

//////////////////////////////////////////////////////////////////////
//test function
wire hp0_dw, hp1_dw;
assign hp0_dw = AL_S_AXI_HP0_DATA_WIDTH == 32 ? 1'b0 : 1'b1;
assign hp1_dw = AL_S_AXI_HP1_DATA_WIDTH == 32 ? 1'b0 : 1'b1;
`include "ps_bfm_customer_master_test.v"
`include "ps_bfm_customer_slave_test.v"
`include "ps_bfm_customer_fahb_master_test.v"



initial 
begin
    #20000;

    #1000;
    ps_bfm_master_api_test();
    ps_bfm_slave_test_unit(hp0_dw, hp1_dw);

    fahb_master_test_unit();
    #40000;
    $finish;

end

endmodule

