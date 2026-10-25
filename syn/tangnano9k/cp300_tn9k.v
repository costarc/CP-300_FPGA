//============================================================================
//
//  CP-300 FPGA - top level for the Sipeed Tang Nano 9K (Gowin GW1NR-9C)
//
//  Same core as the DE0 build (rtl/ht1080z + CP-300 ROM + WD1793 + SD/menu IO
//  controller), with these board differences:
//    - 27 MHz -> 42 MHz PLL, 42 MHz pixel clock and 210 MHz TMDS clock
//    - Z80 RAM (48 KB) in the on-chip 8 MB HyperRAM, not SDRAM
//    - HDMI (DVI) output on the board's HDMI connector instead of 4-bit VGA
//    - the TF card slot on the board (SPI mode)
//    - PS/2 keyboard, the original CP-300 keyboard matrix, audio and cassette
//      input on the 2x24 headers, 3.3 V (see README-tangnano9k.md)
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

module cp300_tn9k (
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

	// embedded HyperRAM: the Gowin tools infer these pins from the names
	output  [1:0] O_psram_ck,
	output  [1:0] O_psram_ck_n,
	inout   [1:0] IO_psram_rwds,
	inout  [15:0] IO_psram_dq,
	output  [1:0] O_psram_reset_n,
	output  [1:0] O_psram_cs_n
);

// ---------------------------------------------------------------- clocks
wire clk42, clk42_p, clk_tmds, clk_pix, pll_locked;
pll_tn9k pll (
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
	s1_s     <= {s1_s[0], btn_s1_n};
	s2_s     <= {s2_s[0], btn_s2_n};
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
wire        ps_read, ps_write, ps_busy;
wire [21:0] ps_addr;
wire [15:0] ps_din, ps_dout;

PsramController #(.FREQ(42_000_000), .LATENCY(3)) psram (
	.clk(clk42), .clk_p(clk42_p), .resetn(pll_locked),
	.read(ps_read), .write(ps_write), .byte_write(1'b1),
	.addr(ps_addr), .din(ps_din), .dout(ps_dout), .busy(ps_busy),
	.O_psram_ck(O_psram_ck), .IO_psram_rwds(IO_psram_rwds), .IO_psram_dq(IO_psram_dq),
	.O_psram_cs_n(O_psram_cs_n)
);
assign O_psram_reset_n = {1'b0, pll_locked};   // the second die stays in reset

wire [15:0] ext_addr;
wire        ext_rd, ext_wr, ext_stall;
wire  [7:0] ext_din, ext_dout;

ram_bridge bridge (
	.clk(clk42), .resetn(pll_locked),
	.rd(ext_rd), .wr(ext_wr), .a(ext_addr), .din(ext_din),
	.dout(ext_dout), .stall(ext_stall), .ready(mem_ready),
	.ps_read(ps_read), .ps_write(ps_write), .ps_addr(ps_addr), .ps_din(ps_din),
	.ps_dout(ps_dout), .ps_busy(ps_busy)
);

// ---------------------------------------------------------------- core
wire [17:0] rgb;
wire  [8:0] audio;
wire        hs, vs, hb, vb;
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

	.ht_rgb(rgb),
	.hs(hs),
	.vs(vs),
	.hb(hb),
	.vb(vb),

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
// scandoubler (31 kHz, 21 MHz pixels), then DVI with a 42 MHz pixel clock
// (every pixel twice). DE comes from the blanking signals.
wire [5:0] vga_r, vga_g, vga_b;
wire       vga_hs, vga_vs, vga_de;

mist_video #(.COLOR_DEPTH(6), .SD_HCNT_WIDTH(10), .OUT_COLOR_DEPTH(6), .USE_BLANKS(1'b1),
             .BIG_OSD(1'b1), .VIDEO_CLEANER(1'b1)) mist_video (
	.clk_sys        ( clk42            ),
	.SPI_SCK        ( spi_sck          ),
	.SPI_SS3        ( osd_ss3          ),
	.SPI_DI         ( spi_mosi         ),
	.R              ( rgb[ 5: 0]       ),
	.G              ( rgb[11: 6]       ),
	.B              ( rgb[17:12]       ),
	.HBlank         ( hb               ),
	.VBlank         ( vb               ),
	.HSync          ( hs               ),
	.VSync          ( vs               ),
	.VGA_R          ( vga_r            ),
	.VGA_G          ( vga_g            ),
	.VGA_B          ( vga_b            ),
	.VGA_VS         ( vga_vs           ),
	.VGA_HS         ( vga_hs           ),
	.VGA_DE         ( vga_de           ),
	.ce_divider     ( 3'd3             ),
	.rotate         ( 2'b00            ),
	.blend          ( 1'b0             ),
	.scandoubler_disable( 1'b0         ),
	.scanlines      ( 2'b00            ),
	.ypbpr          ( 1'b0             ),
	.no_csync       ( 1'b1             )
);

wire [20:0] vid_pix;
video_cdc #(.W(21)) vcdc (
	.clk_in (clk42),
	.din    ({vga_de, vga_vs, vga_hs, vga_r, vga_g, vga_b}),
	.clk_out(clk_pix),
	.rst_out(~pll_locked),
	.dout   (vid_pix)
);

dvi_tx dvi (
	.clk_pix(clk_pix),
	.clk_5x(clk_tmds),
	.rst(~pll_locked),
	.r({vid_pix[17:12], vid_pix[17:16]}),
	.g({vid_pix[11:6],  vid_pix[11:10]}),
	.b({vid_pix[5:0],   vid_pix[5:4]}),
	.hs(vid_pix[18]),
	.vs(vid_pix[19]),
	.de(vid_pix[20]),
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
