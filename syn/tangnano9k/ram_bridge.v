//
// Z80 RAM on the Tang Nano 9K's HyperRAM: one byte per CPU bus cycle.
//
// rd/wr are high for the length of a RAM read/write bus cycle. The bridge
// starts one PsramController access, and keeps `stall` high (the core turns it
// into a Z80 WAIT) until that access is done. A 42 MHz access takes ~15 clocks,
// less than one T state of the 2 MHz CPU, so normally the CPU never waits.
//
module ram_bridge (
	input         clk,
	input         resetn,
	input         rd,
	input         wr,
	input  [15:0] a,
	input   [7:0] din,
	output  [7:0] dout,
	output        stall,
	output        ready,        // the PSRAM finished its power-up configuration

	// PsramController
	output reg        ps_read,
	output reg        ps_write,
	output reg [21:0] ps_addr,
	output reg [15:0] ps_din,
	input      [15:0] ps_dout,
	input             ps_busy
);

wire act = rd | wr;
reg  issued, seen_busy, done;
reg  ready_r;
assign ready = ready_r;

always @(posedge clk) begin
	ps_read  <= 1'b0;
	ps_write <= 1'b0;

	if (!resetn) begin
		issued <= 1'b0; seen_busy <= 1'b0; done <= 1'b0; ready_r <= 1'b0;
	end else begin
		if (!ps_busy) ready_r <= 1'b1;

		if (!act) begin
			issued <= 1'b0; seen_busy <= 1'b0; done <= 1'b0;
		end else if (!issued) begin
			if (ready_r && !ps_busy && !ps_read && !ps_write) begin
				ps_addr  <= {6'd0, a};
				ps_din   <= {din, din};
				ps_read  <= rd;
				ps_write <= wr & ~rd;
				issued   <= 1'b1;
			end
		end else if (!done) begin
			if (ps_busy) seen_busy <= 1'b1;
			else if (seen_busy) done <= 1'b1;
		end
	end
end

assign stall = act & ~done;
assign dout  = ps_addr[0] ? ps_dout[15:8] : ps_dout[7:0];

endmodule
