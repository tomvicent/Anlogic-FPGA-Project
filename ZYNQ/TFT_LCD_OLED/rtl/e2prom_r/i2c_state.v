// AT24C64 读回校验模块。
// 复位释放后读取地址 0x0000~0x00FF，并核对写入器写入的 address ^ 8'hA5。
// 全部 256 字节匹配后 led 锁存为 1；任何 I2C 错误或数据不匹配都会置 error。
module e2prom_r_start_core #(
	parameter integer CLK_FREQ = 50_000_000,
	parameter integer I2C_FREQ = 250_000,
	parameter [6:0] SLAVE_ADDR = 7'h50,
	parameter integer WRITE_WAIT_MS = 5 // 保留旧版参数接口；只读校验不使用写等待时间
)(
	input  wire clk,
	input  wire rst_n,
	input  wire start,
	inout  wire scl,
	inout  wire sda,
	// output reg  busy,
	// output reg  done,
	// output reg  error,
	output reg  led
);

reg  busy;
reg  done;
reg  error;

localparam [1:0] RD_IDLE     = 2'd0;
localparam [1:0] RD_LAUNCH   = 2'd1;
localparam [1:0] RD_WAIT_I2C = 2'd2;

reg [1:0]  rd_state;
reg [7:0]  byte_index;
reg        i2c_start;
reg [15:0] i2c_word_addr;
wire [7:0] i2c_data_out;
wire       i2c_busy;
wire       i2c_done;
wire       i2c_error;

function [7:0] payload_byte;
	input [7:0] index; // 8 位索引可表示 0x00~0xFF，共 256 个数据
	begin
		payload_byte = index ^ 8'hA5;
	end
endfunction

at24c64_i2c_byte_r #(
	.CLK_FREQ(CLK_FREQ),
	.I2C_FREQ(I2C_FREQ),
	.SLAVE_ADDR(SLAVE_ADDR)
) u_at24c64_i2c_byte (
	.clk(clk),
	.rst_n(rst_n),
	.start(i2c_start),
	.read_req(1'b1),
	.word_addr(i2c_word_addr),
	.data_in(8'd0),
	.data_out(i2c_data_out),
	.busy(i2c_busy),
	.done(i2c_done),
	.error(i2c_error),
	.scl(scl),
	.sda(sda)
);

always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		rd_state      <= RD_IDLE;
		byte_index    <= 8'd0;
		i2c_start     <= 1'b0;
		i2c_word_addr <= 16'd0;
		busy          <= 1'b0;
		done          <= 1'b0;
		error         <= 1'b0;
		led           <= 1'b0;
	end else begin
		i2c_start <= 1'b0;
		done      <= 1'b0;

		case (rd_state)
			RD_IDLE: begin
				if (start) begin
					byte_index <= 8'd0;
					busy       <= 1'b1;
					error      <= 1'b0;
					led        <= 1'b0;
					rd_state   <= RD_LAUNCH;
				end
			end

			RD_LAUNCH: begin
				i2c_word_addr <= {8'h00, byte_index};
				i2c_start     <= 1'b1;
				rd_state      <= RD_WAIT_I2C;
			end

			RD_WAIT_I2C: begin
				if (i2c_done) begin
					if (i2c_error || (i2c_data_out != payload_byte(byte_index))) begin
						error    <= 1'b1;
						busy     <= 1'b0;
						done     <= 1'b1;
						rd_state <= RD_IDLE;
					end else if (byte_index == 8'hFF) begin
						busy     <= 1'b0;
						done     <= 1'b1;
						led      <= 1'b1;
						rd_state <= RD_IDLE;
					end else begin
						byte_index <= byte_index + 1'b1;
						rd_state   <= RD_LAUNCH;
					end
				end
			end

			default: begin
				rd_state <= RD_IDLE;
				busy     <= 1'b0;
				error    <= 1'b1;
				done     <= 1'b1;
			end
		endcase
	end
end

endmodule
