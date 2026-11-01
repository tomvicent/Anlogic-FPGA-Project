# 1. 约束主时钟：50MHz，周期20ns
create_clock -name sys_clk -period 10 [get_ports sys_clk]

# 2. 约束输入延迟（低速接口简单约束即可）
set_input_delay -max 2 -clock sys_clk [get_ports {key[0] key[1] rs485_uart_rxd}]
set_input_delay -min 0 -clock sys_clk [get_ports {key[0] key[1] rs485_uart_rxd}]

# 3. 约束输出延迟
set_output_delay -max 2 -clock sys_clk [get_ports {led[0] led[1] rs485_uart_txd RS485_DE0}]
set_output_delay -min 0 -clock sys_clk [get_ports {led[0] led[1] rs485_uart_txd RS485_DE0}]

# 4. 异步输入设为伪路径（按键、UART接收都是异步信号，无需严格时序检查）
set_false_path -from [get_ports {key[0] key[1] rs485_uart_rxd}]
