task automatic ps_bfm_slave_test_unit(input hp0_dw, input hp1_dw);

        reg  [33-1:0] waddr_gp0;
        reg  [33-1:0] waddr_gp1;
        reg  [33-1:0] waddr_acp;
        reg  [33-1:0] waddr_hp0;
        reg  [33-1:0] waddr_hp1;

        reg  [33*8-1:0] addr;

        reg  [16*32*8-1:0] wdata_32bit;
        reg  [16*4*8-1:0] wstrb_32bit;
        reg  [16*64*8-1:0] wdata_64bit;
        reg  [16*8*8-1:0] wstrb_64bit;

        reg  [33-1:0] raddr_gp0;
        reg  [33-1:0] raddr_gp1;
        reg  [33-1:0] raddr_acp;
        reg  [33-1:0] raddr_hp0;
        reg  [33-1:0] raddr_hp1;

        reg  [32-1:0] rdata_32bit;
        reg  [64-1:0] rdata_64bit;

        reg  [16*32-1:0] wdata_32bit_burst_gp0;
        reg  [16*32-1:0] wdata_32bit_burst_gp1;
        reg  [16*4-1:0] wstrb_32bit_burst;

        reg  [16*64-1:0] wdata_64bit_burst_acp;
        reg  [16*64-1:0] wdata_64bit_burst_hp0;
        reg  [16*64-1:0] wdata_64bit_burst_hp1;
        reg  [16*8-1:0] wstrb_64bit_burst;

        reg [1:0] response_test;
        reg [3:0] len_gp0;
        reg [3:0] len_gp1;
        reg [2:0] len_acp;
        reg [3:0] len_hp0;
        reg [3:0] len_hp1;

        reg [3:0] qos_gp0;
        reg [3:0] qos_gp1;
        reg [3:0] qos_acp;
        reg [3:0] qos_hp0;
        reg [3:0] qos_hp1;

        reg [31:0] id;
        reg       lock;
        reg [2:0] prot;
        reg [3:0] cache;

        reg [1:0] burst;
        reg [2:0] bfm_type;
        reg port;

        integer i;
