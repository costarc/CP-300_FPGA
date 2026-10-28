// APB3 slave test: apb_regbus in front of bvf_regs (register path only), plain and paged.
`timescale 1ns/1ps
module tb_apb;
reg clk = 0, pclk = 0, presetn = 0;
always #12 clk = ~clk;
always #5  pclk = ~pclk;      // 100 MHz

reg [19:0] paddr = 0; reg psel = 0, penable = 0, pwrite = 0; reg [31:0] pwdata = 0;
wire [31:0] prdata; wire pready, pslverr;
wire [19:0] b_addr; wire b_wr, b_rd; wire [31:0] b_wdata, b_rdata;

apb_regbus #(.ABITS(20), .PAGED(0)) apb (.pclk(pclk), .presetn(presetn), .paddr(paddr), .psel(psel), .penable(penable),
	.pwrite(pwrite), .pwdata(pwdata), .prdata(prdata), .pready(pready), .pslverr(pslverr),
	.clk(clk), .b_addr(b_addr), .b_wr(b_wr), .b_wdata(b_wdata), .b_rd(b_rd), .b_rdata(b_rdata));

wire [63:0] keys; wire run;
bvf_regs regs (.clk(clk), .reset(1'b0), .addr(b_addr), .wr(b_wr), .wdata(b_wdata), .rd(b_rd), .rdata(b_rdata),
	.run(run), .rst_pulse(), .turbo(), .wp_all(), .keys(keys),
	.io_hold(1'b0), .scan_valid(1'b0), .req_pending(1'b0), .req_is_wr(1'b0), .req_err(1'b0), .dbg(8'h5A),
	.req_slot(32'd0), .req_offset(32'd0), .req_len(32'd0), .req_boff(32'd0),
	.frame_cnt(16'd7), .frame_latest(1'b1), .fb_addr(), .fb_dout(32'hCAFE0001),
	.aud_count(9'd0), .aud_head(32'd0), .aud_lost(1'b0), .aud_pop(), .aud_clr_lost(),
	.trk_addr(), .trk_we(), .trk_dout(32'd0),
	.done_pulse(), .done_err(), .sz_we(), .sz_idx(), .sz_val(), .pres_we(), .pres_val(), .chg_set(),
	.scan_we(), .scan_val(), .rl_we(), .rl_waddr());

task apb_write(input [19:0] a, input [31:0] d);
begin
	@(posedge pclk); paddr <= a; pwdata <= d; pwrite <= 1; psel <= 1; penable <= 0;
	@(posedge pclk); penable <= 1;
	@(posedge pclk); while (!pready) @(posedge pclk);
	psel <= 0; penable <= 0; pwrite <= 0;
end
endtask
task apb_read(input [19:0] a, output [31:0] d);
begin
	@(posedge pclk); paddr <= a; pwrite <= 0; psel <= 1; penable <= 0;
	@(posedge pclk); penable <= 1;
	@(posedge pclk); while (!pready) @(posedge pclk);
	d = prdata;
	psel <= 0; penable <= 0;
end
endtask

integer errors = 0;
task check(input [255:0] what, input [31:0] got, input [31:0] exp);
begin
	if (got !== exp) begin errors = errors + 1; $display("FAIL %0s: got %h expected %h", what, got, exp); end
	else $display("ok   %0s", what);
end
endtask
reg [31:0] v;
initial begin
	repeat (5) @(posedge pclk); presetn = 1; repeat (5) @(posedge pclk);
	apb_read(20'h0, v);          check("ID", v, 32'h43503001);
	apb_write(20'h0C, 32'h12345678); apb_write(20'h10, 32'h9ABCDEF0);
	apb_read(20'h0C, v);         check("KEYS_LO", v, 32'h12345678);
	apb_read(20'h10, v);         check("KEYS_HI", v, 32'h9ABCDEF0);
	apb_read(20'h14, v);         check("FRAME", v, 32'h0001_0007);
	apb_read(20'h30000, v);      check("frame window", v, 32'hCAFE0001);
	apb_write(20'h04, 32'h1);    apb_read(20'h04, v); check("CTRL run", v, 1);
	if (errors == 0) $display("PASS"); else $display("FAIL: %0d errors", errors);
	$finish;
end
initial begin #2000000; $display("FAIL: timeout"); $finish; end
endmodule
