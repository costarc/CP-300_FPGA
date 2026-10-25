// Simulation of the frame buffer path: arbiter + Z80 RAM bridge + frame writer + scan-out, with a
// behavioural PSRAM, a core video source (672 x 262 raster, 512 x 192 picture) and random Z80 traffic.
// Checks: every displayed frame is one complete frame (no tearing), the pixels are where they belong
// (640x480, picture 512 x 384 centred, border around), and the Z80 reads back what it wrote.
`timescale 1ns/1ps
module tb_fb;

reg clk = 0, clk_pix = 0;
always #11.905 clk = ~clk;          // 42 MHz
always #19.84 clk_pix = ~clk_pix;   // 25.2 MHz
reg resetn = 0;
initial begin #200 resetn = 1; end

localparam [17:0] INK = 18'b000001_000010_000011, PAPER = 18'b001000_000100_000010, BORDER = 18'b100000_010000_001000;

// ---------------------------------------------------------------- core video source
reg [9:0] hc = 0;
reg [8:0] vc = 0;
reg [1:0] pd = 0;
reg [15:0] fnum = 0;
wire pxen = (pd == 2'd3);
wire [9:0] px = hc - 10'd135;
wire [8:0] py = vc - 9'd50;
wire screen = (hc >= 135 && hc < 647 && vc >= 50 && vc < 242);
wire [1:0] f3 = fnum % 3;
function pat(input [9:0] x, input [8:0] y, input [1:0] f);
	pat = (((x >> 2) + y + f) % 3) == 0;
endfunction
wire inkbit = pat(px, py, f3);
wire vs_n = !(vc < 2);
always @(posedge clk) begin
	pd <= pd + 1;
	if (pxen) begin
		if (hc == 671) begin
			hc <= 0;
			if (vc == 261) begin vc <= 0; fnum <= fnum + 1; end else vc <= vc + 1;
		end else hc <= hc + 1;
	end
end

// ---------------------------------------------------------------- the design
wire        c0_req, c0_we, c0_ack, c1_req, c1_ack, c2_req, c2_ack, ready;
wire [21:0] c0_addr, c1_addr, c2_addr;
wire [15:0] c0_din, c1_din, arb_dout;
wire        ps_read, ps_write, ps_busy, ps_bw;
wire [21:0] ps_addr;
wire [15:0] ps_din, ps_dout;

`ifdef USE_SDRAM
wire [31:0] sd_dq; wire [10:0] sd_a; wire [1:0] sd_ba; wire sd_ncs, sd_nwe, sd_nras, sd_ncas, sd_clk, sd_cke; wire [3:0] sd_dqm;
sdram_ctrl #(.FREQ(42_000_000)) psram (.clk(clk), .clk_sdram(~clk), .resetn(resetn), .read(ps_read), .write(ps_write),
	.addr(ps_addr), .din(ps_din), .byte_write(ps_bw), .dout(ps_dout), .busy(ps_busy),
	.SDRAM_DQ(sd_dq), .SDRAM_A(sd_a), .SDRAM_BA(sd_ba), .SDRAM_nCS(sd_ncs), .SDRAM_nWE(sd_nwe), .SDRAM_nRAS(sd_nras),
	.SDRAM_nCAS(sd_ncas), .SDRAM_CLK(sd_clk), .SDRAM_CKE(sd_cke), .SDRAM_DQM(sd_dqm));
sdram_chip chip (.DQ(sd_dq), .A(sd_a), .BA(sd_ba), .nCS(sd_ncs), .nWE(sd_nwe), .nRAS(sd_nras), .nCAS(sd_ncas), .CLK(sd_clk), .CKE(sd_cke), .DQM(sd_dqm));
`else
PsramController psram (.clk(clk), .clk_p(clk), .resetn(resetn), .read(ps_read), .write(ps_write),
	.byte_write(ps_bw), .addr(ps_addr), .din(ps_din), .dout(ps_dout), .busy(ps_busy),
	.O_psram_ck(), .IO_psram_rwds(), .IO_psram_dq(), .O_psram_cs_n());
`endif