begin

        wdata_32bit_burst_gp0[0*32+:32] = 32'h11111111;
        wdata_32bit_burst_gp0[1*32+:32] = 32'h22222222;
        wdata_32bit_burst_gp0[2*32+:32] = 32'h33333333;
        wdata_32bit_burst_gp0[3*32+:32] = 32'h44444444;
        wdata_32bit_burst_gp0[4*32+:32] = 32'h55555555;
        wdata_32bit_burst_gp0[5*32+:32] = 32'h66666666;
        wdata_32bit_burst_gp0[6*32+:32] = 32'h77777777;
        wdata_32bit_burst_gp0[7*32+:32] = 32'h88888888;
        wdata_32bit_burst_gp0[8*32+:32] = 32'h99999999;
        wdata_32bit_burst_gp0[9*32+:32] = 32'haaaaaaaa;
        wdata_32bit_burst_gp0[10*32+:32] = 32'hbbbbbbbb;
        wdata_32bit_burst_gp0[11*32+:32] = 32'hcccccccc;
        wdata_32bit_burst_gp0[12*32+:32] = 32'hdddddddd;
        wdata_32bit_burst_gp0[13*32+:32] = 32'heeeeeeee;
        wdata_32bit_burst_gp0[14*32+:32] = 32'hffffffff;
        wdata_32bit_burst_gp0[15*32+:32] = 32'h5a5a5a5a;

        wdata_32bit_burst_gp1[0*32+:32] = 32'h21111112;
        wdata_32bit_burst_gp1[1*32+:32] = 32'h32222223;
        wdata_32bit_burst_gp1[2*32+:32] = 32'h43333334;
        wdata_32bit_burst_gp1[3*32+:32] = 32'h54444445;
        wdata_32bit_burst_gp1[4*32+:32] = 32'h65555556;
        wdata_32bit_burst_gp1[5*32+:32] = 32'h76666667;
        wdata_32bit_burst_gp1[6*32+:32] = 32'h87777778;
        wdata_32bit_burst_gp1[7*32+:32] = 32'h98888889;
        wdata_32bit_burst_gp1[8*32+:32] = 32'ha999999a;
        wdata_32bit_burst_gp1[9*32+:32] = 32'hbaaaaaab;
        wdata_32bit_burst_gp1[10*32+:32] = 32'hcbbbbbbc;
        wdata_32bit_burst_gp1[11*32+:32] = 32'hdccccccd;
        wdata_32bit_burst_gp1[12*32+:32] = 32'hedddddde;
        wdata_32bit_burst_gp1[13*32+:32] = 32'hfeeeeeef;
        wdata_32bit_burst_gp1[14*32+:32] = 32'h1ffffff1;
        wdata_32bit_burst_gp1[15*32+:32] = 32'h6a5a5a56;

        wstrb_32bit_burst[0*4+:4] = 4'hf;
        wstrb_32bit_burst[1*4+:4] = 4'hf;
        wstrb_32bit_burst[2*4+:4] = 4'hf;
        wstrb_32bit_burst[3*4+:4] = 4'hf;
        wstrb_32bit_burst[4*4+:4] = 4'hf;
        wstrb_32bit_burst[5*4+:4] = 4'hf;
        wstrb_32bit_burst[6*4+:4] = 4'hf;
        wstrb_32bit_burst[7*4+:4] = 4'hf;
        wstrb_32bit_burst[8*4+:4] = 4'hf;
        wstrb_32bit_burst[9*4+:4] = 4'hf;
        wstrb_32bit_burst[10*4+:4] = 4'hf;
        wstrb_32bit_burst[11*4+:4] = 4'hf;
        wstrb_32bit_burst[12*4+:4] = 4'hf;
        wstrb_32bit_burst[13*4+:4] = 4'hf;
        wstrb_32bit_burst[14*4+:4] = 4'hf;
        wstrb_32bit_burst[15*4+:4] = 4'hf;

        for (i=0; i<16;i=i+1) begin
            wdata_64bit_burst_acp[i*64+:64] = {wdata_32bit_burst_gp0[i*32+:32], wdata_32bit_burst_gp0[i*32+:32]};
            wdata_64bit_burst_hp0[i*64+:64] = {wdata_32bit_burst_gp0[i*32+:32], wdata_32bit_burst_gp1[i*32+:32]};
            wdata_64bit_burst_hp1[i*64+:64] = {wdata_32bit_burst_gp1[i*32+:32], wdata_32bit_burst_gp1[i*32+:32]};
        end

        wstrb_64bit_burst[0*8+:8] = 8'hff;
        wstrb_64bit_burst[1*8+:8] = 8'hff;
        wstrb_64bit_burst[2*8+:8] = 8'hff;
        wstrb_64bit_burst[3*8+:8] = 8'hff;
        wstrb_64bit_burst[4*8+:8] = 8'hff;
        wstrb_64bit_burst[5*8+:8] = 8'hff;
        wstrb_64bit_burst[6*8+:8] = 8'hff;
        wstrb_64bit_burst[7*8+:8] = 8'hff;
        wstrb_64bit_burst[8*8+:8] = 8'hff;
        wstrb_64bit_burst[9*8+:8] = 8'hff;
        wstrb_64bit_burst[10*8+:8] = 8'hff;
        wstrb_64bit_burst[11*8+:8] = 8'hff;
        wstrb_64bit_burst[12*8+:8] = 8'hff;
        wstrb_64bit_burst[13*8+:8] = 8'hff;
        wstrb_64bit_burst[14*8+:8] = 8'hff;
        wstrb_64bit_burst[15*8+:8] = 8'hff;

        len_gp0 = 4'hf;
        len_gp1 = 4'hf;
        len_acp = 3'h7;
        len_hp0 = 4'hf;
        len_hp1 = 4'hf;
        
        waddr_gp0 = 33'h0_0000_0000;
        raddr_gp0 = 33'h0_0000_0000;
        waddr_gp1 = 33'h0_3FFF_FF80;
        raddr_gp1 = 33'h0_3FFF_FF80;
        
        waddr_acp = 33'h1_0000_0000;
        raddr_acp = 33'h1_0000_0000;
        
        waddr_hp0 = 33'h1_1000_0000;
        raddr_hp0 = 33'h1_1000_0000;
        waddr_hp1 = 33'h1_9FFF_FF80;
        raddr_hp1 = 33'h1_9FFF_FF80;

        addr[0*33 +:33] = 33'h0_0000_0000;
        addr[1*33 +:33] = 33'h0_0001_0000;
        addr[2*33 +:33] = 33'h0_0002_0000;
        addr[3*33 +:33] = 33'h0_0003_0000;
        addr[4*33 +:33] = 33'h0_0004_0000;
        addr[5*33 +:33] = 33'h0_0005_0000;
        addr[6*33 +:33] = 33'h0_0006_0000;
        addr[7*33 +:33] = 33'h0_0007_0000;

        wdata_32bit[0*16*32+: 16*32] = wdata_32bit_burst_gp0;
        wdata_32bit[1*16*32+: 16*32] = wdata_32bit_burst_gp1;
        wdata_32bit[2*16*32+: 16*32] = wdata_32bit_burst_gp0;
        wdata_32bit[3*16*32+: 16*32] = wdata_32bit_burst_gp1;
        wdata_32bit[4*16*32+: 16*32] = wdata_32bit_burst_gp0;
        wdata_32bit[5*16*32+: 16*32] = wdata_32bit_burst_gp1;
        wdata_32bit[6*16*32+: 16*32] = wdata_32bit_burst_gp0;
        wdata_32bit[7*16*32+: 16*32] = wdata_32bit_burst_gp1;
        wstrb_32bit = -1;

        wdata_64bit[0*16*64*8+: 16*32*8] = wdata_32bit;
        wdata_64bit[1*16*32*8+: 16*32*8] = wdata_32bit;
        wstrb_64bit = -1;

        burst = 2'b01;

        id = -1;
        lock = 0;
        prot = 0;
        cache = 4'b1111;

        port = 0;

        $display("\nSLAVE TEST START! ");

        $display("DDR TEST START! ");
        ps_bfm_slave_test(hp0_dw, hp1_dw, burst, waddr_gp0, waddr_gp1, waddr_acp, waddr_hp0, waddr_hp1, raddr_gp0, raddr_gp1, raddr_acp, raddr_hp0, raddr_hp1, len_gp0, len_gp1, len_acp, len_hp0, len_hp1, wdata_32bit_burst_gp0, wdata_32bit_burst_gp1, wstrb_32bit_burst, wdata_64bit_burst_acp, wdata_64bit_burst_hp0, wdata_64bit_burst_hp1, wstrb_64bit_burst, id, lock, prot, cache);
        $display("DDR TEST END!\n ");

        waddr_gp0 = 33'h0_6100_0000;
        raddr_gp0 = 33'h0_6100_0000;
        waddr_gp1 = 33'h0_6100_10F0;
        raddr_gp1 = 33'h0_6100_10F0;
        
        waddr_acp = 33'h0_6100_1F80;
        raddr_acp = 33'h0_6100_1F80;

        waddr_hp0 = 33'h0_6102_0000;
        raddr_hp0 = 33'h0_6102_0000;
        waddr_hp1 = 33'h0_6103_FF80;
        raddr_hp1 = 33'h0_6103_FF80;
        
        $display("OCM TEST START! ");
        ps_bfm_slave_test(hp0_dw, hp1_dw, burst, waddr_gp0, waddr_gp1, waddr_acp, waddr_hp0, waddr_hp1, raddr_gp0, raddr_gp1, raddr_acp, raddr_hp0, raddr_hp1, len_gp0, len_gp1, len_acp, len_hp0, len_hp1, wdata_32bit_burst_gp0, wdata_32bit_burst_gp1, wstrb_32bit_burst, wdata_64bit_burst_acp, wdata_64bit_burst_hp0, wdata_64bit_burst_hp1, wstrb_64bit_burst, id, lock, prot, cache);
        $display("OCM TEST END!");

        waddr_gp0 = 33'h0_0000_0000;
        raddr_gp0 = 33'h0_0000_0000;
        waddr_gp1 = 33'h0_3FFF_FF80;
        raddr_gp1 = 33'h0_3FFF_FF80;

        waddr_acp = 33'h1_0000_0000;
        raddr_acp = 33'h1_0000_0000;

        waddr_hp0 = 33'h1_1000_0000;
        raddr_hp0 = 33'h1_1000_0000;
        waddr_hp1 = 33'h1_9FFF_FF80;
        raddr_hp1 = 33'h1_9FFF_FF80;

        qos_gp0 = 0;
        qos_gp1 = 0;
        qos_acp = 0;
        qos_hp0 = 0;
        qos_hp1 = 0;   

        burst = 2'b01;

        $display("SLAVE TEST END! ");
