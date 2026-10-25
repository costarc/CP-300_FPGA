//
// Three clients share the one PsramController: 0 = Z80 RAM, 1 = frame buffer writer,
// 2 = frame buffer scan-out. Priority 0 > 1 > 2; an access is never interrupted, so a client waits
// for at most the access in progress (about 19 clocks) plus its own.
//
// A client raises req with we/addr/din/bw stable and keeps them until it sees ack (one clock pulse,
// dout is valid in that clock); it must drop req by then (the arbiter stays idle for two clocks).
//
module psram_arb (
	input         clk,
	input         resetn,
	output        ready,        // the PSRAM finished its power-up configuration

	input         c0_req, input c0_we, input [21:0] c0_addr, input [15:0] c0_din, input c0_bw,
	output reg    c0_ack,
	input         c1_req, input c1_we, input [21:0] c1_addr, input [15:0] c1_din, input c1_bw,
	output reg    c1_ack,
	input         c2_req, input c2_we, input [21:0] c2_addr, input [15:0] c2_din, input c2_bw,
	output reg    c2_ack,
	output reg [15:0] dout,

	// PsramController
	output reg        ps_read,
	output reg        ps_write,
	output reg        ps_bw,
	output reg [21:0] ps_addr,
	output reg [15:0] ps_din,
	input      [15:0] ps_dout,
	input             ps_busy
);

localparam S_IDLE = 3'd0, S_START = 3'd1, S_BUSY = 3'd2, S_DONE = 3'd3, S_ACK = 3'd4, S_GAP = 3'd5;

reg [2:0] st;
reg [1:0] who;
reg       ready_r;
assign ready = ready_r;

always @(posedge clk) begin
	ps_read  <= 1'b0;
	ps_write <= 1'b0;
	c0_ack   <= 1'b0;
	c1_ack   <= 1'b0;
	c2_ack   <= 1'b0;

	if (!resetn) begin
		st <= S_IDLE; ready_r <= 1'b0;
	end else begin
		if (!ps_busy) ready_r <= 1'b1;

		case (st)
		S_IDLE: if (ready_r && !ps_busy) begin
			if (c0_req) begin
				who <= 2'd0; ps_addr <= c0_addr; ps_din <= c0_din; ps_bw <= c0_bw;
				ps_read <= ~c0_we; ps_write <= c0_we; st <= S_START;
			end else if (c1_req) begin
				who <= 2'd1; ps_addr <= c1_addr; ps_din <= c1_din; ps_bw <= c1_bw;
				ps_read <= ~c1_we; ps_write <= c1_we; st <= S_START;
			end else if (c2_req) begin
				who <= 2'd2; ps_addr <= c2_addr; ps_din <= c2_din; ps_bw <= c2_bw;
				ps_read <= ~c2_we; ps_write <= c2_we; st <= S_START;
			end
		end
		S_START: st <= S_BUSY;                    // the controller sees read/write now
		S_BUSY:  if (ps_busy) st <= S_DONE;
		S_DONE:  if (!ps_busy) begin dout <= ps_dout; st <= S_ACK; end
		S_ACK: begin
			c0_ack <= (who == 2'd0);
			c1_ack <= (who == 2'd1);
			c2_ack <= (who == 2'd2);
			st <= S_GAP;
		end
		S_GAP: st <= S_IDLE;
		default: st <= S_IDLE;
		endcase
	end
end

endmodule
