# Parameter overrides can append "(DEBOUNCE_MS=20)" to the XSim root name.
set rs485_top [current_scope]
if {![string match "*tb_rs485_key_led*" $rs485_top]} {error "Cannot find the RS485 testbench scope."}
foreach rs485_signal {sys_clk sys_rst_n key led rs485_uart_rxd rs485_uart_txd uut/key_data uut/uart_tx_en uut/uart_tx_data uut/uart_rx_done uut/uart_rx_data rx_byte received_byte} {
    set rs485_objects [get_objects $rs485_signal]
    if {$rs485_objects eq ""} {error "Missing waveform signal: $rs485_signal"}
    log_wave $rs485_signal
}
run all
quit
