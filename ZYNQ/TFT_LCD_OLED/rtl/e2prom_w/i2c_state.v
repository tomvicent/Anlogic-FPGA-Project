// AT24C64 256 字节自动写入模块。
// 将 e2prom_w 设为 FPGA 顶层，复位释放后写入地址 0x0000~0x00FF。
// 写入数据为 address ^ 8'hA5；本文件同时包含 I2C 字节读写驱动。
module e2prom_w_start_core #(
	parameter integer CLK_FREQ = 50_000_000,
	parameter integer I2C_FREQ = 250_000,
	parameter [6:0] SLAVE_ADDR = 7'h50,
	parameter integer WRITE_WAIT_MS = 5
)(
	input  wire clk,
	input  wire rst_n,
	input  wire start,
	inout  wire scl,
	inout  wire sda,
	output reg  led1,
	output reg  led2
);


reg  busy;
reg  done;
reg  error;


localparam integer WRITE_WAIT_CYCLES = (CLK_FREQ / 1000) * WRITE_WAIT_MS;
//等待5ms，AT24C64写入一个字节需要5ms的时间，写入一个字节后需要等待5ms才能继续写入下一个字节
localparam [2:0] WR_IDLE  = 3'd0;
localparam [2:0] WR_LAUNCH = 3'd1;
localparam [2:0] WR_WAIT_I2C = 3'd2;
localparam [2:0] WR_DELAY = 3'd3;

reg [2:0]  wr_state;
reg [7:0]  byte_index;
reg [31:0] wait_count;
reg        i2c_start;
reg [15:0] i2c_word_addr;
reg [7:0]  i2c_data_in;
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

at24c64_i2c_byte_w #(
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
		wr_state      <= WR_IDLE;
		byte_index    <= 8'd0;
		wait_count    <= 32'd0;
		i2c_start     <= 1'b0;
		i2c_word_addr <= 16'd0;
		i2c_data_in   <= 8'd0;
		busy          <= 1'b0;
		done          <= 1'b0;
		error         <= 1'b0;
		led1          <= 1'b0;
		led2          <= 1'b0;
	end else begin
		i2c_start <= 1'b0;
		done      <= 1'b0;

		case (wr_state)
			// WR_IDLE：空闲态，等待上层 start 信号触发一次完整的 256 字节写入流程
			WR_IDLE: begin
				if (start) begin
					byte_index <= 8'd0;  // 从地址 0x00 开始写
					busy       <= 1'b1;  // 说明当前正在写 EEPROM
					error      <= 1'b0;  // 清除错误标志
					led1       <= 1'b0;
					led2       <= 1'b0;
					wr_state   <= WR_LAUNCH;
				end
			end

			// WR_LAUNCH：准备第一个字节的数据和地址，然后发起一次 I2C 写事务
			WR_LAUNCH: begin
				i2c_word_addr <= {8'h00, byte_index};  // 16-bit 字地址，格式 {高8bit, 低8bit}
				i2c_data_in   <= payload_byte(byte_index); // 根据当前索引生成本次要写入的 8 位数据
				i2c_start     <= 1'b1;  // 触发底层 I2C 模块开始写一个字节
				wr_state      <= WR_WAIT_I2C;
			end

			// WR_WAIT_I2C：等待底层 I2C 一次字节写事务结束
			WR_WAIT_I2C: begin
				if (i2c_done) begin
					if (i2c_error) begin
						error    <= 1'b1;  // 从机未应答或写失败
						led1     <= 1'b1;  // 错误灯保持点亮，直到复位或重新开始
						led2     <= 1'b0;
						busy     <= 1'b0;
						done     <= 1'b1;
						wr_state <= WR_IDLE;
					end else begin
						wait_count <= 32'd0;  // 进入 5ms 写等待计时
						wr_state   <= WR_DELAY;
					end
				end
			end

			// WR_DELAY：等待 AT24C64 写入一个字节所需的内部写周期（WRITE_WAIT_MS）
			// 这里通常设为 5ms，确保 EEPROM 已经真正写进非易失存储器
			WR_DELAY: begin
				if (wait_count >= WRITE_WAIT_CYCLES - 1) begin
					wait_count <= 32'd0;
					if (byte_index == 8'hFF) begin//这里就是限制IIC写入的字节数，写完256个字节就退出写入流程
						busy     <= 1'b0;  // 最后一个字节写完，退出写入流程
						done     <= 1'b1;
						led1     <= 1'b0;
						led2     <= 1'b1;  // 全部 256 字节均收到 ACK 后点亮成功灯
						wr_state <= WR_IDLE;
					end else begin
						byte_index <= byte_index + 1'b1;  // 下一地址
						wr_state   <= WR_LAUNCH;          // 继续写下一个字节
					end
				end else begin
					wait_count <= wait_count + 1'b1;
				end
			end

			// default：防止异常状态，强制回到空闲
			default: begin
				wr_state <= WR_IDLE;
			end
		endcase
	end
end

endmodule
