`timescale 1ns / 1ns

module tb_e2prom_w;

    reg  clk;
    reg  rst_n;
    tri1 scl;
    tri1 sda;
    wire led;
    // wire busy;
    // wire done;
    // wire error;

    // I2C 总线需要上拉，因为 SDA/SCL 端口是双向 inout
    pullup(scl);
    pullup(sda);

    e2prom_r #(
        .CLK_FREQ(50_000_000),
        .I2C_FREQ(250_000),
        .SLAVE_ADDR(7'h50),
        .WRITE_WAIT_MS(5)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .scl(scl),
        .sda(sda),
        .led(led)
        // .busy(busy),
        // .done(done),
        // .error(error)
    );

    // 50 MHz 时钟：周期 20ns
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    // 复位：先让时钟跑起来，然后释放复位
    initial begin
        rst_n = 1'b0;
        #100;
        rst_n = 1'b1;

        // 给足够时间，让顶层自动写 256 个字节
        // 256 字节 * 约 5ms/字节 ~ 1.28s
        #2000000;

        // $display("[TB] write done=%b error=%b busy=%b", done, error, busy);
        $stop;
    end

    // 监控信号，方便观察波形
    // 
    initial begin
        $monitor("t=%0t rst_n=%b scl=%b sda=%b led=%b",
                 $time, rst_n, scl, sda, led);
    end

endmodule