end
endtask


task automatic ps_bfm_slave_test(input hp0_dw, input hp1_dw, input [1:0] burst, input [32:0] waddr_gp0, input [32:0] waddr_gp1, input [32:0] waddr_acp, input [32:0] waddr_hp0, input [32:0] waddr_hp1, input [32:0] raddr_gp0, input [32:0] raddr_gp1, input [32:0] raddr_acp, input [32:0] raddr_hp0, input [32:0] raddr_hp1, input [3:0] len_gp0, input [3:0] len_gp1, input [2:0] len_acp, input [3:0] len_hp0, input [3:0] len_hp1, input [16*32-1:0] wdata_32bit_burst_gp0, input [16*32-1:0] wdata_32bit_burst_gp1, input [16*4-1:0] wstrb_32bit_burst, input [16*64-1:0] wdata_64bit_burst_acp, input [16*64-1:0] wdata_64bit_burst_hp0, input [16*64-1:0] wdata_64bit_burst_hp1, input [16*8-1:0] wstrb_64bit_burst, input [31:0] id, input lock, input [2:0] prot, input [3:0] cache);

        reg  [16*32-1:0] rdata_32bit_burst_gp0;
        reg  [16*32-1:0] rdata_32bit_burst_gp1;
        reg  [16*64-1:0] rdata_64bit_burst_acp;
        reg  [16*32-1:0] rdata_32bit_burst_hp0;
        reg  [16*32-1:0] rdata_32bit_burst_hp1;
        reg  [16*64-1:0] rdata_64bit_burst_hp0;
        reg  [16*64-1:0] rdata_64bit_burst_hp1;

        reg [1:0] size;
        reg [1:0] bresp_gp0;
        reg [1:0] bresp_gp1;
        reg [1:0] bresp_acp;
        reg [1:0] bresp_hp0;
        reg [1:0] bresp_hp1;
        reg [1:0] rresp_gp0;
        reg [1:0] rresp_gp1;
        reg [1:0] rresp_acp;
        reg [1:0] rresp_hp0;
        reg [1:0] rresp_hp1;

        reg [3:0] qos_gp0;
        reg [3:0] qos_gp1;
        reg [3:0] qos_acp;
        reg [3:0] qos_hp0;
        reg [3:0] qos_hp1;

        reg [31:0] awid_gp0;
        reg [31:0] awid_gp1;
        reg [31:0] awid_acp;
        reg [31:0] awid_hp0;
        reg [31:0] awid_hp1;

        reg [31:0] arid_gp0;
        reg [31:0] arid_gp1;
        reg [31:0] arid_acp;
        reg [31:0] arid_hp0;
        reg [31:0] arid_hp1;

        reg awlock;
        reg arlock;

        reg [2:0] awprot;
        reg [2:0] arprot;

        reg [3:0] awcache;
        reg [3:0] arcache;
        
        integer i;
        reg flag;

        reg [8*5:1] str; 

