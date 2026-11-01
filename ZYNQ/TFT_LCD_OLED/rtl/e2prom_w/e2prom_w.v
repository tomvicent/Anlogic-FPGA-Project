//这个是顶层模块
module e2prom_w #(
    parameter integer CLK_FREQ = 50_000_000,
    parameter integer I2C_FREQ = 250_000,
    parameter [6:0] SLAVE_ADDR = 7'h50,
    parameter integer WRITE_WAIT_MS = 5
)(
    input  wire clk,
    input  wire rst_n,
    inout  wire scl,
    inout  wire sda,
    output wire led1,  // 写入失败（从机未应答）
    output wire led2   // 全部数据写入完成
);

reg start;
reg started;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        start   <= 1'b0;
        started <= 1'b0;
    end else begin
        start <= 1'b0;
        if (!started) begin
            start   <= 1'b1;
            started <= 1'b1;
        end
    end
end

e2prom_w_start_core #(
    .CLK_FREQ(CLK_FREQ),
    .I2C_FREQ(I2C_FREQ),
    .SLAVE_ADDR(SLAVE_ADDR),
    .WRITE_WAIT_MS(WRITE_WAIT_MS)
) u_e2prom_w_start_core (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .scl(scl),
    .sda(sda),
    .led1(led1),
    .led2(led2)
);

endmodule
