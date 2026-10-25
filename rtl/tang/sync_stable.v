//
// Brings a slowly changing bus into another clock domain: the output follows the input only when
// three consecutive samples agree, so a value caught while some bits are changing is never used.
//
module sync_stable #(parameter W = 2, parameter [W-1:0] INIT = 0) (
	input              clk,
	input      [W-1:0] din,
	output reg [W-1:0] dout
);

reg [W-1:0] a = INIT, b = INIT, c = INIT;

initial dout = INIT;

always @(posedge clk) begin
	a <= din;
	b <= a;
	c <= b;
	if (a == b && b == c) dout <= c;
end

endmodule
