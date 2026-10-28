//
// CP-300 FPGA, BeagleV-Fire: the CP-300 with a host register bus (AXI4-Lite) instead of SD card, PS/2 and
// video connector. The host is the Linux side of the PolarFire SoC (cp300d daemon, see ../host).
//
//   host (AXI4-Lite, aclk) -> axil_regbus -> bvf_regs (clk, 42 MHz) -> keys, run/reset/turbo,
//                                            ROM load, disk mailbox, frame RAM, audio FIFO
//
// The core, the IO controller (helper Z80 + DMK firmware) and the ROM loader are the ones of the
// Analogue Pocket port, unchanged:  ../analogue/src/fpga/core/{ht1080z_ext,io_ctrl_pocket,io_fw_pkg,cp300_roms_stub}.vhd
// and rtl/ (ht1080z, wd1793, T80 ...).  The host holds the core in reset (CTRL.run = 0) while it loads the
// two ROMs and the slot table, then sets run.
//
module bvf_core (
	input         clk,                 // 42 MHz core clock, from the fabric clock conditioning circuit
	input         pll_locked,

	input         aclk,
	input         aresetn,
	input  [19:0] s_awaddr, input s_awvalid, output s_awready,
	input  [31:0] s_wdata,  input [3:0] s_wstrb, input s_wvalid, output s_wready,
	output  [1:0] s_bresp,  output s_bvalid, input s_bready,
	input  [19:0] s_araddr, input s_arvalid, output s_arready,
	output [31:0] s_rdata,  output [1:0] s_rresp, output s_rvalid, input s_rready,

	output        irq                  // disk request pending or frame ready: level, for the UIO driver
);

// ---------------------------------------------------------------- host bus
wire [19:0] b_addr;
wire        b_wr, b_rd;
wire [31:0] b_wdata, b_rdata;

axil_regbus bus (
	.aclk(aclk), .aresetn(aresetn),
	.awaddr(s_awaddr), .awvalid(s_awvalid), .awready(s_awready),
	.wdata(s_wdata), .wstrb(s_wstrb), .wvalid(s_wvalid), .wready(s_wready),
	.bresp(s_bresp), .bvalid(s_bvalid), .bready(s_bready),
	.araddr(s_araddr), .arvalid(s_arvalid), .arready(s_arready),
	.rdata(s_rdata), .rresp(s_rresp), .rvalid(s_rvalid), .rready(s_rready),
	.clk(clk), .b_addr(b_addr), .b_wr(b_wr), .b_wdata(b_wdata), .b_rd(b_rd), .b_rdata(b_rdata)
);

// ---------------------------------------------------------------- the CP-300
wire        run, rst_pulse, turbo, wp_all;
wire [63:0] keys;
wire        io_hold;
wire        core_reset = ~run | ~pll_locked | io_hold | rst_pulse;

wire [15:0] ext_addr;
wire        ext_rd, ext_wr;
wire  [7:0] ext_din;
reg   [7:0] ext_dout;
// Z80 RAM: the full 64 KB, as in the Pocket port. Only 4000-FFFF is needed (48 KB); trimming it saves
// 128 kbit of block RAM if the MPFS025T runs short (check what ht1080z maps below 4000 first).
reg   [7:0] ram64 [0:65535];
always @(posedge clk) begin
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

wire        rl_we;
wire [12:0] rl_waddr;
wire [31:0] rl_wdata = b_wdata;

wire        sd_nCS, sd_nWE, sd_nCAS, sd_nRAS, sd_dqmh, sd_dqml, sd_cke;
wire [12:0] sd_a;
wire  [1:0] sd_ba;
wire [15:0] sd_dq;
wire [15:0] exp_addr;
wire  [7:0] exp_dout;
wire        exp_in, exp_out;

