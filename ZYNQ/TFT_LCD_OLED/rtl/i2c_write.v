module i2c_demo #(
    parameter integer CLK_FREQ = 50_000_000,
    parameter integer I2C_FREQ = 100_000,
    parameter [6:0] SLAVE_ADDR = 7'h50,
    parameter integer WRITE_WAIT_MS = 5
)(
    input  wire clk,
    input  wire rst_n,
    inout  wire scl,
    inout  wire sda,
    output reg  busy,
    output reg  done,
    output reg  error
);

localparam integer WRITE_WAIT_CYCLES = (CLK_FREQ / 1000) * WRITE_WAIT_MS;
localparam [2:0] ST_WRITE_LAUNCH = 3'd0;
localparam [2:0] ST_WAIT_I2C     = 3'd1;
localparam [2:0] ST_WRITE_DELAY  = 3'd2;
localparam [2:0] ST_FINISHED     = 3'd3;

reg [2:0]  state;
reg [7:0]  payload_idx;
reg [31:0] wait_count;
reg        i2c_start;
reg [15:0] i2c_word_addr;
reg [7:0]  i2c_data_in;
wire [7:0] i2c_data_out;
wire       i2c_busy;
wire       i2c_done;
wire       i2c_error;

function [7:0] payload_byte;
    input [7:0] index;
    begin
        payload_byte = index ^ 8'hA5;
    end
endfunction

at24c64_i2c_byte_rw #(
    .CLK_FREQ(CLK_FREQ),
    .I2C_FREQ(I2C_FREQ),
    .SLAVE_ADDR(SLAVE_ADDR)
) u_at24c64_i2c_byte (
    .clk(clk),
    .rst_n(rst_n),
    .start(i2c_start),
    .read_req(1'b0),
    .word_addr(i2c_word_addr),
    .data_in(i2c_data_in),
    .data_out(i2c_data_out),
    .busy(i2c_busy),
    .done(i2c_done),
    .error(i2c_error),
    .scl(scl),
    .sda(sda)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state         <= ST_WRITE_LAUNCH;
        payload_idx   <= 8'd0;
        wait_count    <= 32'd0;
        i2c_start     <= 1'b0;
        i2c_word_addr <= 16'd0;
        i2c_data_in   <= 8'd0;
        busy          <= 1'b1;
        done          <= 1'b0;
        error         <= 1'b0;
    end else begin
        i2c_start <= 1'b0;
        done      <= 1'b0;

        case (state)
            ST_WRITE_LAUNCH: begin
                i2c_word_addr <= {8'h00, payload_idx};
                i2c_data_in   <= payload_byte(payload_idx);
                i2c_start     <= 1'b1;
                state         <= ST_WAIT_I2C;
            end

            ST_WAIT_I2C: begin
                if (i2c_done) begin
                    if (i2c_error) begin
                        error <= 1'b1;
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        state <= ST_FINISHED;
                    end else begin
                        wait_count <= 32'd0;
                        state      <= ST_WRITE_DELAY;
                    end
                end
            end

            ST_WRITE_DELAY: begin
                if (WRITE_WAIT_CYCLES <= 1 ||
                    wait_count >= WRITE_WAIT_CYCLES - 1) begin
                    wait_count <= 32'd0;
                    if (payload_idx == 8'hFF) begin
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        state <= ST_FINISHED;
                    end else begin
                        payload_idx <= payload_idx + 1'b1;
                        state       <= ST_WRITE_LAUNCH;
                    end
                end else begin
                    wait_count <= wait_count + 1'b1;
                end
            end

            default: begin
                busy <= 1'b0;
            end
        endcase
    end
end

endmodule
