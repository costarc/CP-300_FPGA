//
// Z80 RAM on the HyperRAM: one byte per CPU bus cycle, as client 0 of psram_arb.
//
// rd/wr are high for the length of a RAM read/write bus cycle. The bridge asks the arbiter for one
// access and keeps `stall` high (the core turns it into a Z80 WAIT) until it is done. An access takes
// about 20 clocks, less than one T state of the 2 MHz CPU, so normally the CPU never waits.
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

	output        req,
	output        we,
	output [21:0] addr,
	output [15:0] wdata,
	input         ack,
	input  [15:0] rdata
);

wire act = rd | wr;
reg  done;
reg  [7:0] q;

assign req   = act & ~done;
assign we    = wr & ~rd;
assign addr  = {6'd0, a};
assign wdata = {din, din};
assign dout  = q;
assign stall = act & ~done;

always @(posedge clk) begin
	if (!resetn || !act) done <= 1'b0;
	else if (ack) begin
		done <= 1'b1;
		q    <= a[0] ? rdata[15:8] : rdata[7:0];
	end
end

endmodule
