//============================================================================
//
//  CP-300 FPGA, MiSTer: Prologica CP-300 (TRS-80 Model III compatible).
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  The system ROM and the character generator are NOT part of the core: they are loaded from the
//  SD card (boot0.rom / boot1.rom in games/CP-300, or from the OSD menu), see README.md.
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_MIX = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[6:5];

assign VIDEO_ARX = (!ar) ? 13'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 13'd3 : 13'd0;

`include "build_id.v"
localparam CONF_STR = {
	"CP-300;;",
	"-;",
	"F1,BIN,Load System ROM;",
	"F2,BIN,Load Char Gen;",
	"-;",
	"S0,DMKDSK,Drive 0;",
	"S1,DMKDSK,Drive 1;",
	"S2,DMKDSK,Drive 2;",
	"S3,DMKDSK,Drive 3;",
	"O[1],Write protect disks,Off,On;",
	"-;",
	"O[6:5],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[4:3],Display,White,Green,Amber;",
	"O[2],Turbo,Off,On;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"v,0;",
	"V,v",`BUILD_DATE
};

wire        forced_scandoubler;
wire  [1:0] buttons;
wire [127:0] status;

wire        ps2_kbd_clk, ps2_kbd_data;

wire  [3:0] img_mounted;
wire [63:0] img_size;
wire [31:0] sd_lba     [4];
wire  [5:0] sd_blk_cnt [4];
wire  [3:0] sd_rd, sd_wr, sd_ack;
wire [13:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din [4];
wire        sd_buff_wr;

wire        ioctl_download;
wire        ioctl_wr;
wire [15:0] ioctl_index;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;

hps_io #(.CONF_STR(CONF_STR), .VDNUM(4), .BLKSZ(2), .PS2DIV(1750)) hps_io
(
	.clk_sys(clk42),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask(16'd0),

	.ps2_kbd_clk_out(ps2_kbd_clk),
	.ps2_kbd_data_out(ps2_kbd_data),

	.img_mounted(img_mounted),
	.img_readonly(),
	.img_size(img_size),

	.sd_lba(sd_lba),
	.sd_blk_cnt(sd_blk_cnt),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(1'b0)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk42, pll_locked;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk42),
	.locked(pll_locked)
);

///////////////////////   ROMs from the SD card   ////////////////

// boot0.rom (index 0) or "Load System ROM" (index 1): system ROM, 16 KB (a 14 KB Model III ROM works too)
// boot1.rom (index 40h) or "Load Char Gen" (index 2): character generator, 2 KB
// They go straight into the RAMs that stand for the ROMs (cp300_rom, videoctrl), four bytes at a time.
wire        is_sys = ioctl_download && (ioctl_index[7:0] == 8'h00 || ioctl_index[7:0] == 8'h01);
wire        is_chr = ioctl_download && (ioctl_index[7:0] == 8'h40 || ioctl_index[7:0] == 8'h02);
wire [14:0] rom_a  = (is_chr ? 15'h4000 : 15'h0000) + ioctl_addr[14:0];
wire        rom_ok = is_chr ? (ioctl_addr[26:11] == 16'd0) : (ioctl_addr[26:14] == 13'd0);

reg  [31:0] rl_wbuf;
reg  [31:0] rl_wdata;
reg  [12:0] rl_waddr;
reg         rl_we = 1'b0;
reg         rl_pend = 1'b0;
reg         dl_q = 1'b0;

always @(posedge clk42) begin
	rl_we <= 1'b0;
	dl_q  <= ioctl_download;
	if (ioctl_wr && (is_sys || is_chr) && rom_ok) begin
		case (rom_a[1:0])
		2'd0: begin rl_wbuf[31:24] <= ioctl_dout; rl_pend <= 1'b1; end
		2'd1: rl_wbuf[23:16] <= ioctl_dout;
		2'd2: rl_wbuf[15:8]  <= ioctl_dout;
		2'd3: begin
			rl_wdata <= {rl_wbuf[31:8], ioctl_dout};
			rl_we    <= 1'b1;
			rl_pend  <= 1'b0;
		end
		endcase
		rl_waddr <= rom_a[14:2];
	end else if (dl_q && !ioctl_download && rl_pend) begin
		// the file ended inside a word
		rl_wdata <= rl_wbuf;
		rl_we    <= 1'b1;
		rl_pend  <= 1'b0;
	end
end

///////////////////////   RESET   ////////////////////////////////

wire io_hold;                               // the IO controller holds the CP-300 in reset until the disks are mounted
reg  [15:0] rst_cnt = 16'd0;
always @(posedge clk42) begin
	if (RESET | status[0] | buttons[1] | (dl_q & ~ioctl_download)) rst_cnt <= 16'd42000;
	else if (rst_cnt != 16'd0) rst_cnt <= rst_cnt - 16'd1;
end

wire run42 = pll_locked;
wire core_reset = ~run42 | io_hold | (rst_cnt != 16'd0) | ioctl_download;

///////////////////////   THE CP-300   ///////////////////////////

// Z80 RAM (4000-FFFF) is a 64 KB block RAM; the access takes one clock, far less than a Z80 T state
// (21 clocks), so the core never needs to wait.
wire [15:0] ext_addr;
wire        ext_rd, ext_wr;
wire  [7:0] ext_din;
reg   [7:0] ext_dout;
reg   [7:0] ram64 [0:65535];

always @(posedge clk42) begin
	if (ext_wr) ram64[ext_addr] <= ext_din;
	ext_dout <= ram64[ext_addr];
end

wire        vid_screen, vid_ink, vid_pxen;
wire        hs_n, vs_n;
wire  [8:0] audio;

wire  [7:0] fdc_track, fdc_trkreg, fdc_sector;
wire        fdc_rd, fdc_wr, fdc_ra, fdc_dam, fdc_ack, fdc_buff_wr, fdc_side;
wire        fdc_res_found, fdc_res_crc, fdc_res_dam;
wire  [8:0] fdc_buff_addr;
wire  [7:0] fdc_buff_dout, fdc_buff_din;
wire  [1:0] fdc_drive;
wire  [3:0] drv_ready, drv_wp;

// SDRAM and exp port of the HT1080Z core: unused here
wire        sd_nCS, sd_nWE, sd_nCAS, sd_nRAS, sd_dqmh, sd_dqml, sd_cke;
wire [12:0] sd_a;
wire  [1:0] sd_ba;
wire [15:0] sd_dq;
wire [15:0] exp_addr;
wire  [7:0] exp_dout;
wire        exp_in, exp_out;

ht1080z_ext cp300 (
	.clk42m (clk42),
	.pllLocked(run42),
	.reset(core_reset),
	.led(),
	.ntsc(1'b1),                // 60 Hz, as the PAL-M CP-300
	.turbo(status[2]),
	.ext_keys(64'd0),
	.cass_in(1'b0),
	.cass_out(),

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

	.ps2clk(ps2_kbd_clk),
	.ps2dat(ps2_kbd_data),

	.ht_rgb(),
	.hs(hs_n),
	.vs(vs_n),
	.hb(),
	.vb(),
	.vid_screen(vid_screen),
	.vid_ink(vid_ink),
	.vid_pxen(vid_pxen),
	.vid_ink_rgb(),
	.vid_paper_rgb(),
	.vid_border_rgb(),

	.audiomix(audio),

	.dn_go(1'b0),
	.dn_wr(1'b0),
	.dn_addr(25'd0),
	.dn_data(8'd0),
	.dn_idx(5'd0),

	.exp_addr(exp_addr),
	.exp_din(8'h00),
	.exp_dout(exp_dout),
	.exp_in(exp_in),
	.exp_out(exp_out),
	.exp_oe(1'b0),

	.ext_ram_addr(ext_addr),
	.ext_ram_rd(ext_rd),
	.ext_ram_wr(ext_wr),
	.ext_ram_din(ext_din),
	.ext_ram_dout(ext_dout),
	.ext_ram_wait(1'b0),

	.SDRAM_nCS(sd_nCS),
	.SDRAM_DQ(sd_dq),
	.SDRAM_A(sd_a),
	.SDRAM_DQMH(sd_dqmh),
	.SDRAM_DQML(sd_dqml),
	.SDRAM_nWE(sd_nWE),
	.SDRAM_nCAS(sd_nCAS),
	.SDRAM_nRAS(sd_nRAS),
	.SDRAM_BA(sd_ba),
	.SDRAM_CKE(sd_cke),

	.rl_clk(clk42),
	.rl_we(rl_we),
	.rl_waddr(rl_waddr),
	.rl_wdata(rl_wdata)
);

///////////////////////   IO CONTROLLER AND DISKS   //////////////

// The helper Z80 serves the floppy controller's sector requests out of the DMK images of the four
// virtual drives, see mister_slots.sv and firmware/pocket.
wire        slot_req_tog, slot_req_wr, slot_busy, slot_err, trk_we, scan_valid;
wire  [1:0] slot_num;
wire [31:0] slot_offset;
wire [15:0] slot_len;
wire [13:0] slot_boff, trk_addr;
wire  [7:0] trk_din, trk_dout;
wire [31:0] slot_size;
wire  [3:0] slot_present, slot_changed, slot_chg_clr;

io_ctrl_pocket io_ctrl (
	.clk(clk42),
	.reset(~run42),
	.core_rst(io_hold),
	.dbg(),

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
	.drv_wp(drv_wp),

	.slot_req_tog(slot_req_tog),
	.slot_req_wr(slot_req_wr),
	.slot_num(slot_num),
	.slot_offset(slot_offset),
	.slot_busy(slot_busy),
	.slot_err(slot_err),
	.slot_len(slot_len),
	.slot_boff(slot_boff),
	.slot_size(slot_size),
	.trk_addr(trk_addr),
	.trk_we(trk_we),
	.trk_din(trk_din),
	.trk_dout(trk_dout),
	.slot_present(slot_present),
	.slot_changed(slot_changed),
	.slot_chg_clr(slot_chg_clr),
	.scan_valid(scan_valid),
	.opt_wp(status[1])
);

mister_slots slots (
	.clk(clk42),
	.reset(~run42),

	.img_mounted(img_mounted),
	.img_size(img_size),
	.sd_lba(sd_lba),
	.sd_blk_cnt(sd_blk_cnt),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_wr(sd_buff_wr),
	.sd_buff_din(sd_buff_din),

	.req_tog(slot_req_tog),
	.req_wr(slot_req_wr),
	.req_slot(slot_num),
	.req_offset(slot_offset),
	.req_len(slot_len),
	.req_boff(slot_boff),
	.busy(slot_busy),
	.err(slot_err),
	.trk_addr(trk_addr),
	.trk_we(trk_we),
	.trk_din(trk_din),
	.trk_dout(trk_dout),
	.size_sel(slot_size),
	.present(slot_present),
	.changed(slot_changed),
	.chg_clr(slot_chg_clr),
	.scan_valid(scan_valid)
);

assign LED_DISK = {1'b1, slot_busy};

///////////////////////   VIDEO   ////////////////////////////////

// The core's picture is 512 x 192 pixels at 10.5 MHz; vid_pxen is that pixel clock as an enable of clk42.
reg [23:0] ink_rgb;
always @(*) begin
	case (status[4:3])
	2'd1:    ink_rgb = 24'h40FF60;     // green phosphor
	2'd2:    ink_rgb = 24'hFFB000;     // amber
	default: ink_rgb = 24'hE8E8E8;     // white
	endcase
end

wire [23:0] rgb = (vid_screen && vid_ink) ? ink_rgb : 24'd0;

assign CLK_VIDEO = clk42;
assign CE_PIXEL  = vid_pxen;
assign VGA_R  = rgb[23:16];
assign VGA_G  = rgb[15:8];
assign VGA_B  = rgb[7:0];
assign VGA_DE = vid_screen;
assign VGA_HS = ~hs_n;
assign VGA_VS = ~vs_n;

///////////////////////   AUDIO   ////////////////////////////////

// The core's audio is the cassette port speaker bit (port FF, three levels); 10h is the idle level.
wire signed [9:0]  a_c   = {1'b0, audio} - 10'sd16;
wire signed [15:0] a_out = a_c <<< 8;

assign AUDIO_S = 1'b1;
assign AUDIO_L = a_out;
assign AUDIO_R = a_out;

reg  [26:0] act_cnt;
always @(posedge clk42) act_cnt <= act_cnt + 1'd1;
assign LED_USER = act_cnt[26] ? act_cnt[25:18] > act_cnt[7:0] : act_cnt[25:18] <= act_cnt[7:0];

endmodule
