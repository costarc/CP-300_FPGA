// mf_pllbase.v (from the APF core template's PLL wrapper)

`timescale 1 ps / 1 ps
module mf_pllbase (
		input  wire  refclk,   //  refclk.clk
		input  wire  rst,      //   reset.reset
		output wire  outclk_0, // outclk0.clk
		output wire  outclk_1, // outclk1.clk
		output wire  outclk_2, // outclk2.clk
		output wire  outclk_3, // outclk3.clk
		output wire  outclk_4, // outclk4.clk
		output wire  locked    //  locked.export
	);

	mf_pllbase_0002 mf_pllbase_inst (
		.refclk   (refclk),   //  refclk.clk
		.rst      (rst),      //   reset.reset
		.outclk_0 (outclk_0), // outclk0.clk
		.outclk_1 (outclk_1), // outclk1.clk
		.outclk_2 (outclk_2), // outclk2.clk
		.outclk_3 (outclk_3), // outclk3.clk
		.outclk_4 (outclk_4), // outclk4.clk
		.locked   (locked)    //  locked.export
	);

endmodule
// The IP parameters in mf_pllbase/mf_pllbase_0002.v were edited by hand for the CP-300: 74.25 MHz in,
// 42 MHz (core), 10.5 MHz (video) and 10.5 MHz +90 degrees (video, DDR clock), two spare 21 MHz outputs.
