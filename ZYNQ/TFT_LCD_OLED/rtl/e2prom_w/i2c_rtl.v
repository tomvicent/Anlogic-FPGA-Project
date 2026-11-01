module at24c64_i2c_byte_w #(
	parameter integer CLK_FREQ = 50_000_000,
	parameter integer I2C_FREQ = 100_000,
	parameter [6:0] SLAVE_ADDR = 7'h50
)(
	input  wire clk,
	input  wire rst_n,
	input  wire start,
	input  wire read_req,
	input  wire [15:0] word_addr,
	input  wire [7:0] data_in,
	output reg  [7:0] data_out,
	output reg  busy,
	output reg  done,
	output reg  error,
	inout  wire scl,
	inout  wire sda
);

// I2C 总线时钟分频参数：
// 目标 I2C 时钟 = I2C_FREQ，实际控制时序按 1/4 周期来切换，
// 用于生成 START/STOP、SCL 上升/下降沿与数据稳定窗口。
localparam integer QUARTER_DIV = CLK_FREQ / (I2C_FREQ * 4);

// 状态机状态编码：
// ST_IDLE    : 空闲，等待 start 信号
// ST_START   : 产生 START 条件
// ST_TX_BYTE : 发送一字节数据
// ST_ACK     : 检查从机 ACK
// ST_RESTART : 读模式时重新发送 START
// ST_RX_BYTE : 接收一字节数据
// ST_MASTER_NACK : 主机发 NACK
// ST_STOP    : 产生 STOP 条件
// ST_FINISH  : 结束事务
localparam [3:0] ST_IDLE       = 4'd0;
localparam [3:0] ST_START      = 4'd1;
localparam [3:0] ST_TX_BYTE    = 4'd2;
localparam [3:0] ST_ACK        = 4'd3;
localparam [3:0] ST_RESTART    = 4'd4;
localparam [3:0] ST_RX_BYTE    = 4'd5;
localparam [3:0] ST_MASTER_NACK = 4'd6;
localparam [3:0] ST_STOP       = 4'd7;
localparam [3:0] ST_FINISH     = 4'd8;

// 当前正在发送的类型：
// TX_DEV_WRITE : 设备地址+写位
// TX_ADDR_HIGH : 字地址高 8bit
// TX_ADDR_LOW  : 字地址低 8bit
// TX_DATA      : 数据字节
// TX_DEV_READ  : 设备地址+读位
localparam [2:0] TX_DEV_WRITE  = 3'd0;
localparam [2:0] TX_ADDR_HIGH  = 3'd1;
localparam [2:0] TX_ADDR_LOW   = 3'd2;
localparam [2:0] TX_DATA       = 3'd3;
localparam [2:0] TX_DEV_READ   = 3'd4;

// 状态机主变量：
reg [3:0]  state;        // 当前状态
reg [1:0]  phase;        // 当前状态中的小阶段计数
reg [2:0]  tx_kind;      // 当前要发送的内容类型
reg [7:0]  tx_shift;     // 待发送字节移位寄存器
reg [7:0]  rx_shift;     // 接收字节缓存
reg [7:0]  data_latch;   // 发送数据缓存
reg [15:0] addr_latch;   // 16bit 字地址缓存
reg [2:0]  bit_index;    // 当前发送/接收的 bit 位索引
reg [31:0] divider_count; // 时序分频计数器
reg        read_latch;    // 标记当前事务是读还是写

// ACK 检测缓存：记录从机是否应答
reg        ack_sample;

// I2C 总线驱动控制：
// scl_drive_low = 1 时，主机主动拉低 SCL
// sda_drive_low = 1 时，主机主动拉低 SDA
// 否则保持高阻态（Z），让从机控制总线
reg        scl_drive_low;
reg        sda_drive_low;

// 在这里将 SDA/SCL 作为 bidirectional 端口输出：
// 低电平由 FPGA 主导拉低，高电平通过高阻态让外部上拉电阻拉高。
assign scl = scl_drive_low ? 1'b0 : 1'bz;
assign sda = sda_drive_low ? 1'b0 : 1'bz;

