
task automatic fahb_master_test_unit();
    reg [32:0] waddr;
    reg [32:0] raddr;
    reg [31:0] len;
    reg [2:0] size;
    reg wrap;
    reg single_burst;
    reg [32*16-1:0] datai;
begin
    waddr = 33'hFC000000;
    raddr = 33'hFC000000;

    size = 3'b010;
    len = 1;
    wrap = 0;
    single_burst = 1;

    datai[0*32+:32] = 32'h21111112;
    datai[1*32+:32] = 32'h32222223;
    datai[2*32+:32] = 32'h43333334;
    datai[3*32+:32] = 32'h54444445;
    datai[4*32+:32] = 32'h65555556;
    datai[5*32+:32] = 32'h76666667;
    datai[6*32+:32] = 32'h87777778;
    datai[7*32+:32] = 32'h98888889;
    datai[8*32+:32] = 32'ha999999a;
    datai[9*32+:32] = 32'hbaaaaaab;
    datai[10*32+:32] = 32'hcbbbbbbc;
    datai[11*32+:32] = 32'hdccccccd;
    datai[12*32+:32] = 32'hedddddde;
    datai[13*32+:32] = 32'hfeeeeeef;
    datai[14*32+:32] = 32'h1ffffff1;
    datai[15*32+:32] = 32'h6a5a5a56;

    $display("\nFAHB TEST START! ");
    fahb_master_test(waddr, raddr, len, size, wrap, single_burst, datai);
    $display("FAHB TEST END! ");
end
endtask


task automatic fahb_master_test(input [32:0] waddr, input [32:0] raddr, input [31:0] len, input [2:0] size, input wrap, input single_burst, input [32*16-1:0] datai);
    reg [31:0] i;
    reg [8*5:1] wrap_str;
    reg [5:0] size_str; 
    reg [32*16-1:0] datao;
    reg bresp;
    reg rresp;
    reg flag;
begin

    if (wrap === 1'b1) begin
        wrap_str = "WRAP";
    end
    else begin
        wrap_str = "INCR";
    end

    if (size === 3'b010) begin
        size_str = 32;
    end
    else if (size === 3'b001) begin
        size_str = 16;
    end
    else if (size === 3'b000) begin
        size_str = 8;
    end

    flag = 0;
    U_PS_BFM.M_FAHB.fahb_write_burst(waddr, len, size, datai, wrap, single_burst, bresp);
    #100;
    U_PS_BFM.M_FAHB.fahb_read_burst(raddr, len, size, wrap, single_burst, datao, rresp);
    for (i=0; i<(len<<size);i=i+1) begin
        if ((bresp !==1'b0) |(rresp !==1'b0) | (datao[i*8+:8] !== datai[i*8+:8])) begin
            if (flag == 1'b0) begin
                $display("FAHB BURST TYPE =%s, BURST LEN = %d, SIZE = %d, START ADDR = %h, WRITE AND READ ERROR! ", wrap_str, len[4:0], size_str, waddr);
            end
            flag = 1'b1;
        end
        else if (i==(len<<size)-1) begin
            if (flag == 1'b0) begin
                $display("FAHB BURST TYPE =%s, BURST LEN = %d, SIZE = %d, START ADDR = %h, WRITE AND READ PASS! ", wrap_str, len[4:0], size_str, waddr);
            end
        end
    end
    #100;
end
endtask