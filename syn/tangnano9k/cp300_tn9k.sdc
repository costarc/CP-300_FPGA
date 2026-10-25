create_clock -name clk27 -period 37.037 -waveform {0 18.518} [get_ports {clk27}]

# the PLL outputs are derived by the tools; the asynchronous inputs need no timing
set_false_path -from [get_ports {btn_s1_n btn_s2_n ps2_clk ps2_dat uart_rx cass_in kbd_col[*] kbd_reset_n sd_miso}]
set_false_path -to   [get_ports {led_n[*] uart_tx audio_out kbd_row[*]}]

# The Z80s only change state on their clock enable: ht1080z's every 21st clock, the IO controller's
# every 2nd. Paths inside a T80 get that many clocks. WAIT_n for the main CPU comes from a register
# (wait_r) that changes at least 4 clocks before an enable.
set_multicycle_path -from [get_pins {ht1080z/cpu/u0/*/Q ht1080z/cpu/u0/*/*/Q ht1080z/cpu/u0/*/*/DO[*]}] -to [get_pins {ht1080z/cpu/u0/*/D ht1080z/cpu/u0/*/DI[*] ht1080z/cpu/u0/*/CE ht1080z/cpu/u0/*/*/D ht1080z/cpu/u0/*/*/DI[*] ht1080z/cpu/u0/*/*/CE ht1080z/cpu/u0/*/*/WAD[*] ht1080z/cpu/u0/*/*/WRE ht1080z/cpu/u0/*/*/AD[*]}] -setup -end 4
set_multicycle_path -from [get_pins {ht1080z/cpu/u0/*/Q ht1080z/cpu/u0/*/*/Q ht1080z/cpu/u0/*/*/DO[*]}] -to [get_pins {ht1080z/cpu/u0/*/D ht1080z/cpu/u0/*/DI[*] ht1080z/cpu/u0/*/CE ht1080z/cpu/u0/*/*/D ht1080z/cpu/u0/*/*/DI[*] ht1080z/cpu/u0/*/*/CE ht1080z/cpu/u0/*/*/WAD[*] ht1080z/cpu/u0/*/*/WRE ht1080z/cpu/u0/*/*/AD[*]}] -hold -end 3
set_multicycle_path -from [get_pins {io_ctrl/cpu/u0/*/Q io_ctrl/cpu/u0/*/*/Q io_ctrl/cpu/u0/*/*/DO[*]}] -to [get_pins {io_ctrl/cpu/u0/*/D io_ctrl/cpu/u0/*/DI[*] io_ctrl/cpu/u0/*/CE io_ctrl/cpu/u0/*/*/D io_ctrl/cpu/u0/*/*/DI[*] io_ctrl/cpu/u0/*/*/CE io_ctrl/cpu/u0/*/*/WAD[*] io_ctrl/cpu/u0/*/*/WRE io_ctrl/cpu/u0/*/*/AD[*]}] -setup -end 2
set_multicycle_path -from [get_pins {io_ctrl/cpu/u0/*/Q io_ctrl/cpu/u0/*/*/Q io_ctrl/cpu/u0/*/*/DO[*]}] -to [get_pins {io_ctrl/cpu/u0/*/D io_ctrl/cpu/u0/*/DI[*] io_ctrl/cpu/u0/*/CE io_ctrl/cpu/u0/*/*/D io_ctrl/cpu/u0/*/*/DI[*] io_ctrl/cpu/u0/*/*/CE io_ctrl/cpu/u0/*/*/WAD[*] io_ctrl/cpu/u0/*/*/WRE io_ctrl/cpu/u0/*/*/AD[*]}] -hold -end 1
set_multicycle_path -from [get_pins {ht1080z/wait_r*/Q}] -to [get_pins {ht1080z/cpu/u0/*/D ht1080z/cpu/u0/*/CE ht1080z/cpu/u0/*/*/D ht1080z/cpu/u0/*/*/WRE}] -setup -end 3
set_multicycle_path -from [get_pins {ht1080z/wait_r*/Q}] -to [get_pins {ht1080z/cpu/u0/*/D ht1080z/cpu/u0/*/CE ht1080z/cpu/u0/*/*/D ht1080z/cpu/u0/*/*/WRE}] -hold -end 2

# Port latches (F4, E0, E4, EC) are only written on a CPU enable and are read many clocks later
set_multicycle_path -from [get_pins {ht1080z/f4_*/Q ht1080z/ec_*/Q ht1080z/intmask_*/Q ht1080z/nmimask_*/Q}] -to [get_pins {ht1080z/cpu/*/D ht1080z/cpu/*/CE ht1080z/cpu/u0/*/D ht1080z/cpu/u0/*/CE ht1080z/cpu/u0/*/*/D ht1080z/cpu/u0/*/*/WRE}] -setup -end 4
set_multicycle_path -from [get_pins {ht1080z/f4_*/Q ht1080z/ec_*/Q ht1080z/intmask_*/Q ht1080z/nmimask_*/Q}] -to [get_pins {ht1080z/cpu/*/D ht1080z/cpu/*/CE ht1080z/cpu/u0/*/D ht1080z/cpu/u0/*/CE ht1080z/cpu/u0/*/*/D ht1080z/cpu/u0/*/*/WRE}] -hold -end 3

# The OSD takes the IO controller's SPI port (SCK divided from clk42, slow, data stable long before the edge)
create_clock -name clk42 -period 23.809 [get_nets {clk42}]
create_clock -name spi_sck -period 20 [get_nets {spi_sck_r_5}]
set_false_path -from [get_clocks {spi_sck}] -to [get_clocks {clk42}]
set_false_path -from [get_clocks {clk42}] -to [get_clocks {spi_sck}]
