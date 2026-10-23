create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

derive_pll_clocks
derive_clock_uncertainty

set clk42 {pll|altpll_component|auto_generated|pll1|clk[0]}
set clksd {pll|altpll_component|auto_generated|pll1|clk[1]}

# SDRAM: DRAM_CLK is PLL clk[1], clk[0] advanced by 2 ns
set_input_delay  -clock [get_clocks $clksd] -reference_pin [get_ports {DRAM_CLK}] -max 6.4 [get_ports {DRAM_DQ[*]}]
set_input_delay  -clock [get_clocks $clksd] -reference_pin [get_ports {DRAM_CLK}] -min 3.2 [get_ports {DRAM_DQ[*]}]
set_output_delay -clock [get_clocks $clksd] -reference_pin [get_ports {DRAM_CLK}] -max 1.5 [get_ports {DRAM_DQ[*] DRAM_ADDR[*] DRAM_BA_* DRAM_*_N DRAM_*DQM DRAM_CKE}]
set_output_delay -clock [get_clocks $clksd] -reference_pin [get_ports {DRAM_CLK}] -min -0.8 [get_ports {DRAM_DQ[*] DRAM_ADDR[*] DRAM_BA_* DRAM_*_N DRAM_*DQM DRAM_CKE}]

# VGA pins only need to arrive together
set_output_delay -clock [get_clocks $clk42] -max 0 [get_ports {VGA_*}]
set_output_delay -clock [get_clocks $clk42] -min -5 [get_ports {VGA_*}]
set_multicycle_path -to [get_ports {VGA_*}] -setup 2
set_multicycle_path -to [get_ports {VGA_*}] -hold 1

set_false_path -from [get_ports {BUTTON[*] SW[*] PS2_* UART_RXD CASS_IN}]
set_false_path -to   [get_ports {LEDG[*] UART_TXD AUDIO_OUT}]

# SDRAM read data is captured one full clk[0] cycle after the clk[1] edge that
# launches it (sdram.v samples sd_data in STATE_CMD_READ)
set_multicycle_path -from [get_clocks $clksd] -to [get_clocks $clk42] -setup 2
set_multicycle_path -from [get_clocks $clksd] -to [get_clocks $clk42] -hold 1
