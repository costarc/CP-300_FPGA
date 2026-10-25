// pocket_video test: feeds it the timing of videoctrl.vhd (60 Hz: 672 pixels x 263 lines at 10.5 MHz,
// hsync low for 42 pixels, vsync low for 2 lines, 512 x 192 picture from pixel 135 / line 41) and
// checks what the Pocket would see on its 10.5 MHz video clock: one VS pulse per frame, one HS pulse per
// line at least 3 clocks after VS and one clock before DE, DE exactly over the 512 x 192 picture, the
// pixel values and black everywhere else.
`timescale 1ns/1ps
module tb_video;
	reg clk = 0;
	always #11.905 clk = ~clk;

	// core timing
	reg [1:0]  div = 0;
	reg [9:0]  hctr = 0;
	reg [8:0]  vctr = 0;
	wire       pxen = (div == 2'd1);
	wire       screen = (hctr >= 135 && hctr < 135 + 512 && vctr >= 41 && vctr < 41 + 192);
	wire       hs_n = !(hctr < 42);
	wire       vs_n = !(vctr < 2);
	wire [8:0] px = hctr - 135;
	wire [7:0] py = vctr - 41;
	wire       ink = screen && ((px ^ py) & 1);

	always @(posedge clk) begin
		div <= div + 2'd1;
		if (pxen) begin
			if (hctr == 671) begin
				hctr <= 0;
				vctr <= (vctr == 262) ? 9'd0 : vctr + 9'd1;
			end else hctr <= hctr + 10'd1;
		end
	end

	wire [8:0]  a_x; wire [7:0] a_y;
	wire [23:0] o_rgb; wire o_de, o_hs, o_vs;
	pocket_video dut (.clk(clk), .pxen(pxen), .screen(screen), .ink(ink), .hs_n(hs_n), .vs_n(vs_n),
		.ovl_on(1'b0), .ovl_rgb(24'h0), .ink_rgb(24'hE8E8E8),
		.a_x(a_x), .a_y(a_y), .o_rgb(o_rgb), .o_de(o_de), .o_hs(o_hs), .o_vs(o_vs));

	// what core_top does: the 10.5 MHz video clock samples the held values
	reg [23:0] v_rgb; reg v_de, v_hs, v_vs;
	reg [1:0] vdiv = 0;
	always @(posedge clk) begin
		vdiv <= vdiv + 2'd1;
		if (vdiv == 2'd3) begin v_rgb <= o_rgb; v_de <= o_de; v_hs <= o_hs; v_vs <= o_vs; end
	end

	integer fails = 0;
	integer vclk = 0;               // video clock count
	integer vs_count = 0, hs_count = 0, de_pixels = 0, de_lines = 0, line_px = 0, bad_px = 0, bad_black = 0;
	integer last_vs = -100, last_hs = -100, last_de_end = -100, frames = 0;
	integer min_vs_hs = 1000, min_hs_de = 1000;
	reg prev_de = 0;
	integer lines_since_vs = 0;
	integer ex;
	integer xx = 0, yy = 0;
	reg first_de_line = 0;

	always @(posedge clk) if (vdiv == 2'd3) begin
		vclk = vclk + 1;
		if (v_vs) begin
			vs_count = vs_count + 1;
			last_vs = vclk;
			frames = frames + 1;
			yy = 0;
		end
		if (v_hs) begin
			hs_count = hs_count + 1;
			if (vclk - last_vs < min_vs_hs && last_vs > 0 && (vclk - last_vs) < 700) min_vs_hs = vclk - last_vs;
			last_hs = vclk;
		end
		if (v_de && !prev_de) begin
			if (vclk - last_hs < min_hs_de) min_hs_de = vclk - last_hs;
			xx = 0;
		end
		if (v_de) begin
			de_pixels = de_pixels + 1;
			ex = ((xx ^ yy) & 1) ? 24'hE8E8E8 : 0;
			if (v_rgb !== ex[23:0]) bad_px = bad_px + 1;
			xx = xx + 1;
		end else if (vs_count > 0) begin
			if (v_rgb !== 24'h0) bad_black = bad_black + 1;
		end
		if (!v_de && prev_de) begin
			de_lines = de_lines + 1;
			yy = yy + 1;
			if (xx != 512) begin fails = fails + 1; $display("FAIL: line of %0d pixels", xx); end
		end
		prev_de = v_de;
	end

	initial begin
		// four frames (the first is partial: the pipeline starts empty)
		#(11.905 * 2 * 4 * 672 * (4 * 263 + 20));      // four frames and 20 lines
		$display("frames=%0d vs=%0d hs=%0d de_lines=%0d de_pixels=%0d bad_px=%0d bad_black=%0d min VS->HS=%0d HS->DE=%0d",
			frames, vs_count, hs_count, de_lines, de_pixels, bad_px, bad_black, min_vs_hs, min_hs_de);
		if (vs_count < 4 || vs_count > 5) begin fails = fails + 1; $display("FAIL: VS count"); end
		if (hs_count < 4 * 263 + 15 || hs_count > 4 * 263 + 21) begin fails = fails + 1; $display("FAIL: HS count"); end
		if (de_lines != 4 * 192) begin fails = fails + 1; $display("FAIL: DE lines"); end
		if (de_pixels != de_lines * 512) begin fails = fails + 1; $display("FAIL: DE pixels"); end
		if (bad_px != 0) begin fails = fails + 1; $display("FAIL: pixel values"); end
		if (bad_black != 0) begin fails = fails + 1; $display("FAIL: not black outside DE"); end
		if (min_vs_hs < 3) begin fails = fails + 1; $display("FAIL: HS too soon after VS"); end
		if (min_hs_de < 2) begin fails = fails + 1; $display("FAIL: DE too soon after HS"); end
		if (fails == 0) $display("PASS"); else $display("FAILED: %0d", fails);
		$finish;
	end
endmodule