psram_arb arb (.clk(clk), .resetn(resetn), .ready(ready),
	.c0_req(c0_req), .c0_we(c0_we), .c0_addr(c0_addr), .c0_din(c0_din), .c0_bw(1'b1), .c0_ack(c0_ack),
	.c1_req(c1_req), .c1_we(1'b1), .c1_addr(c1_addr), .c1_din(c1_din), .c1_bw(1'b0), .c1_ack(c1_ack),
	.c2_req(c2_req), .c2_we(1'b0), .c2_addr(c2_addr), .c2_din(16'd0), .c2_bw(1'b0), .c2_ack(c2_ack),
	.dout(arb_dout), .ps_read(ps_read), .ps_write(ps_write), .ps_bw(ps_bw), .ps_addr(ps_addr),
	.ps_din(ps_din), .ps_dout(ps_dout), .ps_busy(ps_busy));

reg        z_rd = 0, z_wr = 0;
reg [15:0] z_a = 0;
reg  [7:0] z_d = 0;
wire [7:0] z_q;
wire       z_stall;
ram_bridge bridge (.clk(clk), .resetn(resetn), .rd(z_rd), .wr(z_wr), .a(z_a), .din(z_d), .dout(z_q), .stall(z_stall),
	.req(c0_req), .we(c0_we), .addr(c0_addr), .wdata(c0_din), .ack(c0_ack), .rdata(arb_dout));

wire [1:0] fb_latest, fb_disp;
fb_writer fbw (.clk(clk), .resetn(resetn), .pxen(pxen), .screen(screen), .inkbit(inkbit), .vs_n(vs_n),
	.req(c1_req), .addr(c1_addr), .data(c1_din), .ack(c1_ack), .latest(fb_latest), .disp_raw(fb_disp));

wire [7:0] v_r, v_g, v_b;
wire v_hs, v_vs, v_de;
fb_scanout fbs (.clk(clk), .resetn(resetn), .clk_pix(clk_pix),
	.req(c2_req), .addr(c2_addr), .ack(c2_ack), .rdata(arb_dout),
	.latest(fb_latest), .ink_rgb(INK), .paper_rgb(PAPER), .border_rgb(BORDER), .disp_o(fb_disp),
	.spi_sck(1'b0), .spi_ss3(1'b1), .spi_di(1'b0),
	.r(v_r), .g(v_g), .b(v_b), .hs(v_hs), .vs(v_vs), .de(v_de));

// ---------------------------------------------------------------- Z80 traffic
reg [7:0] shadow [0:65535];
reg       known [0:65535];
integer   zerr = 0, zops = 0, zmax = 0, t0, i;
initial for (i = 0; i < 65536; i = i + 1) known[i] = 0;
reg [31:0] seed = 32'h1234567;
function [31:0] rnd(input [31:0] s); rnd = s * 1664525 + 1013904223; endfunction

initial begin : z80
	integer n, gap;
	wait (ready);
	repeat (50) @(posedge clk);
	forever begin
		seed = rnd(seed);
		gap = 20 + (seed[15:8] % 60);
		repeat (gap) @(posedge clk);
		seed = rnd(seed);
		z_a = 16'h4000 + (seed[23:8] % 16'hC000);
		if (seed[3:0] < 6 && known[z_a]) begin
			z_rd = 1; t0 = $time; @(posedge clk);
			while (z_stall) @(posedge clk);
			if (($time - t0) > zmax) zmax = $time - t0;
			if (z_q !== shadow[z_a]) begin zerr = zerr + 1; $display("Z80 read error %h: %h expected %h", z_a, z_q, shadow[z_a]); end
			repeat (10) @(posedge clk);
			z_rd = 0;
		end else begin
			z_d = seed[31:24]; z_wr = 1; t0 = $time; @(posedge clk);
			while (z_stall) @(posedge clk);
			if (($time - t0) > zmax) zmax = $time - t0;
			shadow[z_a] = z_d; known[z_a] = 1;
			repeat (10) @(posedge clk);
			z_wr = 0;
		end
		zops = zops + 1;
	end
end

// ---------------------------------------------------------------- scan-out checker
function [7:0] e8(input [5:0] c); e8 = {c, c[5:4]}; endfunction
wire [23:0] ink_o    = {e8(INK[5:0]),    e8(INK[11:6]),    e8(INK[17:12])};
wire [23:0] paper_o  = {e8(PAPER[5:0]),  e8(PAPER[11:6]),  e8(PAPER[17:12])};
wire [23:0] border_o = {e8(BORDER[5:0]), e8(BORDER[11:6]), e8(BORDER[17:12])};
wire [23:0] pix = {v_r, v_g, v_b};

reg [9:0] h1, h2, h3, v1, v2, v3;
always @(posedge clk_pix) begin
	h1 <= fbs.h; v1 <= fbs.v; h2 <= h1; v2 <= v1; h3 <= h2; v3 <= v2;   // output is 2 clocks behind the counters
end
wire        inwin = (h2 >= 64 && h2 < 576 && v2 >= 48 && v2 < 432);
wire  [9:0] wx = h2 - 64;
wire  [9:0] wy = v2 - 48;

integer frames = 0, perr = 0, torn = 0, shown = 0, checked = 0;
integer phases [0:2]; initial begin phases[0]=0; phases[1]=0; phases[2]=0; end
integer cur_f = -1;
reg [1:0] first_ink_group;
integer g;
always @(posedge clk_pix) if (fbs.disp != 3 && v_de) begin
	if (!inwin) begin
		if (pix !== border_o) begin perr = perr + 1; if (perr < 10) $display("border pixel wrong at %0d,%0d: %h", h2, v2, pix); end
	end else begin
		// the first row tells which frame it is: 3 groups of 4 pixels, exactly one is ink
		if (wy == 0 && wx == 0) cur_f = -1;
		if (wy == 0 && wx < 12 && pix === ink_o) begin g = wx / 4; cur_f = (3 - g) % 3; end
		if (cur_f >= 0 && !(wy == 0 && wx < 12)) begin
			checked = checked + 1; if (wx == 12 && wy == 0) phases[cur_f] = phases[cur_f] + 1;
			if (pix !== (pat(wx, wy >> 1, cur_f) ? ink_o : paper_o)) begin
				perr = perr + 1;
				if (perr < 10) $display("pixel wrong at x=%0d row=%0d: %h (frame phase %0d)", wx, wy, pix, cur_f);
			end
		end
	end
end
always @(posedge clk_pix) if (fbs.disp != 3 && h2 == 10'd0 && v2 == 10'd0) shown = shown + 1;

initial begin
	#120_000_000;     // 7 frames
	$display("frame phases seen %0d/%0d/%0d, pixels checked %0d", phases[0], phases[1], phases[2], checked);
	`ifdef USE_SDRAM
	$display("SDRAM refreshes %0d", chip.refreshes);
`endif
	$display("frames shown %0d, pixel errors %0d, Z80 ops %0d, Z80 errors %0d, worst Z80 wait %0d ns", shown, perr, zops, zerr, zmax);
	if (perr == 0 && zerr == 0 && shown >= 3 && checked > 1000000) $display("PASS"); else $display("FAIL");
	$finish;
end
endmodule
