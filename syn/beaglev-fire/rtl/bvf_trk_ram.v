// CP-300 FPGA, BeagleV-Fire: one byte lane of the 16 KB track RAM. True dual port, one clock, plain
// inference (no vendor megafunction). Port A is the host, port B the IO controller.
module bvf_trk_ram (
	input            clk,
	input      [11:0] a_addr, input a_we, input [7:0] a_din, output reg [7:0] a_q,
	input      [11:0] b_addr, input b_we, input [7:0] b_din, output reg [7:0] b_q
);
reg [7:0] m [0:4095];
always @(posedge clk) begin
	if (a_we) m[a_addr] <= a_din;
	a_q <= m[a_addr];
end
always @(posedge clk) begin
	if (b_we) m[b_addr] <= b_din;
	b_q <= m[b_addr];
end
endmodule
