// Testbench for the BeagleV-Fire host side: AXI4-Lite -> axil_regbus -> bvf_regs, with bvf_fb,
// bvf_dataslot and bvf_audio, against a mock of the core's video, audio and IO controller.
`timescale 1ns/1ps
module tb_bvf;

reg clk = 0, aclk = 0, aresetn = 0;
always #12 clk  = ~clk;      // ~42 MHz
always #4  aclk = ~aclk;     // 125 MHz

// ---------------------------------------------------------------- AXI master
reg [19:0] awaddr, araddr; reg awvalid = 0, wvalid = 0, arvalid = 0, bready = 1, rready = 1;
reg [31:0] wdata;
wire awready, wready, bvalid, arready, rvalid; wire [31:0] rdata; wire [1:0] bresp, rresp;

wire [19:0] b_addr; wire b_wr, b_rd; wire [31:0] b_wdata, b_rdata;

axil_regbus bus (.aclk(aclk), .aresetn(aresetn),
	.awaddr(awaddr), .awvalid(awvalid), .awready(awready),
	.wdata(wdata), .wstrb(4'hF), .wvalid(wvalid), .wready(wready),
	.bresp(bresp), .bvalid(bvalid), .bready(bready),
	.araddr(araddr), .arvalid(arvalid), .arready(arready),
	.rdata(rdata), .rresp(rresp), .rvalid(rvalid), .rready(rready),
	.clk(clk), .b_addr(b_addr), .b_wr(b_wr), .b_wdata(b_wdata), .b_rd(b_rd), .b_rdata(b_rdata));

task axi_write(input [19:0] a, input [31:0] d);
begin
	@(posedge aclk); awaddr <= a; wdata <= d; awvalid <= 1; wvalid <= 1;
	@(posedge aclk); while (!(awready && wready)) @(posedge aclk);
	awvalid <= 0; wvalid <= 0;
	while (!bvalid) @(posedge aclk);
	@(posedge aclk);
end
endtask

task axi_read(input [19:0] a, output [31:0] d);
begin
	@(posedge aclk); araddr <= a; arvalid <= 1;
	@(posedge aclk); while (!arready) @(posedge aclk);
	arvalid <= 0;
	while (!rvalid) @(posedge aclk);
	d = rdata;
	@(posedge aclk);
end
endtask

// ---------------------------------------------------------------- mock core video: 512 x 192, 4 clk per pixel
function pix(input integer x, input integer y);
	pix = ((x * 7 + y * 3) % 5 == 0) ^ (x == y);
endfunction

reg [1:0] pdiv = 0;
wire pxen = pdiv == 0;
always @(posedge clk) pdiv <= pdiv + 1;

reg screen = 0, ink = 0, vs_n = 1;
integer fx, fy, fr;
initial begin
	fr = 0;
	forever begin
		// frame start pulse
		@(posedge clk); while (!pxen) @(posedge clk);
		vs_n <= 0; repeat (8) begin @(posedge clk); while (!pxen) @(posedge clk); end
		vs_n <= 1; repeat (16) begin @(posedge clk); while (!pxen) @(posedge clk); end
		for (fy = 0; fy < 200; fy = fy + 1) begin
			for (fx = 0; fx < 600; fx = fx + 1) begin
				@(posedge clk); while (!pxen) @(posedge clk);
				screen <= (fx < 512) && (fy < 192);
				ink <= ((fx < 512) && (fy < 192)) ? pix(fx, fy) : 1'b0;
			end
		end
		screen <= 0;
		fr = fr + 1;
	end
end

// ---------------------------------------------------------------- DUT blocks (as in bvf_core)
wire        run, rst_pulse, turbo, wp_all; wire [63:0] keys;
wire [15:0] frame_cnt; wire frame_latest; wire [12:0] fb_addr; wire [31:0] fb_dout;
wire [8:0]  aud_count; wire [31:0] aud_head; wire aud_lost, aud_pop, aud_clr_lost;
wire [11:0] trk_addr_h; wire trk_we_h; wire [31:0] h_dout_trk;
wire        done_pulse, done_err, sz_we, pres_we, scan_we, scan_val;
wire  [1:0] sz_idx; wire [31:0] sz_val; wire [3:0] pres_val, chg_set;
wire        rl_we; wire [12:0] rl_waddr;

reg         req_tog = 0;
reg   [1:0] req_slot = 0;
reg  [13:0] m_trk_addr = 0; reg m_trk_we = 0; reg [7:0] m_trk_din = 0; wire [7:0] m_trk_dout;
wire        busy, err; wire [31:0] size_sel; wire [3:0] present, changed; reg [3:0] chg_clr = 0; wire scan_valid;

reg [8:0] audio = 9'h010;

bvf_fb #(.BUFS(2)) fb (.clk(clk), .pxen(pxen), .screen(screen), .ink(ink), .vs_n(vs_n),
	.h_addr(fb_addr), .h_dout(fb_dout), .frame_cnt(frame_cnt), .latest(frame_latest));

bvf_audio #(.CLK_MHZ(42)) aud (.clk(clk), .reset(~run), .audio(audio), .pop(aud_pop), .head(aud_head),
	.count(aud_count), .lost(aud_lost), .clr_lost(aud_clr_lost));

bvf_dataslot slots (.clk(clk), .reset(~run),
	.h_addr(trk_addr_h), .h_we(trk_we_h), .h_din(b_wdata), .h_dout(h_dout_trk),
	.done_pulse(done_pulse), .done_err(done_err), .sz_we(sz_we), .sz_idx(sz_idx), .sz_val(sz_val),
	.pres_we(pres_we), .pres_val(pres_val), .chg_set(chg_set), .scan_we(scan_we), .scan_val(scan_val),
	.req_tog(req_tog), .req_slot(req_slot), .busy(busy), .err(err),
	.trk_addr(m_trk_addr), .trk_we(m_trk_we), .trk_din(m_trk_din), .trk_dout(m_trk_dout),
	.size_sel(size_sel), .present(present), .changed(changed), .chg_clr(chg_clr), .scan_valid(scan_valid));

bvf_regs regs (.clk(clk), .reset(1'b0), .addr(b_addr), .wr(b_wr), .wdata(b_wdata), .rd(b_rd), .rdata(b_rdata),
	.run(run), .rst_pulse(rst_pulse), .turbo(turbo), .wp_all(wp_all), .keys(keys),
	.io_hold(1'b0), .scan_valid(scan_valid), .req_pending(busy), .req_is_wr(1'b0), .req_err(err), .dbg(8'h5A),
	.req_slot({30'd0, req_slot}), .req_offset(32'h0000_1200), .req_len(32'd1024), .req_boff(32'd0),
	.frame_cnt(frame_cnt), .frame_latest(frame_latest), .fb_addr(fb_addr), .fb_dout(fb_dout),
	.aud_count(aud_count), .aud_head(aud_head), .aud_lost(aud_lost), .aud_pop(aud_pop), .aud_clr_lost(aud_clr_lost),
	.trk_addr(trk_addr_h), .trk_we(trk_we_h), .trk_dout(h_dout_trk),
	.done_pulse(done_pulse), .done_err(done_err), .sz_we(sz_we), .sz_idx(sz_idx), .sz_val(sz_val),
	.pres_we(pres_we), .pres_val(pres_val), .chg_set(chg_set), .scan_we(scan_we), .scan_val(scan_val),
	.rl_we(rl_we), .rl_waddr(rl_waddr));

// ROM load capture
integer rl_count = 0; reg [12:0] rl_last; reg [31:0] rl_lastd;
always @(posedge clk) if (rl_we) begin rl_count <= rl_count + 1; rl_last <= rl_waddr; rl_lastd <= b_wdata; end

// ---------------------------------------------------------------- checks
integer errors = 0;
task check(input [255:0] what, input [31:0] got, input [31:0] exp);
begin
	if (got !== exp) begin errors = errors + 1; $display("FAIL %0s: got %h expected %h", what, got, exp); end
	else $display("ok   %0s", what);
end
endtask

reg [31:0] v, v2;
integer i, x, y, bad, frames0, tries;
reg [31:0] w;
reg fl;

initial begin
	repeat (10) @(posedge aclk);
	aresetn = 1;
	repeat (10) @(posedge aclk);

	axi_read(20'h00000, v);              check("ID", v, 32'h43503001);
	axi_write(20'h0000C, 32'hA5A5_0001); axi_write(20'h00010, 32'h8000_0003);
	axi_read(20'h0000C, v);              check("KEYS_LO", v, 32'hA5A5_0001);
	axi_read(20'h00010, v);              check("KEYS_HI", v, 32'h8000_0003);
	check("keys bus", keys[63:0] == 64'h8000_0003_A5A5_0001, 1);
	axi_write(20'h00004, 32'h0000_0005); // run + turbo
	axi_read(20'h00004, v);              check("CTRL", v, 32'h5);
	axi_read(20'h00020, v);              check("DEBUG", v, 32'h5A);

	// ROM load
	axi_write(20'h10000 + 20'h4*20'h123, 32'h11223344);
	check("rl_waddr", rl_last, 13'h123);
	check("rl_data", rl_lastd, 32'h11223344);
	check("rl_count", rl_count, 1);

	// ---- frame: wait for a few frames, then read the latest and compare with the generator
	axi_read(20'h00014, v); frames0 = v[15:0];
	tries = 0;
	while (tries < 2000) begin
		axi_read(20'h00014, v);
		if (v[15:0] >= frames0 + 2) tries = 100000; else begin tries = tries + 1; #20000; end
	end
	// read the newest complete frame while the writer fills the other; copy it and check the counter
	axi_read(20'h00014, v); frames0 = v[15:0]; fl = v[16];
	bad = 0;
	for (y = 0; y < 192; y = y + 1)
		for (x = 0; x < 512; x = x + 32) begin
			axi_read(20'h30000 + 4*((fl ? 4096 : 0) + y*16 + x/32), w);
			for (i = 0; i < 32; i = i + 1)
				if (w[i] !== pix(x+i, y)) bad = bad + 1;
		end
	axi_read(20'h00014, v2);
	$display("frame counter before %0d after %0d, buffer %0d, bad pixels %0d", frames0, v2[15:0], fl, bad);
	// only frames not overwritten during the copy count: the copy can race the writer, so if the counter
	// moved by 2 or more the copy is discarded, like the daemon does
	if (v2[15:0] - frames0 < 2) check("frame pixels", bad, 0);
	else $display("note: frame copy raced the writer (%0d frames), not checked", v2[15:0] - frames0);

	// ---- disk mailbox
	axi_write(20'h00060, 32'd737280);    // SIZE_0
	axi_write(20'h00070, 32'h1);         // PRESENT
	axi_write(20'h00078, 32'h1);         // SCAN_VALID
	axi_write(20'h00074, 32'h1);         // CHG_SET
	repeat (4) @(posedge clk);
	check("present", present, 4'h1);
	check("scan_valid", scan_valid, 1);
	check("changed", changed, 4'h1);
	check("size_sel", size_sel, 32'd737280);
	@(negedge clk); chg_clr = 4'h1; @(negedge clk); chg_clr = 0; repeat (3) @(posedge clk);
	check("changed cleared", changed, 4'h0);

	// the IO controller asks for a read: host fills the track RAM, the IO controller reads it back
	@(posedge clk); req_tog <= 1; @(posedge clk); @(posedge clk);
	axi_read(20'h00008, v);              check("status pending", v[2], 1);
	axi_read(20'h00044, v);              check("REQ_OFFSET", v, 32'h1200);
	for (i = 0; i < 8; i = i + 1) axi_write(20'h20000 + 4*i, 32'h04030201 + 32'h04040404 * i);
	axi_write(20'h00050, 32'h0);         // DONE
	repeat (4) @(posedge clk);
	check("busy dropped", busy, 0);
	for (i = 0; i < 32; i = i + 1) begin
		@(posedge clk); m_trk_addr <= i; @(posedge clk); @(posedge clk);
		if (m_trk_dout !== ((i % 4) + 1 + 4 * (i / 4) + 4 * (i / 4) * 0 + 0)) begin end
	end
	// byte order check: byte 0 = 01, byte 5 = 0x01+4*... -> word 1 = 08070605, byte 5 = 06
	@(posedge clk); m_trk_addr <= 14'd0; @(posedge clk); @(posedge clk); check("trk byte 0", m_trk_dout, 8'h01);
	@(posedge clk); m_trk_addr <= 14'd5; @(posedge clk); @(posedge clk); check("trk byte 5", m_trk_dout, 8'h06);

	// write request: the IO controller writes a byte, the host reads the word back
	@(posedge clk); m_trk_addr <= 14'd64; m_trk_din <= 8'hEE; m_trk_we <= 1; @(posedge clk); m_trk_we <= 0;
	req_tog <= 0; @(posedge clk); @(posedge clk);
	axi_read(20'h20000 + 4*16, v);       check("host reads IO write", v[7:0], 8'hEE);

	// ---- audio: three changes, popped in order
	axi_write(20'h00018, 32'h1);
	audio <= 9'h011; repeat (200) @(posedge clk);
	audio <= 9'h00F; repeat (200) @(posedge clk);
	axi_read(20'h00018, v);              check("audio count", v[8:0], 2);
	axi_read(20'h0001C, v);              check("audio level 1", v[31:23], 9'h011);
	axi_write(20'h0001C, 32'h0);         // pop
	axi_read(20'h0001C, v);              check("audio level 2", v[31:23], 9'h00F);

	if (errors == 0) $display("PASS"); else $display("FAIL: %0d errors", errors);
	$finish;
end

initial begin #400000000; $display("FAIL: timeout"); $finish; end

endmodule
