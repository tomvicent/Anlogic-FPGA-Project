// OLED I2C 写入示例
//
// 上电复位释放后，本模块自动执行两笔 I2C 写事务：
//   1) 控制字节 0x00 + OLED 初始化命令 + 页/列位置命令
//   2) 控制字节 0x40 + 连续 16 个测试数据字节
//
// 本例使用 SSD1306 常见的 7 位 I2C 地址 0x3C。SCL/SDA 都采用开漏方式，
// 外部需要接上拉电阻。此精简例程不支持从机时钟拉伸和自动重试。

module oled_i2c_demo #(
    parameter integer CLK_FREQ = 50_000_000, // FPGA 输入时钟频率，单位 Hz；按实际系统时钟修改
    parameter integer I2C_FREQ = 250_000,    // I2C 的 SCL 目标频率，单位 Hz；默认 250 kHz
    parameter [6:0]   OLED_ADDR = 7'h3C      // OLED 的 7 位从机地址，常见为 0x3C 或 0x3D
)(
    input  wire clk,
    input  wire rst_n,
    inout  wire scl,
    inout  wire sda,
    output reg  busy,
    output reg  done,
    output reg  error
);

localparam integer DIVIDER = CLK_FREQ / (I2C_FREQ * 4); // 四分频计数值：每个 SCL 周期分成 4 个时序阶段

localparam [2:0] ST_START = 3'd0; // 产生 I2C 起始条件，并准备从机地址
localparam [2:0] ST_SEND  = 3'd1; // 按高位优先发送当前字节的 8 个数据位
localparam [2:0] ST_ACK   = 3'd2; // 释放 SDA 并采样从机的 ACK/NACK
localparam [2:0] ST_STOP  = 3'd3; // 产生 I2C 停止条件
localparam [2:0] ST_IDLE  = 3'd4; // 示例完成后停留的空闲状态

reg [31:0] div_cnt; // 系统时钟分频计数器
reg        tick;    // 分频节拍；每次计满产生一个时序步进脉冲

reg [2:0]  state;           // 当前 I2C 状态
reg [1:0]  phase;           // 当前状态内部的时序阶段
reg [2:0]  bit_idx;         // 当前发送到字节的哪一位：7 到 0
reg [5:0]  payload_idx;     // 当前事务中正在发送的字节编号
reg        transaction;     // 0：初始化/命令事务；1：连续显示数据事务
reg        sending_address; // 1：当前发送的是从机地址字节；0：当前发送 OLED 控制/数据字节
reg [7:0]  tx_byte;         // 当前待发送的 8 位字节
reg        ack_sample;      // 保存采样到的应答位：0=ACK，1=NACK
reg        scl_pull_low;    // SCL 开漏控制：1=主动拉低，0=释放总线
reg        sda_pull_low;    // SDA 开漏控制：1=主动拉低，0=释放总线

assign scl = scl_pull_low ? 1'b0 : 1'bz; // 开漏 SCL：不输出高电平，释放时由上拉电阻拉高
assign sda = sda_pull_low ? 1'b0 : 1'bz; // 开漏 SDA：不输出高电平，释放时由上拉电阻拉高

