
derive_clocks
create_clock -name clk_mipi -period 6.4 -waveform {0 3.2} [get_pins {design_top_wrapper_u/u_mipi_dphy_rx_dr1_mipiio_wrapper/u_DR1_mipiio_wrapper/u_DR1_PHY_MIPIIO.hsrx_byteclk_to_fabric}]

# 约束命令，将从ps p2f_rst0_n开始的路径都设置为false path
set_false_path -from [get_nets {design_0_inst/design_0_ARM_Processor_System_0_Inst/p2f_rst0_n}]


set_clock_groups -exclusive  \
    -group [get_clocks { clk_mipi } ] \
    -group [get_clocks {design_0_inst/design_0_PLL_npu_Inst/dr1_phy_pll_dcc52a480158_Inst/u_DR1_PHY_PLL.clkc[0]}] \
    -group [get_clocks {design_0_inst/design_0_pll_75m_Inst/dr1_phy_pll_1f386b1db2c3_Inst/u_DR1_PHY_PLL.clkc[0]}]  \
    -group [get_clocks {design_top_wrapper_u/U_PLL/dr1_phy_pll_59fc11d80b0d_Inst/u_DR1_PHY_PLL.clkc[2]}]

    
set_clock_groups -exclusive  \
    -group [get_clocks { clk_mipi } ] \
    -group [get_clocks {design_0_inst/design_0_pll_150m_Inst/dr1_phy_pll_bdb046a15d6b_Inst/u_DR1_PHY_PLL.clkc[0]}]
