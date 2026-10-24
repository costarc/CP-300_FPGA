//============================================================================
//
//  CP-300 FPGA - top level for the Terasic DE0 (Cyclone III EP3C16)
//
//  The HT1080Z (TRS-80 Model I) core from mist-devel/ht1080z, being turned
//  into a CP-300 (Model III compatible), running
//  stand-alone on the DE0 without the MiST ARM controller:
//    - 50 MHz -> 42 MHz PLL
//    - CP-300 ROM: four 2732 EPROM images + 2716 character generator in M9K
//    - PS/2 keyboard straight from the DE0 PS/2 port
//    - MiST scandoubler for 31 kHz VGA on the 4-bit DE0 DAC (OSD unused)
//
//  Switches:  SW0 up = 50 Hz (down = 60 Hz, as the PAL-M CP-300)
//             SW1 = CPU turbo, SW3:2 = scanlines, SW4 = tape sounds
//  Buttons:   BUTTON0 = reset
//  LEDs:      LEDG0 = running (out of reset), LEDG9 = PLL locked
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.
//
//============================================================================

module cp300_de0 (
	input         CLOCK_50,

	input   [2:0] BUTTON,
	input   [9:0] SW,
	output  [9:0] LEDG,

	output  [3:0] VGA_R,
	output  [3:0] VGA_G,
	output  [3:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,

	input         PS2_KBCLK,
	input         PS2_KBDAT,

	output        SD_CLK,
	output        SD_CMD,     // MOSI in SPI mode
	input         SD_DAT,     // DAT0 = MISO
	output        SD_DAT3,    // CS
	input         SD_WP_N,

	output [12:0] DRAM_ADDR,
	inout  [15:0] DRAM_DQ,
	output        DRAM_LDQM,
	output        DRAM_UDQM,
	output        DRAM_WE_N,
	output        DRAM_CAS_N,
	output        DRAM_RAS_N,
	output        DRAM_CS_N,
	output        DRAM_BA_0,
	output        DRAM_BA_1,
	output        DRAM_CLK,
	output        DRAM_CKE,

	input         UART_RXD,
	output        UART_TXD,

	output        AUDIO_OUT,  // GPIO0_D[0]: sigma-delta, needs an RC filter
	input         CASS_IN     // GPIO0_D[1]: reserved, the HT1080Z ROM loads tapes via port 04
);

wire clk42, clk42_sdram, pll_locked;
pll_de0 pll(
	.inclk0(CLOCK_50),
	.c0(clk42),
	.c1(clk42_sdram),
	.locked(pll_locked)
);

assign DRAM_CLK = clk42_sdram;

wire        ntsc     = ~SW[0];
wire        turbo    = SW[1];
wire  [1:0] scanlines = SW[3:2];
wire        tapesnd  = SW[4];

// Power-on reset: hold the CPU about 1.5 ms after the PLL locks so the
// SDRAM controller finishes its init sequence before the first RAM access.
reg [15:0] por_cnt = 0;
wire       por_done = &por_cnt;
always @(posedge clk42) begin
	if (!pll_locked)    por_cnt <= 0;
	else if (!por_done) por_cnt <= por_cnt + 1'd1;
end

reg reset = 1;
reg io_reset = 1;
reg [1:0] button_s;
wire core_rst, menu_open;
wire [7:0] io_dbg;
always @(posedge clk42) begin
	button_s <= {button_s[0], BUTTON[0]};
	io_reset <= ~button_s[1] | ~por_done;
	reset <= ~button_s[1] | ~por_done | core_rst;
end

wire [17:0] rgb;
wire  [8:0] audio;
wire        hs, vs, hb, vb;
wire        ledb;
reg   [1:0] cass_in;
wire  [1:0] cass_out;
wire        uart_tx, uart_rts;

// floppy controller <-> IO controller
wire  [7:0] fdc_track, fdc_trkreg, fdc_sector;
wire        fdc_rd, fdc_wr, fdc_ra, fdc_dam, fdc_ack, fdc_buff_wr, fdc_side;
wire        fdc_res_found, fdc_res_crc, fdc_res_dam;
wire  [8:0] fdc_buff_addr;
wire  [7:0] fdc_buff_dout, fdc_buff_din;
wire  [1:0] fdc_drive;
wire  [3:0] drv_ready, drv_wp;

always @(posedge clk42) cass_in <= {cass_in[0], CASS_IN};

wire [15:0] exp_addr;
wire  [7:0] exp_din, exp_dout;
wire        exp_in, exp_out, exp_oe;
wire [12:0] sdram_a;
wire  [1:0] sdram_ba;

ht1080z ht1080z (
	.clk42m (clk42),
	.pllLocked(pll_locked),
	.reset(reset),
	.led(ledb),
	.ntsc(ntsc),
	.turbo(turbo),
	.cass_in(cass_in[1]),
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

	.ps2clk(PS2_KBCLK | menu_open),   // the menu owns the keyboard while it is open
	.ps2dat(PS2_KBDAT | menu_open),

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

	.SDRAM_nCS(DRAM_CS_N),
	.SDRAM_DQ(DRAM_DQ),
	.SDRAM_A(sdram_a),
	.SDRAM_DQMH(DRAM_UDQM),
	.SDRAM_DQML(DRAM_LDQM),
	.SDRAM_nWE(DRAM_WE_N),
	.SDRAM_nCAS(DRAM_CAS_N),
	.SDRAM_nRAS(DRAM_RAS_N),
	.SDRAM_BA(sdram_ba),
	.SDRAM_CKE(DRAM_CKE)
);

assign DRAM_ADDR = sdram_a;
assign DRAM_BA_0 = sdram_ba[0];
assign DRAM_BA_1 = sdram_ba[1];

// 9600 8N1, ports E8-EA
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
	.uart_rx(UART_RXD),
	.uart_tx(uart_tx),
	.uart_cts(1'b0),
	.uart_rts(uart_rts)
);

assign UART_TXD = uart_tx;

// IO controller: SD card, on-screen menu, menu keyboard
wire spi_sck, spi_mosi, osd_ss3, sd_cs_n;
io_ctrl io_ctrl (
	.clk(clk42),
	.reset(io_reset),
	.sd_cs_n(sd_cs_n),
	.spi_sck(spi_sck),
	.spi_mosi(spi_mosi),
	.sd_miso(SD_DAT),
	.sd_wp_n(SD_WP_N),
	.osd_ss3(osd_ss3),
	.ps2clk(PS2_KBCLK),
	.ps2dat(PS2_KBDAT),
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

assign SD_CLK  = spi_sck;
assign SD_CMD  = spi_mosi;
assign SD_DAT3 = sd_cs_n;

mist_video #(.COLOR_DEPTH(6), .SD_HCNT_WIDTH(10), .OUT_COLOR_DEPTH(4), .USE_BLANKS(1'b1)) mist_video(
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
	.VGA_R          ( VGA_R            ),
	.VGA_G          ( VGA_G            ),
	.VGA_B          ( VGA_B            ),
	.VGA_VS         ( VGA_VS           ),
	.VGA_HS         ( VGA_HS           ),
	.ce_divider     ( 3'd3             ),
	.rotate         ( 2'b00            ),
	.blend          ( 1'b0             ),
	.scandoubler_disable( 1'b0         ),
	.scanlines      ( scanlines        ),
	.ypbpr          ( 1'b0             ),
	.no_csync       ( 1'b1             )
);

wire [14:0] audio_mix = {1'b0, audio, 5'd0} + (tapesnd ? {cass_in[1], cass_out[0], 10'd0} : 14'd0);
dac #(.C_bits(15)) dac(
	.clk_i(clk42),
	.res_n_i(1'b1),
	.dac_i(audio_mix),
	.dac_o(AUDIO_OUT)
);


assign LEDG = {pll_locked, io_dbg, ~reset};   // LEDG8:1 = IO controller status, then the last PS/2 byte

endmodule
