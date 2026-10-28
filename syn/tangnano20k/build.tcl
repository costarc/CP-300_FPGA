# Gowin command line build:  gw_sh build.tcl   (run in this folder)
# Needs the submodules. The ROMs are loaded from the SD card (no ROM package).
set root ../..
set tang $root/rtl/tang

add_file -type verilog board_tn20k.v
add_file -type verilog $tang/cp300_tang.v
add_file -type verilog $tang/pll_tang.v
add_file -type verilog $tang/sdram_ctrl.v
add_file -type verilog $tang/sdram.v
add_file -type verilog $tang/psram_arb.v
add_file -type verilog $tang/ram_bridge.v
add_file -type verilog $tang/fb_writer.v
add_file -type verilog $tang/fb_scanout.v
add_file -type verilog $tang/sync_stable.v
add_file -type verilog $tang/dvi_tx.v
add_file -type verilog $tang/osd.v

add_file -type vhdl $root/syn/analogue/src/fpga/core/cp300_roms_stub.vhd
add_file -type vhdl $root/rtl/cp300/cp300_rom.vhd
add_file -type vhdl $root/rtl/kbd/matrix_kbd.vhd
add_file -type vhdl $root/rtl/fdc/wd1793.vhd
add_file -type vhdl $root/rtl/hdc/wd1010.vhd
add_file -type vhdl $root/rtl/io/io_fw_pkg.vhd
add_file -type vhdl $root/rtl/io/io_ctrl.vhd
add_file -type vhdl $root/rtl/ht1080z/ht1080z.vhd
add_file -type vhdl $root/rtl/ht1080z/videoctrl.vhd
add_file -type vhdl $root/rtl/ht1080z/ps2kbd.vhd
add_file -type vhdl $root/rtl/ht1080z/ps2reader.vhd
add_file -type vhdl $root/rtl/ht1080z/YM2149.vhd
add_file -type vhdl $root/rtl/ht1080z/vol_table_array.vhd
add_file -type verilog $root/rtl/ht1080z/trs80_rs232.v
add_file -type verilog $root/rtl/ht1080z/gen_uart.v
foreach f {T80_Pack T80_ALU T80_MCode T80_Reg T80 T80s} {
    add_file -type vhdl $root/rtl/T80/$f.vhd
}
add_file -type vhdl $root/rtl/mist-modules/dac.vhd

add_file -type cst cp300_tn20k.cst
add_file -type sdc cp300_tn20k.sdc

set_device GW2AR-LV18QN88C8/I7 -name GW2AR-18C
set_option -top_module cp300_tang
set_option -verilog_std sysv2017
set_option -vhdl_std vhd2008
set_option -use_sspi_as_gpio 1
set_option -use_mspi_as_gpio 0
set_option -use_ready_as_gpio 0
set_option -use_done_as_gpio 0
set_option -use_reconfign_as_gpio 0
set_option -use_i2c_as_gpio 0
set_option -gen_text_timing_rpt 1
set_option -output_base_name cp300_tn20k

run all
