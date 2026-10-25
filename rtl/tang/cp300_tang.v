//============================================================================
//
//  CP-300 FPGA - top level for the Sipeed Tang Nano boards (9K: GW1NR-9C, 20K: GW2AR-18C)
//
//  Same core as the DE0 build (rtl/ht1080z + CP-300 ROM + WD1793 + SD/menu IO
//  controller), with these board differences:
//    - 27 MHz -> 42 MHz core PLL, and a second PLL for the HDMI pixel clock (25.2 MHz)
//    - Z80 RAM (48 KB) in the on-chip 8 MB RAM (9K: HyperRAM, 20K: SDRAM), not external SDRAM
//    - the picture is kept in a frame buffer in the same RAM and shown as standard
//      640x480 @ 60 Hz HDMI (DVI) on the board's HDMI connector
//    - the TF card slot on the board (SPI mode)
//    - PS/2 keyboard, the original CP-300 keyboard matrix, audio and cassette
//      input on the 2x24 headers, 3.3 V (see the README of the board)
//
//  Only the pin file (.cst) and the build script differ between the boards; the
//  design uses no more than a Tang Nano 9K has (the 20K build checks that).
//
//  Buttons:   S1 = reset, S2 = CPU turbo on/off
//  LEDs:      LED0 = running, LED1 = PLLs locked, LED2 = HyperRAM ready,
//             LED3 = turbo, LED5:4 = IO controller status
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.
//
//============================================================================

`ifdef BOARD_TN20K
`define TANG_DEVICE "GW2AR-18C"
`define TANG_CLKP_PSDA "1000"    // SDRAM clock: core clock 180 degrees later
`define BTN_ACTIVE_HIGH 1'b1      // the 20K's S1/S2 read high when pressed
`else
`define TANG_DEVICE "GW1NR-9C"
`define TANG_CLKP_PSDA "0100"    // HyperRAM clock: core clock 90 degrees later
`define BTN_ACTIVE_HIGH 1'b0      // the 9K's read low
`endif

module cp300_tang (
	input         clk27,
	input         btn_s1_n,     // reset
	input         btn_s2_n,     // turbo toggle
	output  [5:0] led_n,

	output        tmds_clk_p,
	output        tmds_clk_n,
	output  [2:0] tmds_d_p,
	output  [2:0] tmds_d_n,

	input         ps2_clk,
	input         ps2_dat,

	// original CP-300 keyboard: 3.3 V logic
	output  [7:0] kbd_row,      // row lines, low = selected
	input   [7:0] kbd_col,      // column lines, pulled up, a key pulls its column low
	input         kbd_reset_n,  // the keyboard's reset key(s), low = pressed

	output        sd_clk,
	output        sd_mosi,
	input         sd_miso,
	output        sd_cs_n,

	input         uart_rx,
	output        uart_tx,

	output        audio_out,    // sigma-delta, needs an RC filter
	input         cass_in,

`ifdef BOARD_TN20K
	// the 20K's embedded 64 Mbit SDRAM: the Gowin tools infer these pins from the names
	output        O_sdram_clk,
	output        O_sdram_cke,
	output        O_sdram_cs_n,
	output        O_sdram_cas_n,
	output        O_sdram_ras_n,
	output        O_sdram_wen_n,
	inout  [31:0] IO_sdram_dq,
	output [10:0] O_sdram_addr,
	output  [1:0] O_sdram_ba,
	output  [3:0] O_sdram_dqm
`else
	// the 9K's embedded HyperRAM: the Gowin tools infer these pins from the names
	output  [1:0] O_psram_ck,
	output  [1:0] O_psram_ck_n,
	inout   [1:0] IO_psram_rwds,
	inout  [15:0] IO_psram_dq,
	output  [1:0] O_psram_reset_n,
	output  [1:0] O_psram_cs_n
`endif
);

// ---------------------------------------------------------------- clocks
wire clk42, clk42_p, clk_tmds, clk_pix, pll_locked;
pll_tang #(.DEVICE(`TANG_DEVICE), .CLKP_PSDA(`TANG_CLKP_PSDA)) pll (
	.clk27(clk27),
	.clk(clk42),
	.clk_p(clk42_p),
	.clk_tmds(clk_tmds),
	.clk_pix(clk_pix),
	.locked(pll_locked)
);

// ---------------------------------------------------------------- reset, buttons
reg [15:0] por_cnt = 16'd0;
wire       por_done = &por_cnt;
always @(posedge clk42) begin
	if (!pll_locked)    por_cnt <= 16'd0;
	else if (!por_done) por_cnt <= por_cnt + 16'd1;
end

