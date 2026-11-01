task automatic ps_bfm_master_api_test();
reg  [33-1:0] waddr;
reg  [32-1:0] wdata_32bit [0:15];
reg  [16*32-1:0] wdata;
reg  [32-1:0] rdata_32bit [0:15];
reg  [33-1:0] raddr;
reg  [1024-1:0] rdata;
reg [1:0] response_test;
reg [3:0] len;
reg [2:0] siz;
reg [1:0] burst;
reg [1:0] lck;
reg [3:0] cache;
reg[2:0] prot;
integer i;
begin
    $display("MASTER TEST START! ");

        //$display("GP0 TEST START! ");
        wdata[0*32+:32] = 32'h00000000;
        wdata[1*32+:32] = 32'h11111111;
        wdata[2*32+:32] = 32'h22222222;
        wdata[3*32+:32] = 32'h33333333;
        wdata[4*32+:32] = 32'h44444444;
        wdata[5*32+:32] = 32'h55555555;
        wdata[6*32+:32] = 32'h66666666;
        wdata[7*32+:32] = 32'h77777777;
        wdata[8*32+:32] = 32'h88888888;
        wdata[9*32+:32] = 32'h99999999;
        wdata[10*32+:32] = 32'hAAAA_AAAA;
        wdata[11*32+:32] = 32'hBBBB_BBBB;
        wdata[12*32+:32] = 32'hCCCC_CCCC;
        wdata[13*32+:32] = 32'hDDDD_DDDD;
        wdata[14*32+:32] = 32'hEEEE_EEEE;
        wdata[15*32+:32] = 32'hFFFF_FFFF;

        waddr = 33'h0_8000_0000; 
        U_PS_BFM.M_AXI_GP0.write_data(waddr,4*16,wdata,response_test);

        #1000;
        raddr = 33'h0_8000_0000;
        U_PS_BFM.M_AXI_GP0.read_data(raddr,4*16, rdata, response_test);

         if (wdata == rdata) begin
             $display("GP0 BURST TYPE = INCR, BURST LEN=16, WRITE AND READ  PASS! ");
        end
        else begin
            $display("GP0 BURST TYPE = INCR, BURST LEN=16,  WRITE AND READ ERROR! ");
        end
        //$display("GP0 TEST END! ");

        //$display("GP1 TEST START! ");
        wdata[0*32+:32] = 32'h00000000;
        wdata[1*32+:32] = 32'h11111111;
        wdata[2*32+:32] = 32'h22222222;
        wdata[3*32+:32] = 32'h33333333;
        wdata[4*32+:32] = 32'h44444444;
        wdata[5*32+:32] = 32'h55555555;
        wdata[6*32+:32] = 32'h66666666;
        wdata[7*32+:32] = 32'h77777777;
        wdata[8*32+:32] = 32'h88888888;
        wdata[9*32+:32] = 32'h99999999;
        wdata[10*32+:32] = 32'hAAAA_AAAA;
        wdata[11*32+:32] = 32'hBBBB_BBBB;
        wdata[12*32+:32] = 32'hCCCC_CCCC;
        wdata[13*32+:32] = 32'hDDDD_DDDD;
        wdata[14*32+:32] = 32'hEEEE_EEEE;
        wdata[15*32+:32] = 32'hFFFF_FFFF;

        waddr = 33'h0_A000_0000;
        U_PS_BFM.M_AXI_GP1.write_data(waddr,4*16,wdata,response_test);

        #1000;
        raddr = 33'h0_A000_0000;
        U_PS_BFM.M_AXI_GP1.read_data(raddr,4*16, rdata, response_test);

         if (wdata == rdata) begin
             $display("GP1 BURST TYPE = INCR, BURST LEN=16,  WRITE AND READ  PASS! ");
        end
        else begin
            $display("GP1 BURST TYPE = INCR, BURST LEN=16,  WRITE AND READ ERROR! ");
        end
        //$display("GP1 TEST END! ");

    $display("MASTER TEST END! ");
end
endtask




