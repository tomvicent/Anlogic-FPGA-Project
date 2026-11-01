`timescale 1ns / 1ps

// UART transmitter: one start bit, eight data bits (LSB first), one stop bit.
module uart_tx #(
    parameter integer CLK_FREQ = 50_000_000,
    parameter integer UART_BPS = 115200,
    parameter integer TX_SETUP_CYCLES = 0
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_tx_en,
    input  wire [7:0] uart_tx_data,
    output reg        uart_txd,
    output wire       uart_tx_busy
);

    // Require UART_BPS > 0 and CLK_FREQ / UART_BPS >= 2.
    localparam integer BIT_CYCLES = (CLK_FREQ + UART_BPS / 2) / UART_BPS;
    localparam integer COUNT_MAX = (TX_SETUP_CYCLES > BIT_CYCLES) ? TX_SETUP_CYCLES : BIT_CYCLES;
    localparam integer COUNT_WIDTH = (COUNT_MAX <= 1) ? 1 : $clog2(COUNT_MAX);

    reg [COUNT_WIDTH-1:0] baud_count;
    reg [9:0] tx_frame;
    reg [3:0] bit_index;
    reg busy;
    reg tx_en_d;
    reg tx_start_pending;

    assign uart_tx_busy = busy;

    // Accept a rising edge only while idle. Requests while busy are discarded.
    // Holding uart_tx_en high sends one frame; lower it before the next request.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_en_d    <= 1'b0;
            baud_count <= {COUNT_WIDTH{1'b0}};
            tx_frame   <= 10'b1111111111;
            bit_index  <= 4'd0;
            busy       <= 1'b0;
            uart_txd   <= 1'b1;
            tx_start_pending <= 1'b0;
        end else begin
            tx_en_d <= uart_tx_en;
            if (!busy) begin
                uart_txd <= 1'b1;
                if (uart_tx_en && !tx_en_d) begin
                    tx_frame   <= {1'b1, uart_tx_data, 1'b0};
                    bit_index  <= 4'd0;
                    baud_count <= (TX_SETUP_CYCLES > 0) ? TX_SETUP_CYCLES - 1 : BIT_CYCLES - 1;
                    busy       <= 1'b1;
                    uart_txd   <= (TX_SETUP_CYCLES > 0);
                    tx_start_pending <= (TX_SETUP_CYCLES > 0);
                end
            end else if (baud_count == 0) begin
                if (tx_start_pending) begin
                    tx_start_pending <= 1'b0;
                    uart_txd   <= 1'b0;
                    baud_count <= BIT_CYCLES - 1;
                end else if (bit_index == 4'd9) begin
                    busy     <= 1'b0;
                    uart_txd <= 1'b1;
                end else begin
                    tx_frame   <= {1'b1, tx_frame[9:1]};
                    uart_txd   <= tx_frame[1];
                    bit_index  <= bit_index + 1'b1;
                    baud_count <= BIT_CYCLES - 1;
                end
            end else begin
                baud_count <= baud_count - 1'b1;
            end
        end
    end

endmodule
