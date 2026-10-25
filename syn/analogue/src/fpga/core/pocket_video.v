//
// CP-300 FPGA, Analogue Pocket: the core's picture in the framework's video format.
//
// The core's raw picture is 512 x 192 pixels at 10.5 MHz; `pxen` is that pixel clock as an enable of
// clk. Everything here runs on clk with pxen; core_top.v registers the outputs with the 10.5 MHz video
// clock (they are stable for four clk, one pixel).
//
// Pipeline, one step per pxen: (a_*) the core's pixel with its coordinates, which the on-screen
// keyboard (osd_kbd) turns into ovl_on / ovl_rgb during the next four clk; (o_*) pixel + keyboard.
// VS and HS are one-pixel pulses made from the core's sync (HS 8 pixels after VS), DE is the 512 x 192
// area, everything else is black.
//
module pocket_video (
	input             clk,
	input             pxen,
	input             screen,        // core: inside the 512 x 192 area
	input             ink,           // core: the pixel
	input             hs_n,          // core sync, active low
	input             vs_n,

	input             ovl_on,        // osd_kbd, for (a_x, a_y), valid at the next pxen
	input      [23:0] ovl_rgb,
	input      [23:0] ink_rgb,

	output reg  [8:0] a_x,
	output reg  [7:0] a_y,
	output reg [23:0] o_rgb,
	output reg        o_de,
	output reg        o_hs,
	output reg        o_vs
);

reg  [8:0] cx;                 // column of the next pixel of the line
reg  [7:0] cy;                 // line of the picture
reg        scr_d;
reg        a_ink, a_scr;
reg  [7:0] hs_pulse_sr;        // the core's hsync pulses, delayed 8 pixels behind the frame pulse
reg        hs_prev, vs_prev;

always @(posedge clk) begin
	if (pxen) begin
		scr_d <= screen;
		if (!vs_n)                     cy <= 8'd0;
		else if (scr_d && !screen)     cy <= cy + 8'd1;
		if (screen) cx <= cx + 9'd1; else cx <= 9'd0;

		a_x   <= cx;
		a_y   <= cy;
		a_ink <= ink;
		a_scr <= screen;

		hs_prev <= hs_n;
		vs_prev <= vs_n;
		hs_pulse_sr <= {hs_pulse_sr[6:0], hs_prev & ~hs_n};
		o_hs <= hs_pulse_sr[7];
		o_vs <= vs_prev & ~vs_n;

		o_de  <= a_scr;
		o_rgb <= !a_scr ? 24'h000000 :
		         ovl_on ? ovl_rgb :
		         a_ink  ? ink_rgb : 24'h000000;
	end
end

endmodule