reg  [1:0] s1_s, s2_s, kbdres_s;
reg        s2_old;
reg        turbo = 1'b0;
reg [19:0] s2_db;                   // ~25 ms debounce
wire       mem_ready;
wire       core_rst, menu_open;
wire [7:0] io_dbg;
reg        reset = 1'b1;
reg        io_reset = 1'b1;

always @(posedge clk42) begin
	s1_s     <= {s1_s[0], btn_s1_n ^ `BTN_ACTIVE_HIGH};   // s1_s/s2_s: low = pressed
	s2_s     <= {s2_s[0], btn_s2_n ^ `BTN_ACTIVE_HIGH};
	kbdres_s <= {kbdres_s[0], kbd_reset_n};
	io_reset <= ~s1_s[1] | ~por_done;
	reset    <= ~s1_s[1] | ~kbdres_s[1] | ~por_done | ~mem_ready | core_rst;

	s2_old <= s2_s[1];
	if (s2_db != 20'd0) s2_db <= s2_db - 20'd1;
	else if (s2_old && !s2_s[1]) begin
		turbo <= ~turbo;
		s2_db <= 20'd1000000;
	end
end

// ---------------------------------------------------------------- HyperRAM
// shared by the Z80 RAM (client 0), the frame buffer writer (1) and the scan-out (2)
wire        ps_read, ps_write, ps_busy, ps_bw;
wire [21:0] ps_addr;
wire [15:0] ps_din, ps_dout;

`ifdef BOARD_TN20K
sdram_ctrl #(.FREQ(42_000_000)) psram (               // clk42_p is the 180 degree clock here
	.clk(clk42), .clk_sdram(clk42_p), .resetn(pll_locked),
	.read(ps_read), .write(ps_write), .byte_write(ps_bw),
	.addr(ps_addr), .din(ps_din), .dout(ps_dout), .busy(ps_busy),
	.SDRAM_DQ(IO_sdram_dq), .SDRAM_A(O_sdram_addr), .SDRAM_BA(O_sdram_ba), .SDRAM_nCS(O_sdram_cs_n),
	.SDRAM_nWE(O_sdram_wen_n), .SDRAM_nRAS(O_sdram_ras_n), .SDRAM_nCAS(O_sdram_cas_n),
	.SDRAM_CLK(O_sdram_clk), .SDRAM_CKE(O_sdram_cke), .SDRAM_DQM(O_sdram_dqm)
);
`else
PsramController #(.FREQ(42_000_000), .LATENCY(3)) psram (
	.clk(clk42), .clk_p(clk42_p), .resetn(pll_locked),
	.read(ps_read), .write(ps_write), .byte_write(ps_bw),
	.addr(ps_addr), .din(ps_din), .dout(ps_dout), .busy(ps_busy),
	.O_psram_ck(O_psram_ck), .IO_psram_rwds(IO_psram_rwds), .IO_psram_dq(IO_psram_dq),
	.O_psram_cs_n(O_psram_cs_n)
);
assign O_psram_reset_n = {1'b0, pll_locked};   // the second die stays in reset
`endif

wire        c0_req, c0_we, c0_ack, c1_req, c1_ack, c2_req, c2_ack;
wire [21:0] c0_addr, c1_addr, c2_addr;
wire [15:0] c0_din, c1_din, arb_dout;

psram_arb arb (
	.clk(clk42), .resetn(pll_locked), .ready(mem_ready),
	.c0_req(c0_req), .c0_we(c0_we), .c0_addr(c0_addr), .c0_din(c0_din), .c0_bw(1'b1),  .c0_ack(c0_ack),
	.c1_req(c1_req), .c1_we(1'b1),  .c1_addr(c1_addr), .c1_din(c1_din), .c1_bw(1'b0),  .c1_ack(c1_ack),
	.c2_req(c2_req), .c2_we(1'b0),  .c2_addr(c2_addr), .c2_din(16'd0),  .c2_bw(1'b0),  .c2_ack(c2_ack),
	.dout(arb_dout),
	.ps_read(ps_read), .ps_write(ps_write), .ps_bw(ps_bw), .ps_addr(ps_addr), .ps_din(ps_din),
	.ps_dout(ps_dout), .ps_busy(ps_busy)
);

wire [15:0] ext_addr;
wire        ext_rd, ext_wr, ext_stall;
wire  [7:0] ext_din, ext_dout;

ram_bridge bridge (
	.clk(clk42), .resetn(pll_locked),
	.rd(ext_rd), .wr(ext_wr), .a(ext_addr), .din(ext_din),
	.dout(ext_dout), .stall(ext_stall),
	.req(c0_req), .we(c0_we), .addr(c0_addr), .wdata(c0_din), .ack(c0_ack), .rdata(arb_dout)
);

// ---------------------------------------------------------------- core
wire        vid_screen, vid_ink, vid_pxen;
wire [17:0] ink_rgb, paper_rgb, border_rgb;
wire  [8:0] audio;
wire        hs, vs;
wire        ledb;
reg   [1:0] cass_s;
wire  [1:0] cass_out;
wire        uart_rts;

wire [63:0] ext_keys_raw;
matrix_kbd matrix_kbd (
	.clk(clk42),
	.row_n(kbd_row),
	.col_n(kbd_col),
	.keys(ext_keys_raw)
);

// What the CP-300 sees: nothing while the menu is open (the keys belong to the menu then), and no
// BREAK while SHIFT is down (SHIFT+BREAK opens the menu; the ROM treats it as BREAK anyway).
wire        shift_dn = ext_keys_raw[56] | ext_keys_raw[57];       // row 7: left / right shift
wire [63:0] ext_keys = menu_open ? 64'd0 : {ext_keys_raw[63:51], ext_keys_raw[50] & ~shift_dn, ext_keys_raw[49:0]};

wire  [7:0] fdc_track, fdc_trkreg, fdc_sector;
wire        fdc_rd, fdc_wr, fdc_ra, fdc_dam, fdc_ack, fdc_buff_wr, fdc_side;
wire        fdc_res_found, fdc_res_crc, fdc_res_dam;
wire  [8:0] fdc_buff_addr;
wire  [7:0] fdc_buff_dout, fdc_buff_din;
wire  [1:0] fdc_drive;
wire  [3:0] drv_ready, drv_wp;

always @(posedge clk42) cass_s <= {cass_s[0], cass_in};

wire [15:0] exp_addr;
wire  [7:0] exp_din, exp_dout;
wire        exp_in, exp_out, exp_oe;

// SDRAM ports are unused with EXT_RAM
wire        sd_nCS, sd_nWE, sd_nCAS, sd_nRAS;
wire [12:0] sd_a;
wire  [1:0] sd_ba;
wire [15:0] sd_dq;
wire        sd_dqmh, sd_dqml, sd_cke;

ht1080z #(.EXT_RAM(1'b1)) ht1080z (
	.clk42m (clk42),
	.pllLocked(pll_locked),
	.reset(reset),
	.led(ledb),
	.ntsc(1'b1),                // 60 Hz, as the PAL-M CP-300
	.turbo(turbo),
	.ext_keys(ext_keys),
	.cass_in(cass_s[1]),
	.cass_out(cass_out),

	.fdc_svc_rd(fdc_rd),
	.fdc_svc_wr(fdc_wr),
	.fdc_svc_ra(fdc_ra),
	.fdc_svc_track(fdc_track),
	.fdc_svc_trkreg(fdc_trkreg),
	.fdc_svc_sector(fdc_sector),
	.fdc_svc_dam(fdc_dam),
	.fdc_svc_ack(fdc_ack),
	.fdc_res_found(fdc_res_found),
	.fdc_res_crc(fdc_res_crc),
	.fdc_res_dam(fdc_res_dam),
	.fdc_buff_addr(fdc_buff_addr),
	.fdc_buff_dout(fdc_buff_dout),
	.fdc_buff_din(fdc_buff_din),
	.fdc_buff_wr(fdc_buff_wr),
	.fdc_drive(fdc_drive),
	.fdc_side(fdc_side),
	.drv_ready(drv_ready),
	.drv_wp(drv_wp),

	.ps2clk(ps2_clk | menu_open),   // the menu owns the keyboard while it is open
	.ps2dat(ps2_dat | menu_open),

	.ht_rgb(),
	.hs(hs),
	.vs(vs),
	.hb(),
	.vb(),
	.vid_screen(vid_screen),
	.vid_ink(vid_ink),
	.vid_pxen(vid_pxen),
	.vid_ink_rgb(ink_rgb),
	.vid_paper_rgb(paper_rgb),
	.vid_border_rgb(border_rgb),

	.audiomix(audio),

	.dn_go(1'b0),
	.dn_wr(1'b0),
	.dn_addr(25'd0),
	.dn_data(8'd0),
	.dn_idx(5'd0),

	.exp_addr(exp_addr),
	.exp_din(exp_din),
	.exp_dout(exp_dout),
	.exp_in(exp_in),
	.exp_out(exp_out),
	.exp_oe(exp_oe),

	.ext_ram_addr(ext_addr),
	.ext_ram_rd(ext_rd),
	.ext_ram_wr(ext_wr),
	.ext_ram_din(ext_din),
	.ext_ram_dout(ext_dout),
	.ext_ram_wait(ext_stall),

	.SDRAM_nCS(sd_nCS),
	.SDRAM_DQ(sd_dq),
	.SDRAM_A(sd_a),
	.SDRAM_DQMH(sd_dqmh),
	.SDRAM_DQML(sd_dqml),
	.SDRAM_nWE(sd_nWE),
	.SDRAM_nCAS(sd_nCAS),
	.SDRAM_nRAS(sd_nRAS),
	.SDRAM_BA(sd_ba),
	.SDRAM_CKE(sd_cke)
);

// 9600 8N1, ports E8-EA (USB serial of the board)
wire rs_tx;
trs80_rs232 rs232 (
	.clk(clk42),
	.reset(reset),
	.cfg(8'd0),
	.addr(exp_addr[2:0]),
	.e8(exp_addr[7:3] == 5'b11101),
	.in(exp_in),
	.out(exp_out),
	.din(exp_dout),
	.dout(exp_din),
	.oe(exp_oe),
	.uart_rx(uart_rx),
	.uart_tx(rs_tx),
	.uart_cts(1'b0),
	.uart_rts(uart_rts)
);
assign uart_tx = rs_tx;

// IO controller: SD card, on-screen menu, menu keyboard
wire spi_sck, spi_mosi, osd_ss3, sd_cs_o;
io_ctrl #(.CPU_HALF(1'b1)) io_ctrl (
	.clk(clk42),
	.reset(io_reset),
	.sd_cs_n(sd_cs_o),
	.spi_sck(spi_sck),
	.spi_mosi(spi_mosi),
	.sd_miso(sd_miso),
	.sd_wp_n(1'b1),
	.osd_ss3(osd_ss3),
	.ps2clk(ps2_clk),
	.ps2dat(ps2_dat),
	.ext_keys(ext_keys_raw),
	.menu_open(menu_open),
	.core_rst(core_rst),
	.dbg(io_dbg),
	.fdc_rd(fdc_rd),
	.fdc_wr(fdc_wr),
	.fdc_ra(fdc_ra),
	.fdc_track(fdc_track),
	.fdc_trkreg(fdc_trkreg),
	.fdc_sector(fdc_sector),
	.fdc_dam(fdc_dam),
	.fdc_res_found(fdc_res_found),
	.fdc_res_crc(fdc_res_crc),
	.fdc_res_dam(fdc_res_dam),
	.fdc_drive(fdc_drive),
	.fdc_side(fdc_side),
	.fdc_ack(fdc_ack),
	.fdc_buff_addr(fdc_buff_addr),
	.fdc_buff_dout(fdc_buff_dout),
	.fdc_buff_wr(fdc_buff_wr),
	.fdc_buff_din(fdc_buff_din),
	.drv_ready(drv_ready),
	.drv_wp(drv_wp)
);

assign sd_clk  = spi_sck;
assign sd_mosi = spi_mosi;
assign sd_cs_n = sd_cs_o;

// ---------------------------------------------------------------- video
// The core's picture (512 x 192, 1 bit per pixel) goes into a frame buffer in the HyperRAM; the scan-out
// reads it back as 640x480 @ 60 Hz with the menu OSD on top, and a DVI transmitter sends it.
wire [1:0] fb_latest, fb_disp;

fb_writer fbw (
	.clk(clk42), .resetn(pll_locked),
	.pxen(vid_pxen), .screen(vid_screen), .inkbit(vid_ink), .vs_n(vs),
	.req(c1_req), .addr(c1_addr), .data(c1_din), .ack(c1_ack),
	.latest(fb_latest), .disp_raw(fb_disp)
);

wire [7:0] v_r, v_g, v_b;
wire       v_hs, v_vs, v_de;

fb_scanout fbs (
	.clk(clk42), .resetn(pll_locked), .clk_pix(clk_pix),
	.req(c2_req), .addr(c2_addr), .ack(c2_ack), .rdata(arb_dout),
	.latest(fb_latest), .ink_rgb(ink_rgb), .paper_rgb(paper_rgb), .border_rgb(border_rgb),
	.disp_o(fb_disp),
	.spi_sck(spi_sck), .spi_ss3(osd_ss3), .spi_di(spi_mosi),
	.r(v_r), .g(v_g), .b(v_b), .hs(v_hs), .vs(v_vs), .de(v_de)
);

dvi_tx dvi (
	.clk_pix(clk_pix),
	.clk_5x(clk_tmds),
	.rst(~pll_locked),
	.r(v_r), .g(v_g), .b(v_b),
	.hs(v_hs), .vs(v_vs), .de(v_de),
	.tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
	.tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n)
);

// ---------------------------------------------------------------- audio
wire [14:0] audio_mix = {1'b0, audio, 5'd0};
dac #(.C_bits(15)) dac (
	.clk_i(clk42),
	.res_n_i(1'b1),
	.dac_i(audio_mix),
	.dac_o(audio_out)
);

assign led_n = ~{io_dbg[1:0], turbo, mem_ready, pll_locked, ~reset};

endmodule
