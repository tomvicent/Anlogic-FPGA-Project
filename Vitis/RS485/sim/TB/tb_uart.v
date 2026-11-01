`timescale 1ns / 1ps

// 仿真顶层是 tb_rs485_key_led，不是文件名 tb_uart。
// TB默认消抖1ms；设 DEBOUNCE_MS=20 可测试真实硬件时序。
module tb_rs485_key_led #(
    parameter integer CLK_FREQ = 50_000_000,
    parameter integer UART_BPS = 115200,
    parameter integer DEBOUNCE_MS = 1
);
localparam real CLK_PERIOD = 1_000_000_000.0 / CLK_FREQ;
localparam integer BIT_TIME = (1_000_000_000 + UART_BPS / 2) / UART_BPS;
localparam integer HOLD_TIME = DEBOUNCE_MS * 1_000_000 + 200_000;

reg sys_clk, sys_rst_n;
reg [1:0] key;
wire [1:0] led;
reg rs485_uart_rxd;
wire rs485_uart_txd;
reg [7:0] rx_byte;       // 从本端TX线上解码出的字节
reg [7:0] received_byte; // 本端RX模块实际收到的字节
reg rx_done_d;
integer tx_count, rx_count, errors;
reg [7:0] expected_tx [0:31];
reg [7:0] expected_rx [0:31];

rs485_key_led #(
    .CLK_FREQ(CLK_FREQ), .UART_BPS(UART_BPS), .DEBOUNCE_MS(DEBOUNCE_MS)
) uut (
    .sys_clk(sys_clk), .sys_rst_n(sys_rst_n), .key(key), .led(led),
    .rs485_uart_rxd(rs485_uart_rxd), .rs485_uart_txd(rs485_uart_txd)
);

initial begin
    sys_clk = 1'b0;
    forever #(CLK_PERIOD / 2) sys_clk = ~sys_clk;
end

// RX由任务模拟对端驱动。TX没有回接RX，本端按键只发送数据。
task uart_send_frame(input [7:0] data, input stop_bit);
    integer i;
    begin
        rs485_uart_rxd = 1'b0;
        #BIT_TIME;
        for (i = 0; i < 8; i = i + 1) begin
            rs485_uart_rxd = data[i];
            #BIT_TIME;
        end
        rs485_uart_rxd = stop_bit;
        #BIT_TIME;
        rs485_uart_rxd = 1'b1;
    end
endtask

task receive_byte(input [7:0] data);
    integer before_rx;
    reg [1:0] expected_led;
    begin
        before_rx = rx_count;
        expected_rx[before_rx] = data;
        expected_led = ~data[1:0];
        uart_send_frame(data, 1'b1);
        #(3 * CLK_PERIOD);
        if (rx_count != before_rx + 1 || received_byte !== data || led !== expected_led) begin
            $display("FAIL RX: data=%02h received=%02h led=%02b expected_led=%02b",
                     data, received_byte, led, expected_led);
            errors = errors + 1;
        end
    end
endtask

// 按键低有效：key=10为KEY0按下；key=01为KEY1按下。
// 按下、松开各发送一次；消抖完成前不应发送。
task change_key(input [1:0] new_key);
    integer i, before_tx;
    reg [1:0] old_key, old_led;
    begin
        before_tx = tx_count;
        old_key = key;
        old_led = led;
        expected_tx[before_tx] = {6'b0, new_key};
        for (i = 0; i < 5; i = i + 1) begin
            key = new_key;
            #2000;
            key = old_key;
            #2000;
        end
        if (tx_count != before_tx || uut.key_data !== old_key || rs485_uart_txd !== 1'b1) begin
            $display("FAIL debounce: bounce triggered a key change or TX");
            errors = errors + 1;
        end
        key = new_key;
        #HOLD_TIME;
        if (tx_count != before_tx + 1 || rx_byte !== {6'b0, new_key} ||
            uut.key_data !== new_key || led !== old_led) begin
            $display("FAIL key: key=%02b TX=%02h frame_count=%0d LED=%02b",
                     new_key, rx_byte, tx_count - before_tx, led);
            errors = errors + 1;
        end
    end
endtask

// 独立解码TX，检查8位数据和停止位。
always @(negedge rs485_uart_txd) begin : monitor_tx
    integer i;
    if (sys_rst_n) begin
        #(BIT_TIME / 2);
        if (rs485_uart_txd === 1'b0) begin
            for (i = 0; i < 8; i = i + 1) begin
                #BIT_TIME;
                rx_byte[i] = rs485_uart_txd;
            end
            #BIT_TIME;
            if (rs485_uart_txd !== 1'b1 || rx_byte !== expected_tx[tx_count]) begin
                $display("FAIL TX: actual=%02h expected=%02h stop=%b",
                         rx_byte, expected_tx[tx_count], rs485_uart_txd);
                errors = errors + 1;
            end
            tx_count = tx_count + 1;
            $display("[%0t] TX frame %0d: 0x%02h", $time, tx_count, rx_byte);
        end
    end
end

// done只有一拍；下一拍led_ctrl锁存~uart_rx_data[1:0]。
always @(posedge sys_clk) begin
    if (!sys_rst_n)
        rx_done_d = 1'b0;
    else begin
        if (uut.uart_rx_done) begin
            if (rx_done_d || uut.uart_rx_data !== expected_rx[rx_count]) begin
                $display("FAIL RX event: actual=%02h expected=%02h done_prev=%b",
                         uut.uart_rx_data, expected_rx[rx_count], rx_done_d);
                errors = errors + 1;
            end
            received_byte = uut.uart_rx_data;
            rx_count = rx_count + 1;
            $display("[%0t] RX frame %0d: 0x%02h", $time, rx_count, received_byte);
        end
        rx_done_d = uut.uart_rx_done;
    end
end

// 只导出功能信号，避免所有计数器产生数百MB的VCD。
// ModelSim脚本使用+NO_VCD和WLF；+DUMP_ALL可导出全部内部信号。
initial begin
    if (!$test$plusargs("NO_VCD")) begin
        $dumpfile("rs485_checked.vcd");
        if ($test$plusargs("DUMP_ALL"))
            $dumpvars(0, tb_rs485_key_led);
        else
            $dumpvars(0, sys_clk, sys_rst_n, key, led, rs485_uart_rxd,
                      rs485_uart_txd, rx_byte, received_byte, uut.key_data,
                      uut.uart_tx_en, uut.uart_tx_data, uut.uart_rx_done, uut.uart_rx_data);
    end
end

initial begin : test_sequence
    integer before_rx;
    reg [1:0] old_led;
    sys_rst_n = 1'b0;
    key = 2'b11;
    rs485_uart_rxd = 1'b1;
    rx_byte = 8'd0;
    received_byte = 8'd0;
    rx_done_d = 1'b0;
    tx_count = 0;
    rx_count = 0;
    errors = 0;
    #200;
    @(negedge sys_clk);
    sys_rst_n = 1'b1;
    #200;
    if (led !== 2'b00 || rs485_uart_txd !== 1'b1) begin
        $display("FAIL reset: led=%b tx=%b", led, rs485_uart_txd);
        errors = errors + 1;
    end

    change_key(2'b10); // KEY0按下，发送0x02
    change_key(2'b11); // 松开，发送0x03
    receive_byte(8'h02); // LED=01，LED0亮
    receive_byte(8'h01); // LED=10，LED1亮
    receive_byte(8'h00); // LED=11，两个都亮
    receive_byte(8'h03); // LED=00，两个都灭
    change_key(2'b01); // KEY1按下，发送0x01
    change_key(2'b11);
    change_key(2'b00); // 同时按下，发送0x00
    change_key(2'b11);

    // 连续帧，无额外空闲位；检查整个8位字节。
    before_rx = rx_count;
    expected_rx[before_rx] = 8'ha5;
    expected_rx[before_rx + 1] = 8'h5a;
    uart_send_frame(8'ha5, 1'b1);
    uart_send_frame(8'h5a, 1'b1);
    #(3 * CLK_PERIOD);
    if (rx_count != before_rx + 2 || received_byte !== 8'h5a || led !== 2'b01) begin
        $display("FAIL back-to-back RX");
        errors = errors + 1;
    end

    // 短低脉冲、非法停止位应丢弃，并保持LED。
    before_rx = rx_count;
    old_led = led;
    rs485_uart_rxd = 1'b0;
    #(BIT_TIME / 4);
    rs485_uart_rxd = 1'b1;
    #(2 * BIT_TIME);
    uart_send_frame(8'hff, 1'b0);
    #(2 * BIT_TIME);
    if (rx_count != before_rx || led !== old_led) begin
        $display("FAIL RX rejection: invalid input changed RX count or LED");
        errors = errors + 1;
    end
    receive_byte(8'h00); // 错误帧之后继续正常接收

    if (tx_count != 6 || rx_count != 7)
        errors = errors + 1;
    if (errors != 0)
        $fatal(1, "FAIL: %0d errors, TX=%0d RX=%0d", errors, tx_count, rx_count);
    $display("PASS: all checks passed, TX=%0d RX=%0d debounce=%0dms",
             tx_count, rx_count, DEBOUNCE_MS);
    // $finish;
end

initial begin
    #(8 * HOLD_TIME + 2_000_000);
    $fatal(1, "FAIL: simulation timeout");
end
endmodule
