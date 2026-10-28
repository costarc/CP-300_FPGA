// CP-300 FPGA, MiSTer: disk image access for the IO controller.
//
// The same job as syn/analogue/.../apf_dataslot.vhd, on the MiSTer's hps_io block interface: the four
// DMK images are the hps_io virtual drives 0-3 (menu entries S0-S3, mounted by the HPS from the SD
// card). The IO controller (io_ctrl_pocket, firmware/pocket) asks for up to a whole DMK track
// (16 KB, 32 blocks of 512 bytes) in one request; one hps_io command moves it:
//
//   read   the HPS writes the blocks to the track RAM (sd_buff_wr), starting at the request's boff
//   write  the HPS reads the blocks from the track RAM (sd_buff_din)
//
// The track RAM (16 KB) is also in the IO controller's memory map, at 8000h. Everything is on one clock.

module mister_slots (
	input             clk,
	input             reset,                   // high = reset

	// hps_io
	input       [3:0] img_mounted,
	input      [63:0] img_size,
	output reg [31:0] sd_lba    [4],
	output reg  [5:0] sd_blk_cnt[4],
	output reg  [3:0] sd_rd,
	output reg  [3:0] sd_wr,
	input       [3:0] sd_ack,
	input      [13:0] sd_buff_addr,
	input       [7:0] sd_buff_dout,
	input             sd_buff_wr,
	output      [7:0] sd_buff_din   [4],

	// IO controller, see io_ctrl_pocket
	input             req_tog,
	input             req_wr,
	input       [1:0] req_slot,
	input      [31:0] req_offset,
	input      [15:0] req_len,                 // bytes (at most 16384)
	input      [13:0] req_boff,                // where in the track RAM
	output            busy,
	output            err,
	input      [13:0] trk_addr,
	input             trk_we,
	input       [7:0] trk_din,
	output      [7:0] trk_dout,
	output     [31:0] size_sel,                // size of the file in the slot req_slot
	output      [3:0] present,
	output      [3:0] changed,
	input       [3:0] chg_clr,
	output            scan_valid
);

// ---------------------------------------------------------------- mounted images
reg  [31:0] size [4];
reg   [3:0] cg = 4'd0;                         // toggles at every mount / unmount
reg   [3:0] seen = 4'd0;
reg   [3:0] pres = 4'd0;
integer i;

always @(posedge clk) begin
	for (i = 0; i < 4; i = i + 1) begin
		if (img_mounted[i]) begin
			size[i] <= img_size[31:0];
			pres[i] <= |img_size;
			cg[i]   <= ~cg[i];
		end
		if (chg_clr[i]) seen[i] <= cg[i];
	end
	if (reset) begin
		seen <= 4'd0;
	end
end

assign size_sel = size[req_slot];
assign present  = pres;
assign changed  = cg ^ seen;

// The HPS mounts the images it remembers a little after the core starts: tell the firmware that the
// table is complete only after that time, so a remembered disk is there before the CP-300 boots.
reg [26:0] scan_cnt = 27'd0;
always @(posedge clk) begin
	if (reset)              scan_cnt <= 27'd0;
	else if (!scan_cnt[26]) scan_cnt <= scan_cnt + 27'd1;
end
assign scan_valid = scan_cnt[26];             // about 1.6 s at 42 MHz

// ---------------------------------------------------------------- track RAM
// Port A is hps_io (sd_buff_addr counts from 0 in each command, boff moves it), port B the IO controller.
reg  [13:0] boff_r;
reg         rd_cmd = 1'b0;                     // a read command is running: the HPS writes the RAM
wire [13:0] a_addr = sd_buff_addr + boff_r;
wire  [7:0] a_q;

altsyncram #(
	.operation_mode("BIDIR_DUAL_PORT"),
	.width_a(8), .widthad_a(14), .numwords_a(16384),
	.width_b(8), .widthad_b(14), .numwords_b(16384),
	.outdata_reg_a("UNREGISTERED"), .outdata_reg_b("UNREGISTERED"),
	.address_reg_b("CLOCK0"), .indata_reg_b("CLOCK0"), .wrcontrol_wraddress_reg_b("CLOCK0"),
	.read_during_write_mode_port_a("NEW_DATA_NO_NBE_READ"),
	.read_during_write_mode_port_b("NEW_DATA_NO_NBE_READ"),
	.read_during_write_mode_mixed_ports("DONT_CARE"),
	.ram_block_type("M10K"),
	.power_up_uninitialized("FALSE"),
	.intended_device_family("Cyclone V"),
	.lpm_type("altsyncram")
) trk_ram (
	.clock0(clk),
	.address_a(a_addr),   .data_a(sd_buff_dout), .wren_a(sd_buff_wr & rd_cmd), .q_a(a_q),
	.address_b(trk_addr), .data_b(trk_din),      .wren_b(trk_we),              .q_b(trk_dout)
);

assign sd_buff_din[0] = a_q;
assign sd_buff_din[1] = a_q;
assign sd_buff_din[2] = a_q;
assign sd_buff_din[3] = a_q;

// ---------------------------------------------------------------- requests
localparam S_IDLE = 3'd0, S_ISSUE = 3'd1, S_ACK = 3'd2, S_DONE = 3'd3;

reg  [2:0]  st = S_IDLE;
reg         done_tog = 1'b0;
reg         err_r = 1'b0;
reg         wr_r;
reg  [1:0]  slot_r;
reg  [25:0] tmo;

assign busy = req_tog ^ done_tog;
assign err  = err_r;

wire [3:0] ack_sel = sd_ack & (4'b0001 << slot_r);

always @(posedge clk) begin
	if (reset) begin
		st <= S_IDLE; sd_rd <= 4'd0; sd_wr <= 4'd0; done_tog <= req_tog; err_r <= 1'b0; rd_cmd <= 1'b0;
	end else begin
		case (st)
		S_IDLE: if (busy) begin
			slot_r <= req_slot;
			wr_r   <= req_wr;
			boff_r <= req_boff;
			rd_cmd <= ~req_wr;
			for (i = 0; i < 4; i = i + 1) begin
				sd_lba[i]     <= {9'd0, req_offset[31:9]};
				sd_blk_cnt[i] <= 6'(((req_len + 16'd511) >> 9) - 16'd1);
			end
			tmo <= 26'd0;
			if (req_len == 16'd0) begin
				err_r <= 1'b0; done_tog <= req_tog;
			end else st <= S_ISSUE;
		end
		S_ISSUE: begin
			if (wr_r) sd_wr <= 4'b0001 << slot_r; else sd_rd <= 4'b0001 << slot_r;
			st <= S_ACK;
		end
		S_ACK: begin
			tmo <= tmo + 26'd1;
			if (|ack_sel) begin
				sd_rd <= 4'd0; sd_wr <= 4'd0;
				st <= S_DONE;
				tmo <= 26'd0;
			end else if (&tmo) begin            // the HPS never answered (about 1.6 s)
				sd_rd <= 4'd0; sd_wr <= 4'd0;
				err_r <= 1'b1; done_tog <= req_tog; rd_cmd <= 1'b0; st <= S_IDLE;
			end
		end
		S_DONE: begin
			tmo <= tmo + 26'd1;
			if (!(|ack_sel)) begin
				err_r <= 1'b0; done_tog <= req_tog; rd_cmd <= 1'b0; st <= S_IDLE;
			end else if (&tmo) begin
				err_r <= 1'b1; done_tog <= req_tog; rd_cmd <= 1'b0; st <= S_IDLE;
			end
		end
		default: st <= S_IDLE;
		endcase
	end
end

endmodule