always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		state          <= ST_IDLE;
		phase          <= 2'd0;
		tx_kind        <= TX_DEV_WRITE;
		tx_shift       <= 8'd0;
		rx_shift       <= 8'd0;
		data_latch     <= 8'd0;
		addr_latch     <= 16'd0;
		bit_index      <= 3'd7;
		divider_count  <= 32'd0;
		read_latch     <= 1'b0;
		ack_sample     <= 1'b0;
		scl_drive_low  <= 1'b0;
		sda_drive_low  <= 1'b0;
		data_out       <= 8'd0;
		busy           <= 1'b0;
		done           <= 1'b0;
		error          <= 1'b0;
	end else begin
		done <= 1'b0;

		if (state == ST_IDLE && start) begin
			read_latch    <= read_req;
			addr_latch    <= word_addr;
			data_latch    <= data_in;
			error         <= 1'b0;
			busy          <= 1'b1;
			phase         <= 2'd0;
			divider_count <= 32'd0;
			scl_drive_low <= 1'b0;
			sda_drive_low <= 1'b0;
			state         <= ST_START;
		end else if (state != ST_IDLE) begin
            /*
            在这里要大于等于 QUARTER_DIV - 1，因为是从0开始计数的，所以要大于等于计数了50个周期相当于
            一个phase的时间就是1ms，然后再分成4份来实现SCL和SDA的上升下降沿和采样保持的时间
			*/
            if (divider_count >= QUARTER_DIV - 1) begin
				divider_count <= 32'd0;
				case (state)
					ST_START: begin
						case (phase)
							2'd0: begin
								scl_drive_low <= 1'b0;
								sda_drive_low <= 1'b0;
								phase <= 2'd1;
							end
							2'd1: phase <= 2'd2;
							2'd2: begin
								scl_drive_low <= 1'b0;
								sda_drive_low <= 1'b1;
								phase <= 2'd3;
							end
							default: begin//第四个实现开始发送主机的地址+写命令
								scl_drive_low <= 1'b1;
								tx_shift      <= {SLAVE_ADDR, 1'b0};
								tx_kind       <= TX_DEV_WRITE;
								bit_index     <= 3'd7;
								phase         <= 2'd0;
								state         <= ST_TX_BYTE;
							end
						endcase
					end

					ST_TX_BYTE: begin
						case (phase)
							2'd0: begin
								scl_drive_low <= 1'b1;
								sda_drive_low <= ~tx_shift[bit_index];
								phase <= 2'd1;
							end
							2'd1: phase <= 2'd2;
							2'd2: begin
								scl_drive_low <= 1'b0;
								phase <= 2'd3;
							end
							default: begin//八个数据没发完就继续重复发送数据，直到结束
								scl_drive_low <= 1'b0;
								if (bit_index == 3'd0) begin
									phase <= 2'd0;
									state <= ST_ACK;
								end else begin
									bit_index <= bit_index - 1'b1;
									phase <= 2'd0;
								end
							end
						endcase
					end

					ST_ACK: begin
						case (phase)
							2'd0: begin
								scl_drive_low <= 1'b1;
								sda_drive_low <= 1'b0;
								phase <= 2'd1;
							end
							2'd1: phase <= 2'd2;
							2'd2: begin//在这里由从机来拉低SDA线，表示应答ACK
								scl_drive_low <= 1'b0;
								ack_sample <= sda;
								phase <= 2'd3;
							end
							default: begin
								scl_drive_low <= 1'b0;
								sda_drive_low <= 1'b0;
								phase <= 2'd0;
                                //如果SDA仍然是高的话，代表从机并没有应答，收不到数据
								if (ack_sample == 1'b1) begin
									error <= 1'b1;
									state <= ST_STOP;
								end 
                                else begin
									case (tx_kind)//根据当前发送的类型来判断下一步的状态
										TX_DEV_WRITE: begin
											tx_shift  <= addr_latch[15:8];//发送字地址的高8位
											tx_kind   <= TX_ADDR_HIGH;
											bit_index <= 3'd7;
											state     <= ST_TX_BYTE;
										end
										TX_ADDR_HIGH: begin
											tx_shift  <= addr_latch[7:0];
											tx_kind   <= TX_ADDR_LOW;//发送字地址的低8位
											bit_index <= 3'd7;
											state     <= ST_TX_BYTE;
										end
										TX_ADDR_LOW: begin
											if (read_latch) begin
												state <= ST_RESTART;
											end else begin
												tx_shift  <= data_latch;
												tx_kind   <= TX_DATA;//表示地址的低八位发送完成开始，发送数据
												bit_index <= 3'd7;
												state     <= ST_TX_BYTE;
											end
										end
										TX_DATA: state <= ST_STOP;
										TX_DEV_READ: begin
											rx_shift <= 8'd0;
											bit_index <= 3'd7;
											state <= ST_RX_BYTE;
										end
										default: state <= ST_STOP;
									endcase
								end
							end
						endcase
					end

					// ST_RESTART: begin
					// 	case (phase)
					// 		2'd0: begin
					// 			scl_drive_low <= 1'b1;
					// 			sda_drive_low <= 1'b0;
					// 			phase <= 2'd1;
					// 		end
					// 		2'd1: phase <= 2'd2;
					// 		2'd2: begin
					// 			scl_drive_low <= 1'b0;
					// 			sda_drive_low <= 1'b1;
					// 			phase <= 2'd3;
					// 		end
					// 		default: begin
					// 			scl_drive_low <= 1'b0;
					// 			tx_shift      <= {SLAVE_ADDR, 1'b1};
					// 			tx_kind       <= TX_DEV_READ;
					// 			bit_index     <= 3'd7;
					// 			phase         <= 2'd0;
					// 			state         <= ST_TX_BYTE;
					// 		end
					// 	endcase
					// end

					// ST_RX_BYTE: begin
					// 	case (phase)
					// 		2'd0: begin
					// 			scl_drive_low <= 1'b1;
					// 			sda_drive_low <= 1'b0;
					// 			phase <= 2'd1;
					// 		end
					// 		2'd1: phase <= 2'd2;
					// 		2'd2: begin
					// 			scl_drive_low <= 1'b0;
					// 			rx_shift <= {rx_shift[6:0], sda};
					// 			phase <= 2'd3;
					// 		end
					// 		default: begin
					// 			scl_drive_low <= 1'b0;
					// 			if (bit_index == 3'd0) begin
					// 				data_out <= rx_shift;
					// 				phase <= 2'd0;
					// 				state <= ST_MASTER_NACK;
					// 			end else begin
					// 				bit_index <= bit_index - 1'b1;
					// 				phase <= 2'd0;
					// 			end
					// 		end
					// 	endcase
					// end

					// ST_MASTER_NACK: begin
					// 	case (phase)
					// 		2'd0: begin
					// 			scl_drive_low <= 1'b1;
					// 			sda_drive_low <= 1'b0;
					// 			phase <= 2'd1;
					// 		end
					// 		2'd1: phase <= 2'd2;
					// 		2'd2: begin
					// 			scl_drive_low <= 1'b0;
					// 			phase <= 2'd3;
					// 		end
					// 		default: begin
					// 			scl_drive_low <= 1'b0;
					// 			state <= ST_STOP;
					// 			phase <= 2'd0;
					// 		end
					// 	endcase
					// end

					ST_STOP: begin
						case (phase)
							2'd0: begin
								scl_drive_low <= 1'b1;
								sda_drive_low <= 1'b1;
								phase <= 2'd1;
							end
							2'd1: phase <= 2'd2;
							2'd2: begin
								scl_drive_low <= 1'b0;
								sda_drive_low <= 1'b1;
								phase <= 2'd3;
							end
							default: begin
								scl_drive_low <= 1'b0;
								sda_drive_low <= 1'b0;
								state <= ST_FINISH;
								phase <= 2'd0;
							end
						endcase
					end

					ST_FINISH: begin
						busy <= 1'b0;
						done <= 1'b1;
						state <= ST_IDLE;
					end

					default: begin
						state <= ST_IDLE;
						scl_drive_low <= 1'b0;
						sda_drive_low <= 1'b0;
					end
				endcase
			end else begin
				divider_count <= divider_count + 1'b1;
			end
		end
	end
end

endmodule