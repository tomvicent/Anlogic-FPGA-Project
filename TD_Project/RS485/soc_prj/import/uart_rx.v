`timescale 1ns / 1ps

// UART receiver: 8N1, LSB first. Invalid start/stop bits are discarded.
module uart_rx #(
    parameter integer CLK_FREQ = 50_000_000,
    parameter integer UART_BPS = 115200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rxd,
    output reg        uart_rx_done,
    output reg  [7:0] uart_rx_data
);

    // Require UART_BPS > 0 and CLK_FREQ / UART_BPS >= 2.
    localparam integer BIT_CYCLES = (CLK_FREQ + UART_BPS / 2) / UART_BPS; //整数除法前加半个除数，实现四舍五入
    localparam integer HALF_CYCLES = BIT_CYCLES / 2;
    localparam integer COUNT_WIDTH = (BIT_CYCLES <= 1) ? 1 : $clog2(BIT_CYCLES);//取出采样周期需要几个2bit来存入数据

    //状态机的实现
    localparam [1:0] IDLE  = 2'd0;
    localparam [1:0] START = 2'd1;
    localparam [1:0] DATA  = 2'd2;
    localparam [1:0] STOP  = 2'd3;

    (* ASYNC_REG = "TRUE" *) reg rxd_sync_0;
    (* ASYNC_REG = "TRUE" *) reg rxd_sync_1;
    reg rxd_d;
    reg [1:0] state;
    reg [COUNT_WIDTH-1:0] baud_count;
    reg [2:0] bit_index;
    reg [7:0] rx_shift;

    // Synchronize the asynchronous RX input before edge detection and sampling.
    // 进行Rst_n的归一操作，进行初始化，异步RX输入三级寄存器：前两级同步到时钟域消除亚稳态，第三级延迟一拍用于下降沿检测
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rxd_sync_0 <= 1'b1;
            rxd_sync_1 <= 1'b1;
            rxd_d      <= 1'b1;
        end else begin
            rxd_sync_0 <= uart_rxd;
            rxd_sync_1 <= rxd_sync_0;
            rxd_d      <= rxd_sync_1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            baud_count   <= {COUNT_WIDTH{1'b0}};
            bit_index    <= 3'd0;
            rx_shift     <= 8'd0;
            uart_rx_data <= 8'd0;
            uart_rx_done <= 1'b0;
        end else begin
            uart_rx_done <= 1'b0;
            case (state)
                IDLE: begin
                    if (rxd_d && !rxd_sync_1) begin
                        baud_count <= HALF_CYCLES - 1;
                        state      <= START;
                    end
                end
                START: begin
                    if (baud_count != 0) begin
                        baud_count <= baud_count - 1'b1;
                    end else if (!rxd_sync_1) begin
                        baud_count <= BIT_CYCLES - 1;
                        bit_index  <= 3'd0;
                        state      <= DATA;
                    end else begin
                        state <= IDLE; // Short low glitch, not a valid start bit.
                    end
                end
                DATA: begin
                    if (baud_count != 0) begin
                        baud_count <= baud_count - 1'b1;
                    end else begin
                        rx_shift[bit_index] <= rxd_sync_1;
                        baud_count          <= BIT_CYCLES - 1;
                        if (bit_index == 3'd7)
                            state <= STOP;
                        else
                            bit_index <= bit_index + 1'b1;
                    end
                end
                STOP: begin
                    if (baud_count != 0) begin
                        baud_count <= baud_count - 1'b1;
                    end else begin
                        if (rxd_sync_1) begin
                            uart_rx_data <= rx_shift;
                            uart_rx_done <= 1'b1;
                        end
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
