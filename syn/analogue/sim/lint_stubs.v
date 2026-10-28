// Stand-ins for the VHDL entities and megafunctions, only so iverilog can elaborate core_top.v and
// catch port and declaration errors (syn/analogue/sim/lint.sh). They do nothing.
module ht1080z_ext (
	input clk42m, input pllLocked, input reset, output led, input ntsc, input [63:0] ext_keys, input turbo,
	input cass_in, output [1:0] cass_out,
	output fdc_svc_rd, output fdc_svc_wr, output fdc_svc_ra, output [7:0] fdc_svc_track, output [7:0] fdc_svc_trkreg,
	output [7:0] fdc_svc_sector, output fdc_svc_dam, input fdc_svc_ack, input fdc_res_found, input fdc_res_crc,
	input fdc_res_dam, input [8:0] fdc_buff_addr, input [7:0] fdc_buff_dout, output [7:0] fdc_buff_din,
	input fdc_buff_wr, output [1:0] fdc_drive, output fdc_side, input [3:0] drv_ready, input [3:0] drv_wp, output hd_svc, input [3:0] hd_flags,
	input ps2clk, input ps2dat, output [17:0] ht_rgb, output [17:0] vid_ink_rgb, output [17:0] vid_paper_rgb,
	output [17:0] vid_border_rgb, output vid_screen, output vid_ink, output vid_pxen, output hs, output vs,
	output hb, output vb, output [8:0] audiomix,
	input dn_go, input dn_wr, input [24:0] dn_addr, input [7:0] dn_data, input [4:0] dn_idx,
	output [15:0] exp_addr, output exp_in, output exp_out, output [7:0] exp_dout, input [7:0] exp_din, input exp_oe,
	output [15:0] ext_ram_addr, output ext_ram_rd, output ext_ram_wr, output [7:0] ext_ram_din,
	input [7:0] ext_ram_dout, input ext_ram_wait,
	output SDRAM_nCS, inout [15:0] SDRAM_DQ, output [12:0] SDRAM_A, output SDRAM_DQMH, output SDRAM_DQML,
	output SDRAM_nWE, output SDRAM_nCAS, output SDRAM_nRAS, output [1:0] SDRAM_BA, output SDRAM_CKE,
	input rl_clk, input rl_we, input [12:0] rl_waddr, input [31:0] rl_wdata);
endmodule

module io_ctrl_pocket #(parameter CPU_HALF = 1'b1) (
	input clk, input reset, output core_rst, output [7:0] dbg,
	input fdc_rd, input fdc_wr, input fdc_ra, input [7:0] fdc_track, input [7:0] fdc_trkreg, input [7:0] fdc_sector,
	input fdc_dam, output fdc_res_found, output fdc_res_crc, output fdc_res_dam, input [1:0] fdc_drive,
	input fdc_side, output fdc_ack, output [8:0] fdc_buff_addr, output [7:0] fdc_buff_dout, output fdc_buff_wr,
	input [7:0] fdc_buff_din, output [3:0] drv_ready, output [3:0] drv_wp, input hd_svc, output [3:0] hd_flags,
	output slot_req_tog, output slot_req_wr, output [2:0] slot_num, output [31:0] slot_offset, input slot_busy,
	input slot_err, output [8:0] rx_addr, input [7:0] rx_data, output tx_we, output [8:0] tx_addr,
	output [7:0] tx_data, input [7:0] slot_present, input [7:0] slot_changed, output [7:0] slot_chg_clr,
	input scan_valid, input opt_wp);
endmodule

module apf_dataslot (
	input clk_74a, input reset_n_74, input clk, input reset,
	input bridge_wr, input [31:0] bridge_addr, input [31:0] bridge_wr_data, output [31:0] tx_rd_data,
	input dataslot_update, input [15:0] dataslot_update_id,
	output target_dataslot_read, output target_dataslot_write, input target_dataslot_ack, input target_dataslot_done,
	input [2:0] target_dataslot_err, output [15:0] target_dataslot_id, output [31:0] target_dataslot_slotoffset,
	output [31:0] target_dataslot_bridgeaddr, output [31:0] target_dataslot_length,
	output [9:0] datatable_addr, input [31:0] datatable_q,
	input req_tog, input req_wr, input [2:0] req_slot, input [31:0] req_offset, output busy, output err,
	input [8:0] rx_addr, output [7:0] rx_data, input tx_we, input [8:0] tx_addr, input [7:0] tx_data,
	output [7:0] present, output [7:0] changed, input [7:0] chg_clr, output scan_valid);
endmodule

module osd_font (input clk, input [10:0] addr, output reg [7:0] dout,
	input rl_clk, input rl_we, input [12:0] rl_waddr, input [31:0] rl_wdata);
	always @(posedge clk) dout <= 8'h00;
endmodule

module mf_datatable (
	input [9:0] address_a, input [9:0] address_b, input clock_a, input clock_b, input [31:0] data_a,
	input [31:0] data_b, input wren_a, input wren_b, output [31:0] q_a, output [31:0] q_b);
	assign q_a = 32'h0; assign q_b = 32'h0;
endmodule

module altera_pll #(parameter fractional_vco_multiplier = "", reference_clock_frequency = "", operation_mode = "",
	number_of_clocks = 1, output_clock_frequency0 = "", phase_shift0 = "", duty_cycle0 = 50,
	output_clock_frequency1 = "", phase_shift1 = "", duty_cycle1 = 50,
	output_clock_frequency2 = "", phase_shift2 = "", duty_cycle2 = 50,
	output_clock_frequency3 = "", phase_shift3 = "", duty_cycle3 = 50,
	output_clock_frequency4 = "", phase_shift4 = "", duty_cycle4 = 50,
	output_clock_frequency5 = "", phase_shift5 = "", duty_cycle5 = 50,
	output_clock_frequency6 = "", phase_shift6 = "", duty_cycle6 = 50,
	output_clock_frequency7 = "", phase_shift7 = "", duty_cycle7 = 50,
	output_clock_frequency8 = "", phase_shift8 = "", duty_cycle8 = 50,
	output_clock_frequency9 = "", phase_shift9 = "", duty_cycle9 = 50,
	output_clock_frequency10 = "", phase_shift10 = "", duty_cycle10 = 50,
	output_clock_frequency11 = "", phase_shift11 = "", duty_cycle11 = 50,
	output_clock_frequency12 = "", phase_shift12 = "", duty_cycle12 = 50,
	output_clock_frequency13 = "", phase_shift13 = "", duty_cycle13 = 50,
	output_clock_frequency14 = "", phase_shift14 = "", duty_cycle14 = 50,
	output_clock_frequency15 = "", phase_shift15 = "", duty_cycle15 = 50,
	output_clock_frequency16 = "", phase_shift16 = "", duty_cycle16 = 50,
	output_clock_frequency17 = "", phase_shift17 = "", duty_cycle17 = 50,
	pll_type = "", pll_subtype = "") (
	input rst, output [number_of_clocks-1:0] outclk, output locked, output fboutclk, input fbclk, input refclk);
	assign outclk = {number_of_clocks{refclk}}; assign locked = 1'b1;
endmodule
