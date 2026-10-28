//
// CP-300 FPGA, BeagleV-Fire: the core behind an APB3 slave on PCLK (the cape port of the gateware
// framework). The 42 MHz core clock comes from a PF_CCC fed by PCLK, see gateware/CAPE/CP300.
//
module bvf_core_apb (
	input         pclk,
	input         presetn,
	input  [31:0] paddr,
	input         psel,
	input         penable,
	input         pwrite,
	input  [31:0] pwdata,
	output [31:0] prdata,
	output        pready,
	output        pslverr,

	input         clk,                 // 42 MHz core clock
	input         pll_locked,
	output        irq
);

wire [19:0] b_addr;
wire        b_wr, b_rd;
wire [31:0] b_wdata, b_rdata;

apb_regbus #(.ABITS(20), .PAGED(0)) bus (
	.pclk(pclk), .presetn(presetn), .paddr(paddr[19:0]), .psel(psel), .penable(penable), .pwrite(pwrite),
	.pwdata(pwdata), .prdata(prdata), .pready(pready), .pslverr(pslverr),
	.clk(clk), .b_addr(b_addr), .b_wr(b_wr), .b_wdata(b_wdata), .b_rd(b_rd), .b_rdata(b_rdata)
);

bvf_core_bus core (.clk(clk), .pll_locked(pll_locked), .b_addr(b_addr), .b_wr(b_wr), .b_wdata(b_wdata),
	.b_rd(b_rd), .b_rdata(b_rdata), .irq(irq));

endmodule
