// 顶层模块；led 为高电平点亮，整片校验通过后保持点亮。
module e2prom_r #(
    parameter integer CLK_FREQ = 50_000_000,
    parameter integer I2C_FREQ = 250_000,
    parameter [6:0] SLAVE_ADDR = 7'h50,
    parameter integer WRITE_WAIT_MS = 5
)(
    input  wire clk,
    input  wire rst_n,
    inout  wire scl,
    inout  wire sda,
    // output wire busy,
    // output wire done,
    // output wire error,
    output wire led
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

e2prom_r_start_core #(
    .CLK_FREQ(CLK_FREQ),
    .I2C_FREQ(I2C_FREQ),
    .SLAVE_ADDR(SLAVE_ADDR),
    .WRITE_WAIT_MS(WRITE_WAIT_MS)
) u_e2prom_r_start_core (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .scl(scl),
    // .sda(sda),
    // .busy(busy),
    // .done(done),
    .error(error),
    .led(led)
);

endmodule
//我现在要在这个e2prom_r的这个文件里面进行读取出里面的数据并进行判断，看看数据