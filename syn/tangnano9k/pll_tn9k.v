//
// Clocks for the CP-300 on the Tang Nano 9K (27 MHz crystal)
//
//  pll_a : 27 MHz -> 42 MHz core clock (clk) and the same clock 90 degrees later
//          (clk_p, for the HyperRAM clock pin)
//  pll_b : 42 MHz -> 210 MHz (5 x pixel clock for the 10:1 TMDS serializers),
//          divided by 5 again for the HDMI pixel clock (42 MHz, own phase)
//
module pll_tn9k (
	input  clk27,
	output clk,
	output clk_p,
	output clk_tmds,       // 210 MHz
	output clk_pix,        // 42 MHz
	output locked
);

wire lock_a, lock_b;

rPLL #(
	.FCLKIN("27"),
	.DYN_IDIV_SEL("false"), .IDIV_SEL(8),
	.DYN_FBDIV_SEL("false"), .FBDIV_SEL(13),
	.DYN_ODIV_SEL("false"), .ODIV_SEL(16),
	.PSDA_SEL("0100"),
	.DYN_DA_EN("false"),
	.DUTYDA_SEL("1000"),
	.CLKOUT_FT_DIR(1'b1), .CLKOUTP_FT_DIR(1'b1),
	.CLKOUT_DLY_STEP(0), .CLKOUTP_DLY_STEP(0),
	.CLKFB_SEL("internal"),
	.CLKOUT_BYPASS("false"), .CLKOUTP_BYPASS("false"), .CLKOUTD_BYPASS("false"),
	.DYN_SDIV_SEL(2),
	.CLKOUTD_SRC("CLKOUT"), .CLKOUTD3_SRC("CLKOUT"),
	.DEVICE("GW1NR-9C")
) pll_a (
	.CLKOUT(clk), .LOCK(lock_a), .CLKOUTP(clk_p), .CLKOUTD(), .CLKOUTD3(),
	.RESET(1'b0), .RESET_P(1'b0), .CLKIN(clk27), .CLKFB(1'b0),
	.FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0), .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b1111)
);

rPLL #(
	.FCLKIN("42"),
	.DYN_IDIV_SEL("false"), .IDIV_SEL(0),
	.DYN_FBDIV_SEL("false"), .FBDIV_SEL(4),
	.DYN_ODIV_SEL("false"), .ODIV_SEL(4),
	.PSDA_SEL("0000"),
	.DYN_DA_EN("false"),
	.DUTYDA_SEL("1000"),
	.CLKOUT_FT_DIR(1'b1), .CLKOUTP_FT_DIR(1'b1),
	.CLKOUT_DLY_STEP(0), .CLKOUTP_DLY_STEP(0),
	.CLKFB_SEL("internal"),
	.CLKOUT_BYPASS("false"), .CLKOUTP_BYPASS("false"), .CLKOUTD_BYPASS("false"),
	.DYN_SDIV_SEL(2),
	.CLKOUTD_SRC("CLKOUT"), .CLKOUTD3_SRC("CLKOUT"),
	.DEVICE("GW1NR-9C")
) pll_b (
	.CLKOUT(clk_tmds), .LOCK(lock_b), .CLKOUTP(), .CLKOUTD(), .CLKOUTD3(),
	.RESET(~lock_a), .RESET_P(1'b0), .CLKIN(clk), .CLKFB(1'b0),
	.FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0), .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b1111)
);

CLKDIV #(.DIV_MODE("5"), .GSREN("false")) clkdiv5 (
	.CLKOUT(clk_pix), .HCLKIN(clk_tmds), .RESETN(lock_b), .CALIB(1'b0)
);

assign locked = lock_a & lock_b;

endmodule
