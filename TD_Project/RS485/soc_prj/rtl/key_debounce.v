`timescale 1ns / 1ps

// Single active-low key: synchronize, debounce both edges, and pulse on press.
module key_debounce #(
    parameter integer CLK_FREQ    = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
) (
    input  wire clk,
    input  wire rst_n,
    input  wire key_in,     // Raw key input: 0 = pressed, 1 = released.
    output reg  key_value,  // Debounced level: 0 = pressed, 1 = released.
    output reg  key_flag    // One clock pulse for each debounced press.
);

// Parameters must be positive. Clamp sub-cycle intervals to one cycle.
localparam integer FILTER_CYCLES = (CLK_FREQ / 1000) * DEBOUNCE_MS;
localparam integer COUNT_MAX = (FILTER_CYCLES < 1) ? 1 : FILTER_CYCLES;
localparam integer COUNT_WIDTH = (COUNT_MAX <= 1) ? 1 : $clog2(COUNT_MAX);//自动计算出计数器位宽

(* ASYNC_REG = "TRUE" *) reg key_sync_0;
(* ASYNC_REG = "TRUE" *) reg key_sync_1;
reg [COUNT_WIDTH-1:0] count;

/*- 不把这两个寄存器优化掉或合并
- 尽量把它们摆得很近（减小时钟到输出的延迟，让亚稳态更快恢复）
- 不报相关的时序警告

**不加会怎样？** 逻辑功能一样，但综合器可能优化、移位，导致同步链效果变差，亚稳态概率上升。**异步输入打两拍时推荐加。**

> 
> 类似的属性还有 `(* keep = "TRUE" *)`（保留信号不优化）、`(* mark_debug = "TRUE" *)`（保留信号方便 ILA 抓波形）。*/

// Two flip-flops synchronize the asynchronous physical key input.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        key_sync_0 <= 1'b1;
        key_sync_1 <= 1'b1;
    end else begin
        key_sync_0 <= key_in;
        key_sync_1 <= key_sync_0;
    end
end

// Accept a new level only after COUNT_MAX consecutive differing samples.
// A bounce back to the accepted level restarts the debounce interval.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        count     <= {COUNT_WIDTH{1'b0}};
        key_value <= 1'b1;
        key_flag  <= 1'b0;
    end else begin
        key_flag <= 1'b0;
        if (key_sync_1 == key_value) begin
            count <= {COUNT_WIDTH{1'b0}};
        end else if (count == COUNT_MAX - 1) begin
            count     <= {COUNT_WIDTH{1'b0}};
            key_value <= key_sync_1;
            key_flag  <= ~key_sync_1;
        end else begin
            count <= count + 1'b1;
        end
    end
end

endmodule
