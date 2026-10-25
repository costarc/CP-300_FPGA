//
// Frame buffer scan-out: standard 640x480 @ 60 Hz (CEA mode 1, 25.2 MHz pixel clock) video out of the
// frame buffer that fb_writer fills in the HyperRAM, with the CP-300 picture (512 x 192, every line shown
// twice = 512 x 384) centred, the menu OSD on top, and the border colour around it.
//
// clk is the core / HyperRAM clock, clk_pix the pixel clock; they are unrelated. The two sides talk
// through: a request toggle with the row to fetch (pixel -> core), and 2 line buffers that the core side
// fills one video line ahead (the row is read out of RAM 31 us before it is shown).
//
module fb_scanout #(parameter [21:0] FB_BASE = 22'h010000) (
	input         clk,
	input         resetn,
	input         clk_pix,

	// psram_arb client (read only)
	output        req,
	output [21:0] addr,
	input         ack,
	input  [15:0] rdata,

	// from fb_writer / the core (core clock domain)
	input   [1:0] latest,
	input  [17:0] ink_rgb,
	input  [17:0] paper_rgb,
	input  [17:0] border_rgb,
	output  [1:0] disp_o,           // buffer being shown (pixel clock domain)

	// OSD SPI port of the IO controller
	input         spi_sck,
	input         spi_ss3,
	input         spi_di,

	// video, pixel clock domain
	output reg [7:0] r,
	output reg [7:0] g,
	output reg [7:0] b,
	output reg       hs,
	output reg       vs,
	output reg       de
);

// ------------------------------------------------------------------ pixel clock side
wire  [1:0] latest_p;
wire [17:0] ink_p, paper_p, border_p;
sync_stable #(.W(2),  .INIT(2'd3)) s_latest (.clk(clk_pix), .din(latest),     .dout(latest_p));
sync_stable #(.W(18), .INIT(18'd0)) s_ink    (.clk(clk_pix), .din(ink_rgb),    .dout(ink_p));
sync_stable #(.W(18), .INIT(18'd0)) s_paper  (.clk(clk_pix), .din(paper_rgb),  .dout(paper_p));
sync_stable #(.W(18), .INIT(18'd0)) s_border (.clk(clk_pix), .din(border_rgb), .dout(border_p));

reg  [9:0] h = 10'd0, v = 10'd0;
reg  [1:0] disp = 2'd3;
assign disp_o = disp;

// timing: 640 + 16 + 96 + 48 = 800, 480 + 10 + 2 + 33 = 525
always @(posedge clk_pix) begin
	if (h == 10'd799) begin
		h <= 10'd0;
		v <= (v == 10'd524) ? 10'd0 : v + 10'd1;
	end else
		h <= h + 10'd1;
	if (h == 10'd0 && v == 10'd0) disp <= latest_p;        // the frame shown is the newest complete one
end

wire h_act = (h < 10'd640);
wire v_act = (v < 10'd480);
wire win   = (h >= 10'd64) && (h < 10'd576) && (v >= 10'd48) && (v < 10'd432) && (disp != 2'd3);
wire [8:0] xo = h - 10'd64;
wire [8:0] ro = v - 10'd48;

// the row to fetch next: line v+1's row, asked for when line v starts
reg        rq_t = 1'b0;
reg  [8:0] rq_row;
reg        rq_valid;
reg  [1:0] rq_disp;
wire [9:0] vn = v + 10'd1;
always @(posedge clk_pix) begin
	if (h == 10'd0) begin
		rq_valid <= (vn >= 10'd48) && (vn < 10'd432) && (disp != 2'd3);
		rq_row   <= vn - 10'd48;
		rq_disp  <= disp;
	end
	if (h == 10'd2) rq_t <= ~rq_t;        // the row/valid/disp registers are steady by now
end

// line buffers: 2 x 32 words, written by the core side, read here
reg [15:0] lb [0:63];
wire [15:0] lw = lb[{ro[0], xo[8:4]}];

reg [17:0] col;
reg        hs_q, vs_q, de_q, h_act_q, v_act_q;
always @(posedge clk_pix) begin
	h_act_q <= h_act;
	v_act_q <= v_act;
	col  <= !win ? border_p : (lw[~xo[3:0]] ? ink_p : paper_p);
	hs_q <= ~((h >= 10'd656) && (h < 10'd752));
	vs_q <= ~((v >= 10'd490) && (v < 10'd492));
	de_q <= h_act && v_act;
end

// OSD overlay: half-rate pixel enable so the 256-wide menu is 512 wide, as 2 x 2 pixels
reg ce_osd = 1'b0;
always @(posedge clk_pix) ce_osd <= ~ce_osd;

wire [5:0] o_r, o_g, o_b;
osd #(.OSD_X_OFFSET(11'd0), .OSD_Y_OFFSET(11'd0), .OSD_COLOR(3'd4), .OSD_AUTO_CE(1'b0),
      .USE_BLANKS(1'b1), .OUT_COLOR_DEPTH(6), .BIG_OSD(1'b1)) osd (
	.clk_sys ( clk_pix ),
	.ce      ( ce_osd  ),
	.SPI_SCK ( spi_sck ),
	.SPI_SS3 ( spi_ss3 ),
	.SPI_DI  ( spi_di  ),
	.rotate  ( 2'b00   ),
	.R_in    ( col[5:0]   ),
	.G_in    ( col[11:6]  ),
	.B_in    ( col[17:12] ),
	.HBlank  ( ~h_act_q ),
	.VBlank  ( ~v_act_q ),
	.HSync   ( hs_q ),
	.VSync   ( vs_q ),
	.R_out   ( o_r ),
	.G_out   ( o_g ),
	.B_out   ( o_b )
);

always @(posedge clk_pix) begin
	r  <= {o_r, o_r[5:4]};
	g  <= {o_g, o_g[5:4]};
	b  <= {o_b, o_b[5:4]};
	hs <= hs_q;
	vs <= vs_q;
	de <= de_q;
end

// ------------------------------------------------------------------ core clock side: the row fetcher
reg  [2:0] rq_s = 3'd0;
always @(posedge clk) rq_s <= {rq_s[1:0], rq_t};
wire rq_edge = (rq_s[2] != rq_s[1]);

reg        busy;
reg  [4:0] w;
reg  [8:0] row_c;
reg  [1:0] disp_c;
reg        buf_c;

assign req  = busy;
assign addr = FB_BASE + {disp_c, 14'd0} + {7'd0, row_c[8:1], 6'd0} + {16'd0, w, 1'b0};

always @(posedge clk) begin
	if (!resetn) begin
		busy <= 1'b0;
	end else begin
		if (rq_edge && rq_valid && !busy) begin
			busy   <= 1'b1;
			w      <= 5'd0;
			row_c  <= rq_row;
			disp_c <= rq_disp;
		end
		if (busy && ack) begin
			lb[{row_c[0], w}] <= rdata;
			w <= w + 5'd1;
			if (w == 5'd31) busy <= 1'b0;
		end
	end
end

endmodule