ht1080z_ext cp300 (
	.clk42m(clk), .pllLocked(run & pll_locked), .reset(core_reset), .led(),
	.ntsc(1'b1), .turbo(turbo), .ext_keys(keys), .cass_in(1'b0), .cass_out(),
	.fdc_svc_rd(fdc_rd), .fdc_svc_wr(fdc_wr), .fdc_svc_ra(fdc_ra), .fdc_svc_track(fdc_track),
	.fdc_svc_trkreg(fdc_trkreg), .fdc_svc_sector(fdc_sector), .fdc_svc_dam(fdc_dam),
	.fdc_svc_ack(fdc_ack), .fdc_res_found(fdc_res_found), .fdc_res_crc(fdc_res_crc),
	.fdc_res_dam(fdc_res_dam), .fdc_buff_addr(fdc_buff_addr), .fdc_buff_dout(fdc_buff_dout),
	.fdc_buff_din(fdc_buff_din), .fdc_buff_wr(fdc_buff_wr), .fdc_drive(fdc_drive),
	.fdc_side(fdc_side), .drv_ready(drv_ready), .drv_wp(drv_wp),
	.ps2clk(1'b1), .ps2dat(1'b1),
	.ht_rgb(), .hs(hs_n), .vs(vs_n), .hb(), .vb(),
	.vid_screen(vid_screen), .vid_ink(vid_ink), .vid_pxen(vid_pxen),
	.vid_ink_rgb(), .vid_paper_rgb(), .vid_border_rgb(),
	.audiomix(audio),
	.dn_go(1'b0), .dn_wr(1'b0), .dn_addr(25'd0), .dn_data(8'd0), .dn_idx(5'd0),
	.exp_addr(exp_addr), .exp_din(8'h00), .exp_dout(exp_dout), .exp_in(exp_in), .exp_out(exp_out), .exp_oe(1'b0),
	.ext_ram_addr(ext_addr), .ext_ram_rd(ext_rd), .ext_ram_wr(ext_wr), .ext_ram_din(ext_din),
	.ext_ram_dout(ext_dout), .ext_ram_wait(1'b0),
	.SDRAM_nCS(sd_nCS), .SDRAM_DQ(sd_dq), .SDRAM_A(sd_a), .SDRAM_DQMH(sd_dqmh), .SDRAM_DQML(sd_dqml),
	.SDRAM_nWE(sd_nWE), .SDRAM_nCAS(sd_nCAS), .SDRAM_nRAS(sd_nRAS), .SDRAM_BA(sd_ba), .SDRAM_CKE(sd_cke),
	.rl_clk(clk), .rl_we(rl_we), .rl_waddr(rl_waddr), .rl_wdata(rl_wdata)
);

// ---------------------------------------------------------------- IO controller and disk mailbox
wire        slot_req_tog, slot_req_wr, slot_busy, slot_err, trk_we_io, scan_valid;
wire  [1:0] slot_num;
wire [31:0] slot_offset, slot_size;
wire [15:0] slot_len;
wire [13:0] slot_boff, trk_addr_io;
wire  [7:0] trk_din_io, trk_dout_io, io_dbg;
wire  [3:0] slot_present, slot_changed, slot_chg_clr;

io_ctrl_pocket io_ctrl (
	.clk(clk), .reset(~run | ~pll_locked), .core_rst(io_hold), .dbg(io_dbg),
	.fdc_rd(fdc_rd), .fdc_wr(fdc_wr), .fdc_ra(fdc_ra), .fdc_track(fdc_track), .fdc_trkreg(fdc_trkreg),
	.fdc_sector(fdc_sector), .fdc_dam(fdc_dam), .fdc_res_found(fdc_res_found), .fdc_res_crc(fdc_res_crc),
	.fdc_res_dam(fdc_res_dam), .fdc_drive(fdc_drive), .fdc_side(fdc_side), .fdc_ack(fdc_ack),
	.fdc_buff_addr(fdc_buff_addr), .fdc_buff_dout(fdc_buff_dout), .fdc_buff_wr(fdc_buff_wr),
	.fdc_buff_din(fdc_buff_din), .drv_ready(drv_ready), .drv_wp(drv_wp),
	.slot_req_tog(slot_req_tog), .slot_req_wr(slot_req_wr), .slot_num(slot_num), .slot_offset(slot_offset),
	.slot_busy(slot_busy), .slot_err(slot_err), .slot_len(slot_len), .slot_boff(slot_boff),
	.slot_size(slot_size), .trk_addr(trk_addr_io), .trk_we(trk_we_io), .trk_din(trk_din_io),
	.trk_dout(trk_dout_io), .slot_present(slot_present), .slot_changed(slot_changed),
	.slot_chg_clr(slot_chg_clr), .scan_valid(scan_valid), .opt_wp(wp_all)
);

wire        done_pulse, done_err, sz_we, pres_we, scan_we, scan_val;
wire  [1:0] sz_idx;
wire [31:0] sz_val, h_dout_trk;
wire  [3:0] pres_val, chg_set;
wire [11:0] trk_addr_h;
wire        trk_we_h;

bvf_dataslot slots (
	.clk(clk), .reset(~run | ~pll_locked),
	.h_addr(trk_addr_h), .h_we(trk_we_h), .h_din(b_wdata), .h_dout(h_dout_trk),
	.done_pulse(done_pulse), .done_err(done_err),
	.sz_we(sz_we), .sz_idx(sz_idx), .sz_val(sz_val),
	.pres_we(pres_we), .pres_val(pres_val), .chg_set(chg_set), .scan_we(scan_we), .scan_val(scan_val),
	.req_tog(slot_req_tog), .req_slot(slot_num), .busy(slot_busy), .err(slot_err),
	.trk_addr(trk_addr_io), .trk_we(trk_we_io), .trk_din(trk_din_io), .trk_dout(trk_dout_io),
	.size_sel(slot_size), .present(slot_present), .changed(slot_changed), .chg_clr(slot_chg_clr),
	.scan_valid(scan_valid)
);

// ---------------------------------------------------------------- frame capture and audio
wire [15:0] frame_cnt;
wire        frame_latest;
wire [12:0] fb_addr;
wire [31:0] fb_dout;

bvf_fb #(.BUFS(2)) fb (
	.clk(clk), .pxen(vid_pxen), .screen(vid_screen), .ink(vid_ink), .vs_n(vs_n),
	.h_addr(fb_addr), .h_dout(fb_dout), .frame_cnt(frame_cnt), .latest(frame_latest)
);

wire [8:0]  aud_count;
wire [31:0] aud_head;
wire        aud_lost, aud_pop, aud_clr_lost;

bvf_audio #(.CLK_MHZ(42)) aud (
	.clk(clk), .reset(~run), .audio(audio), .pop(aud_pop), .head(aud_head), .count(aud_count),
	.lost(aud_lost), .clr_lost(aud_clr_lost)
);