begin
//gp0 

        if (burst === 2'b01) begin
            str = "INCR";
        end
        else if (burst === 2'b00) begin
            str = "FIXED";
        end
        else if (burst === 2'b10) begin
            str = "WRAP";
        end

        qos_gp0 = 0;
        qos_gp1 = 0;
        qos_acp = 0;
        qos_hp0 = 0;
        qos_hp1 = 0;

        awid_gp0 = id;
        awid_gp1 = id;
        awid_acp = id;
        awid_hp0 = id;
        awid_hp1 = id;

        arid_gp0 = id;
        arid_gp1 = id;
        arid_acp = id;
        arid_hp0 = id;
        arid_hp1 = id;

        awlock = lock;
        arlock = lock;

        awprot = prot;
        arprot = prot;

        awcache = cache;
        arcache = cache;

        rdata_32bit_burst_gp0 = 0;
        rdata_32bit_burst_gp1 = 0;
        rdata_64bit_burst_acp = 0;
        rdata_32bit_burst_hp0 = 0;
        rdata_32bit_burst_hp1 = 0;
        rdata_64bit_burst_hp0 = 0;
        rdata_64bit_burst_hp1 = 0;

        size = 2'b10;
        flag = 1'b0;
        #100;
        tb.U_axi_master_du_gp0.write_addr(burst,waddr_gp0,len_gp0,size,qos_gp0,awid_gp0,awlock,awprot,awcache);
        tb.U_axi_master_du_gp0.write_32bit_data_wburst(wdata_32bit_burst_gp0,wstrb_32bit_burst,len_gp0);
        tb.U_axi_master_du_gp0.write_bresp(awid_gp0,bresp_gp0);
        #100;
        tb.U_axi_master_du_gp0.read_addr(burst,raddr_gp0,len_gp0,size,qos_gp0,arid_gp0,arlock,arprot,arcache);
        tb.U_axi_master_du_gp0.read_32bit_data_wburst(arid_gp0,len_gp0,rdata_32bit_burst_gp0, rresp_gp0);
        for (i=0; i<(len_gp0+1)*4;i=i+1) begin
            if ((bresp_gp0 !==2'b0) |(rresp_gp0 !==2'b0) | ((wstrb_32bit_burst[i] === 1'b1) & (rdata_32bit_burst_gp0[i*8+:8] !== wdata_32bit_burst_gp0[i*8+:8]))) begin
                if (flag == 1'b0) begin
                    $display("GP0 BURST TYPE =%s, BURST LEN = %d, START ADDR = %h, WRITE AND READ ERROR! ", str, len_gp0+5'b1, waddr_gp0);
                end
                flag = 1'b1;
            end
            else if (i==(len_gp0+1)*4-1) begin
                if (flag == 1'b0) begin
                    $display("GP0 BURST TYPE =%s, BURST LEN = %d, START ADDR = %h, WRITE AND READ PASS! ", str, len_gp0+5'b1, waddr_gp0);
                end
            end
        end

//gp1
        size = 2'b10;
        flag = 1'b0;
        
        #100;
        tb.U_axi_master_du_gp1.write_addr(burst,waddr_gp1,len_gp1,size,qos_gp1,awid_gp1,awlock,awprot,awcache);
        tb.U_axi_master_du_gp1.write_32bit_data_wburst(wdata_32bit_burst_gp1,wstrb_32bit_burst,len_gp1);
        tb.U_axi_master_du_gp1.write_bresp(awid_gp1,bresp_gp1);
        #100;
        tb.U_axi_master_du_gp1.read_addr(burst,raddr_gp1,len_gp1,size,qos_gp1,arid_gp1,arlock,arprot,arcache);
        tb.U_axi_master_du_gp1.read_32bit_data_wburst(arid_gp1,len_gp1,rdata_32bit_burst_gp1, rresp_gp1);
        for (i=0; i<(len_gp1+1)*4;i=i+1) begin
            if ((bresp_gp1 !==2'b0) |(rresp_gp1 !==2'b0) | ((wstrb_32bit_burst[i] === 1'b1) & (rdata_32bit_burst_gp1[i*8+:8] !== wdata_32bit_burst_gp1[i*8+:8]))) begin
                if (flag == 1'b0) begin
                    $display("GP1 BURST TYPE =%s, BURST LEN = %d, START ADDR = %h, WRITE AND READ ERROR! ", str, len_gp1+5'b1, waddr_gp1);
                end
                flag = 1'b1;
            end
            else if (i==(len_gp1+1)*4-1) begin
                if (flag == 1'b0) begin
                    $display("GP1 BURST TYPE =%s, BURST LEN = %d, START ADDR = %h, WRITE AND READ PASS! ", str, len_gp1+5'b1, waddr_gp1);
                end
            end
        end
//acp
        size = 2'b11;
        flag = 1'b0;
        
        #100;
        tb.U_axi_master_du_acp.write_addr(2'b01,waddr_acp,len_acp,size,qos_acp,awid_acp,awlock,awprot,awcache);
        tb.U_axi_master_du_acp.write_64bit_data_wburst(wdata_64bit_burst_acp,wstrb_64bit_burst,len_acp);
        tb.U_axi_master_du_acp.write_bresp(awid_acp,bresp_acp);
        #100;
        tb.U_axi_master_du_acp.read_addr(2'b01,raddr_acp,len_acp,size,qos_acp,arid_acp,arlock,arprot,arcache);
        tb.U_axi_master_du_acp.read_64bit_data_wburst(arid_acp,len_acp,rdata_64bit_burst_acp, rresp_acp);
        for (i=0; i<(len_acp+1)*8;i=i+1) begin
            if ((bresp_acp !==2'b0) |(rresp_acp !==2'b0) | ((wstrb_64bit_burst[i] === 1'b1) & (rdata_64bit_burst_acp[i*8+:8] !== wdata_64bit_burst_acp[i*8+:8]))) begin
                if (flag == 1'b0) begin
                    $display("ACP BURST TYPE =%s, BURST LEN = %d, START ADDR = %h, WRITE AND READ ERROR! ", str, len_acp+5'b1, waddr_acp);
                end
                flag = 1'b1;
            end
            else if (i==(len_acp+1)*8-1) begin
                if (flag == 1'b0) begin
                    $display("ACP BURST TYPE =%s, BURST LEN = %d, START ADDR = %h, WRITE AND READ PASS! ", str, len_acp+5'b1, waddr_acp);
                end
            end
        end
//hp0
        flag = 1'b0;
        
        #100;
        if (hp0_dw == 1'b0) begin
            size = 2'b10;
            #100;
            $display("HP0 DATA WIDTH = 32! ");
            tb.U_axi_master_du_hp0.write_addr(burst,waddr_hp0,len_hp0,size,qos_hp0,awid_hp0,awlock,awprot,awcache);
            tb.U_axi_master_du_hp0.write_32bit_data_wburst(wdata_64bit_burst_hp0[16*32-1:0],wstrb_32bit_burst,len_hp0);
            tb.U_axi_master_du_hp0.write_bresp(awid_hp0,bresp_hp0);
            #100;
            tb.U_axi_master_du_hp0.read_addr(burst,raddr_hp0,len_hp0,size,qos_hp0,arid_hp0,arlock,arprot,arcache);
            tb.U_axi_master_du_hp0.read_32bit_data_wburst(arid_hp0,len_hp0,rdata_32bit_burst_hp0, rresp_hp0);
            for (i=0; i<(len_hp0+1)*8;i=i+1) begin
                if ((bresp_hp0 !==2'b0) |(rresp_hp0 !==2'b0) | ((wstrb_32bit_burst[i] === 1'b1) & (rdata_32bit_burst_hp0[i*8+:8] !== wdata_64bit_burst_hp0[i*8+:8]))) begin
                    if (flag == 1'b0) begin
                        $display("HP0 BURST TYPE =%s, BURST LEN = %d, START ADDR = %h, WRITE AND READ ERROR! ", str, len_hp0+5'b1, waddr_hp0);
                    end
                    flag = 1'b1;
                end
                else if (i==(len_hp0+1)*8-1) begin
                    if (flag == 1'b0) begin
                        $display("HP0 BURST TYPE =%s, BURST LEN = %d, START ADDR = %h, WRITE AND READ PASS! ", str, len_hp0+5'b1, waddr_hp0);
                    end
                end
            end
        end
        else begin
            size = 2'b11;
            #100;
            $display("HP0 DATA WIDTH = 64! ");
            tb.U_axi_master_du_hp0.write_addr(burst,waddr_hp0,len_hp0,size,qos_hp0,awid_hp0,awlock,awprot,awcache);
            tb.U_axi_master_du_hp0.write_64bit_data_wburst(wdata_64bit_burst_hp0,wstrb_64bit_burst,len_hp0);
            tb.U_axi_master_du_hp0.write_bresp(awid_hp0,bresp_hp0);
            #100;
            tb.U_axi_master_du_hp0.read_addr(burst,raddr_hp0,len_hp0,size,qos_hp0,arid_hp0,arlock,arprot,arcache);
            tb.U_axi_master_du_hp0.read_64bit_data_wburst(arid_hp0,len_hp0,rdata_64bit_burst_hp0, rresp_hp0);
            for (i=0; i<(len_hp0+1)*8;i=i+1) begin
                if ((bresp_hp0 !==2'b0) |(rresp_hp0 !==2'b0) | ((wstrb_64bit_burst[i] === 1'b1) & (rdata_64bit_burst_hp0[i*8+:8] !== wdata_64bit_burst_hp0[i*8+:8]))) begin
                    if (flag == 1'b0) begin
                        $display("HP0 BURST TYPE =%s, BURST LEN = %d, START ADDR = %h, WRITE AND READ ERROR! ", str, len_hp0+5'b1, waddr_hp0);
                    end
                    flag = 1'b1;
                end
                else if (i==(len_hp0+1)*8-1) begin
                    if (flag == 1'b0) begin
                        $display("HP0 BURST TYPE =%s, BURST LEN = %d, START ADDR = %h, WRITE AND READ PASS! ", str, len_hp0+5'b1, waddr_hp0);
                    end
                end
            end        
        end
//hp1
        flag = 1'b0;

        #100;
        if (hp1_dw == 1'b0)begin
            size = 2'b10;
            #100;
            $display("HP1 DATA WIDTH = 32! ");
            tb.U_axi_master_du_hp1.write_addr(burst,waddr_hp1,len_hp1,size,qos_hp1,awid_hp1,awlock,awprot,awcache);
            tb.U_axi_master_du_hp1.write_32bit_data_wburst(wdata_64bit_burst_hp1[16*32-1:0],wstrb_32bit_burst,len_hp1);
            tb.U_axi_master_du_hp1.write_bresp(awid_hp1,bresp_hp1);
            #100;
            tb.U_axi_master_du_hp1.read_addr(burst,raddr_hp1,len_hp1,size,qos_hp1,arid_hp1,arlock,arprot,arcache);
            tb.U_axi_master_du_hp1.read_32bit_data_wburst(arid_hp1,len_hp1,rdata_32bit_burst_hp1, rresp_hp1);
            for (i=0; i<(len_hp1+1)*8;i=i+1) begin
                if ((bresp_hp1 !==2'b0) |(rresp_hp1 !==2'b0) | ((wstrb_32bit_burst[i] === 1'b1) & (rdata_32bit_burst_hp1[i*8+:8] !== wdata_64bit_burst_hp1[i*8+:8]))) begin
                    if (flag == 1'b0) begin
                        $display("HP1 BURST TYPE =%s, BURST LEN = %d, START ADDR = %h, WRITE AND READ ERROR! ", str, len_hp1+5'b1, waddr_hp1);
                    end
                    flag = 1'b1;
                end
                else if (i==(len_hp1+1)*8-1) begin
                    if (flag == 1'b0) begin
                        $display("HP1 BURST TYPE =%s, BURST LEN = %d, START ADDR = %h, WRITE AND READ PASS! ", str, len_hp1+5'b1, waddr_hp1);
                    end
                end
            end
        end
        else begin
            size = 2'b11;
            #100;
            $display("HP1 DATA WIDTH = 64! ");
            tb.U_axi_master_du_hp1.write_addr(burst,waddr_hp1,len_hp1,size,qos_hp1,awid_hp1,awlock,awprot,awcache);
            tb.U_axi_master_du_hp1.write_64bit_data_wburst(wdata_64bit_burst_hp1,wstrb_64bit_burst,len_hp1);
            tb.U_axi_master_du_hp1.write_bresp(awid_hp1,bresp_hp1);
            #100;
            tb.U_axi_master_du_hp1.read_addr(burst,raddr_hp1,len_hp1,size,qos_hp1,arid_hp1,arlock,arprot,arcache);
            tb.U_axi_master_du_hp1.read_64bit_data_wburst(arid_hp1,len_hp1,rdata_64bit_burst_hp1, rresp_hp1);
            for (i=0; i<(len_hp1+1)*8;i=i+1) begin
                if ((bresp_hp1 !==2'b0) |(rresp_hp1 !==2'b0) | ((wstrb_64bit_burst[i] === 1'b1) & (rdata_64bit_burst_hp1[i*8+:8] !== wdata_64bit_burst_hp1[i*8+:8]))) begin
                    if (flag == 1'b0) begin
                        $display("HP1 BURST TYPE =%s, BURST LEN = %d, START ADDR = %h, WRITE AND READ ERROR! ", str, len_hp1+5'b1, waddr_hp1);
                    end
                    flag = 1'b1;
                end
                else if (i==(len_hp1+1)*8-1) begin
                    if (flag == 1'b0) begin
                        $display("HP1 BURST TYPE =%s, BURST LEN = %d, START ADDR = %h, WRITE AND READ PASS! ", str, len_hp1+5'b1, waddr_hp1);
                    end
                end
            end
        end
        #2000;
end
endtask