// 将一个 8 位数据编号转换成要发给 OLED 的字节。
// transaction=0：控制字节 0x00 和初始化/定位命令。
// transaction=1：控制字节 0x40 和 16 个交替的测试图案字节。
function [7:0] payload_byte;
    input       transaction_sel;
    input [5:0] index;
    begin
        if (transaction_sel == 1'b0) begin
            case (index)
                6'd0:  payload_byte = 8'h00; // OLED 命令控制字节
                6'd1:  payload_byte = 8'hAE; // 关闭显示
                6'd2:  payload_byte = 8'hD5;
                6'd3:  payload_byte = 8'h80;
                6'd4:  payload_byte = 8'hA8;
                6'd5:  payload_byte = 8'h3F;
                6'd6:  payload_byte = 8'hD3;
                6'd7:  payload_byte = 8'h00;
                6'd8:  payload_byte = 8'h40;
                6'd9:  payload_byte = 8'hA1;
                6'd10: payload_byte = 8'hC8;
                6'd11: payload_byte = 8'hDA;
                6'd12: payload_byte = 8'h12;
                6'd13: payload_byte = 8'h81;
                6'd14: payload_byte = 8'hCF;
                6'd15: payload_byte = 8'hD9;
                6'd16: payload_byte = 8'hF1;
                6'd17: payload_byte = 8'hDB;
                6'd18: payload_byte = 8'h30;
                6'd19: payload_byte = 8'hA4;
                6'd20: payload_byte = 8'hA6;
                6'd21: payload_byte = 8'h8D;
                6'd22: payload_byte = 8'h14;
                6'd23: payload_byte = 8'hAF; // 打开显示
                6'd24: payload_byte = 8'hB0; // 第 0 页
                6'd25: payload_byte = 8'h10; // 列地址高位
                6'd26: payload_byte = 8'h00; // 列地址低位
                default: payload_byte = 8'h00;
            endcase
        end else begin
            if (index == 6'd0)
                payload_byte = 8'h40; // OLED 显示数据控制字节
            else if (index[0] == 1'b1)//这个是表示后计数就是AA
                payload_byte = 8'hAA;
            else
                payload_byte = 8'h55;
        end
    end
endfunction

// 产生 I2C 四分之一周期的节拍。状态机每个 I2C 位使用四个 phase：
// SCL 低并设置 SDA、SCL 高、保持高、SCL 拉低。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        div_cnt <= 32'd0;
        tick    <= 1'b0;
    end else if (div_cnt == DIVIDER - 1) begin
        div_cnt <= 32'd0;
        tick    <= 1'b1;
    end else begin
        div_cnt <= div_cnt + 1'b1;
        tick    <= 1'b0;
    end
end

// I2C 发送状态机：先发从机地址+写位，再依次发 payload_byte() 提供的字节。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state            <= ST_START;
        phase            <= 2'd0;
        bit_idx          <= 3'd7;
        payload_idx      <= 6'd0;
        transaction      <= 1'b0;
        sending_address  <= 1'b1;
        tx_byte          <= 8'd0;
        ack_sample       <= 1'b1;
        scl_pull_low     <= 1'b0;
        sda_pull_low     <= 1'b0;
        busy             <= 1'b1;
        done             <= 1'b0;
        error            <= 1'b0;
    end else begin
        done <= 1'b0;

        if (tick) begin
            case (state)
                ST_START: begin
                    case (phase)
                        2'd0: begin // 总线空闲：释放 SCL 和 SDA
                            scl_pull_low <= 1'b0;
                            sda_pull_low <= 1'b0;
                            phase        <= 2'd1;
                        end
                        2'd1: begin // SCL 为高时，SDA 拉低，产生 START
                            scl_pull_low <= 1'b0;
                            sda_pull_low <= 1'b1;
                            phase        <= 2'd2;
                        end
                        default: begin // 拉低 SCL，准备发送地址
                            scl_pull_low    <= 1'b1;
                            sda_pull_low    <= 1'b1;
                            tx_byte         <= {OLED_ADDR, 1'b0};//发送主机地址和读或者写的命令
                            bit_idx         <= 3'd7;//当前发送到字节的哪一位从7到0 这样子发送
                            sending_address <= 1'b1;//1表示发送的是从机的地址字节
                            phase           <= 2'd0;//将拍数至0
                            state           <= ST_SEND;//切换到发送数据的模式
                        end
                    endcase
                end

                ST_SEND: begin
                    case (phase)
                        2'd0: begin // SCL 低时设置当前数据位；0 拉低，1 释放
                            scl_pull_low <= 1'b1;
                            sda_pull_low <= (tx_byte[bit_idx] == 1'b0);//这个其实就是发数据了，这里刚好四拍
                            phase        <= 2'd1;
                        end
                        2'd1: begin
                            scl_pull_low <= 1'b0; // SCL 高，从机采样数据位
                            phase        <= 2'd2;
                        end
                        2'd2: begin
                            scl_pull_low <= 1'b0; // 高电平保持
                            phase        <= 2'd3;
                        end
                        default: begin
                            scl_pull_low <= 1'b1;
                            phase        <= 2'd0;
                            if (bit_idx == 3'd0) begin
                                state <= ST_ACK;
                            end else begin
                                bit_idx <= bit_idx - 1'b1;
                            end
                        end
                    endcase
                end

                ST_ACK: begin
                    case (phase)
                        2'd0: begin
                            scl_pull_low <= 1'b1;
                            sda_pull_low <= 1'b0; // 释放 SDA，由从机发送 ACK/NACK
                            phase        <= 2'd1;
                        end
                        2'd1: begin
                            scl_pull_low <= 1'b0;
                            phase        <= 2'd2;
                        end
                        2'd2: begin
                            scl_pull_low <= 1'b0;
                            ack_sample   <= sda; // SCL 已经为高；0=ACK，1=NACK
                            phase        <= 2'd3;
                        end
                        default: begin
                            scl_pull_low <= 1'b1;
                            phase        <= 2'd0;
                            if (ack_sample == 1'b1) begin
                                error <= 1'b1;
                                state <= ST_STOP;
                            end else if (sending_address) begin
                                sending_address <= 1'b0;
                                payload_idx     <= 6'd0;
                                tx_byte         <= payload_byte(transaction, 6'd0);
                                bit_idx         <= 3'd7;
                                state           <= ST_SEND;
                            end else if ((!transaction && payload_idx == 6'd26) ||
                                         ( transaction && payload_idx == 6'd16)) begin
                                state <= ST_STOP;
                            end else begin
                                payload_idx <= payload_idx + 1'b1;
                                tx_byte     <= payload_byte(transaction, payload_idx + 1'b1);
                                bit_idx     <= 3'd7;
                                state       <= ST_SEND;
                            end
                        end
                    endcase
                end

                ST_STOP: begin
                    case (phase)
                        2'd0: begin // SCL 低时拉低 SDA
                            scl_pull_low <= 1'b1;
                            sda_pull_low <= 1'b1;
                            phase        <= 2'd1;
                        end
                        2'd1: begin // SCL 拉高，SDA 仍保持低
                            scl_pull_low <= 1'b0;
                            sda_pull_low <= 1'b1;
                            phase        <= 2'd2;
                        end
                        2'd2: begin // SCL 为高时释放 SDA，产生 STOP
                            scl_pull_low <= 1'b0;
                            sda_pull_low <= 1'b0;
                            phase        <= 2'd3;
                        end
                        default: begin
                            phase <= 2'd0;
                            if (error) begin
                                busy  <= 1'b0;
                                done  <= 1'b1;
                                state <= ST_IDLE;
                            end else if (transaction == 1'b0) begin
                                transaction <= 1'b1;
                                state       <= ST_START;
                            end else begin
                                busy  <= 1'b0;
                                done  <= 1'b1;
                                state <= ST_IDLE;
                            end
                        end
                    endcase
                end

                default: begin // ST_IDLE：示例执行完成后停在这里
                    scl_pull_low <= 1'b0;
                    sda_pull_low <= 1'b0;
                end
            endcase
        end
    end
end

endmodule
