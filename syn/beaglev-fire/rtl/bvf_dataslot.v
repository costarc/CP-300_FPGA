//
// CP-300 FPGA, BeagleV-Fire: disk access for the IO controller (replaces apf_dataslot.vhd).
//
// The IO controller (io_ctrl_pocket) asks for a piece of a DMK image: it raises req_tog and fills in
// slot / offset / length / track RAM offset (ports 20-2F, read back by the host through bvf_regs).
// The host (the cp300d daemon) fills the track RAM (read request) or empties it (write request),
// then writes DONE: that flips done_tog, busy = req_tog ^ done_tog drops and the firmware goes on.
// Everything runs on clk: the CDC to the AXI clock is in axil_regbus.
//
// The host also tells which drive slots hold a file (present), their sizes, and "file replaced"
// (chg_set), the same information the Pocket got from the framework's slot table.
//
// Track RAM byte order: little endian words (byte 0 of the track RAM = bits 7:0 of the first word),
// so Linux sees the bytes in order. (The Pocket was big endian.)
//
module bvf_dataslot (
	input         clk,
	input         reset,                 // high

	// host side
	input  [11:0] h_addr,                // 32 bit word address in the 16 KB track RAM
	input         h_we,
	input  [31:0] h_din,
	output [31:0] h_dout,                // one clock after h_addr
	input         done_pulse,
	input         done_err,
	input         sz_we,
	input   [1:0] sz_idx,
	input  [31:0] sz_val,
	input         pres_we,
	input   [3:0] pres_val,
	input   [3:0] chg_set,
	input         scan_we,
	input         scan_val,

	// IO controller side (same names as io_ctrl_pocket)
	input         req_tog,
	input   [1:0] req_slot,
	output        busy,
	output        err,
	input  [13:0] trk_addr,
	input         trk_we,
	input   [7:0] trk_din,
	output  [7:0] trk_dout,
	output [31:0] size_sel,
	output  [3:0] present,
	output  [3:0] changed,
	input   [3:0] chg_clr,
	output        scan_valid
);

// ---------------------------------------------------------------- track RAM, four lanes
wire [7:0] qa [0:3];
wire [7:0] qb [0:3];
reg  [1:0] lane_b;
genvar i;
generate for (i = 0; i < 4; i = i + 1) begin : lane
	bvf_trk_ram ram (
		.clk(clk),
		.a_addr(h_addr),           .a_we(h_we), .a_din(h_din[8*i +: 8]), .a_q(qa[i]),
		.b_addr(trk_addr[13:2]),   .b_we(trk_we && trk_addr[1:0] == i),  .b_din(trk_din), .b_q(qb[i])
	);
end endgenerate
assign h_dout = {qa[3], qa[2], qa[1], qa[0]};
always @(posedge clk) lane_b <= trk_addr[1:0];
assign trk_dout = qb[lane_b];

// ---------------------------------------------------------------- request handshake
reg done_tog = 1'b0;
reg err_r    = 1'b0;
always @(posedge clk) begin
	if (reset) begin
		done_tog <= 1'b0;
		err_r    <= 1'b0;
	end else if (done_pulse) begin
		done_tog <= ~done_tog;
		err_r    <= done_err;
	end
end
assign busy = req_tog ^ done_tog;
assign err  = err_r;

// ---------------------------------------------------------------- slot table written by the host
reg [31:0] sz [0:3];
reg  [3:0] pres = 4'd0;
reg  [3:0] cg   = 4'd0;
reg  [3:0] seen = 4'd0;
reg        scan = 1'b0;
integer k;
initial for (k = 0; k < 4; k = k + 1) sz[k] = 32'd0;
always @(posedge clk) begin
	if (reset) begin
		pres <= 4'd0; cg <= 4'd0; seen <= 4'd0; scan <= 1'b0;
		for (k = 0; k < 4; k = k + 1) sz[k] <= 32'd0;
	end else begin
		if (sz_we)   sz[sz_idx] <= sz_val;
		if (pres_we) pres <= pres_val;
		if (scan_we) scan <= scan_val;
		cg <= cg ^ chg_set;
		for (k = 0; k < 4; k = k + 1)
			if (chg_clr[k]) seen[k] <= cg[k];
	end
end
assign size_sel   = sz[req_slot];
assign present    = pres;
assign changed    = cg ^ seen;
assign scan_valid = scan;

endmodule