// ---------------------------------------------------------------- registers
bvf_regs regs (
	.clk(clk), .reset(~pll_locked), .addr(b_addr), .wr(b_wr), .wdata(b_wdata), .rd(b_rd), .rdata(b_rdata),
	.run(run), .rst_pulse(rst_pulse), .turbo(turbo), .wp_all(wp_all), .keys(keys),
	.io_hold(io_hold), .scan_valid(scan_valid), .req_pending(slot_busy), .req_is_wr(slot_req_wr),
	.req_err(slot_err), .dbg(io_dbg),
	.req_slot({30'd0, slot_num}), .req_offset(slot_offset), .req_len({16'd0, slot_len}), .req_boff({18'd0, slot_boff}),
	.frame_cnt(frame_cnt), .frame_latest(frame_latest), .fb_addr(fb_addr), .fb_dout(fb_dout),
	.aud_count(aud_count), .aud_head(aud_head), .aud_lost(aud_lost), .aud_pop(aud_pop), .aud_clr_lost(aud_clr_lost),
	.trk_addr(trk_addr_h), .trk_we(trk_we_h), .trk_dout(h_dout_trk),
	.done_pulse(done_pulse), .done_err(done_err), .sz_we(sz_we), .sz_idx(sz_idx), .sz_val(sz_val),
	.pres_we(pres_we), .pres_val(pres_val), .chg_set(chg_set), .scan_we(scan_we), .scan_val(scan_val),
	.rl_we(rl_we), .rl_waddr(rl_waddr)
);

// level interrupt for the UIO driver: a disk request waits, or (see FRAME) the host polls it
assign irq = slot_busy;

endmodule
