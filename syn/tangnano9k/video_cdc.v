//
// Moves the video signal from the core clock (clk_in) to the HDMI pixel clock
// (clk_out). Both are 42 MHz from the same PLL chain, so a 16 entry FIFO that
// the reader starts when it is half full never over- or underflows: only the
// phase between the two clocks is unknown.
//
module video_cdc #(parameter W = 21) (
	input              clk_in,
	input      [W-1:0] din,
	input              clk_out,
	input              rst_out,
	output reg [W-1:0] dout
);

reg [W-1:0] mem [0:15];
reg   [3:0] wptr = 4'd0;

always @(posedge clk_in) begin
	mem[wptr] <= din;
	wptr      <= wptr + 4'd1;
end

wire [3:0] wgray = wptr ^ (wptr >> 1);
reg  [3:0] wg1, wg2;
reg  [3:0] rptr = 4'd0;
reg        run = 1'b0;

function [3:0] g2b(input [3:0] g);
	g2b = {g[3], g[3]^g[2], g[3]^g[2]^g[1], g[3]^g[2]^g[1]^g[0]};
endfunction

wire [3:0] wb  = g2b(wg2);
wire [3:0] occ = wb - rptr;

always @(posedge clk_out) begin
	wg1 <= wgray;
	wg2 <= wg1;
	if (rst_out) begin
		run  <= 1'b0;
		rptr <= 4'd0;
	end else begin
		if (!run && occ >= 4'd8) begin
			run  <= 1'b1;
			rptr <= wb - 4'd8;
		end
		if (run) begin
			dout <= mem[rptr];
			rptr <= rptr + 4'd1;
		end
	end
end

endmodule
