//
// Clocks for the CP-300 on the Tang Nano boards (27 MHz crystal), two independent PLLs:
//
//  pll_a : 27 MHz -> 42 MHz core clock (clk) and the same clock shifted by CLKP_PSDA x 22.5 degrees (clk_p:
//          the HyperRAM clock pin on the 9K, 90 degrees; the SDRAM clock on the 20K, 180 degrees)
//  pll_b : 27 MHz -> 126 MHz (5 x pixel clock for the 10:1 TMDS serialisers), /5 = 25.2 MHz pixel clock
//          (640x480 @ 60 Hz); the two are unrelated, the video path crosses between them in fb_scanout
//
module pll_tang #(parameter DEVICE = "GW1NR-9C", parameter CLKP_PSDA = "0100") (
	input  clk27,
	output clk,
	output clk_p,
	output clk_tmds,       // 126 MHz
	output clk_pix,        // 25.2 MHz
	output locked
);

wire lock_a, lock_b;

rPLL #(
	.FCLKIN("27"),
	.DYN_IDIV_SEL("false"), .IDIV_SEL(8),
	.DYN_FBDIV_SEL("false"), .FBDIV_SEL(13),
	.DYN_ODIV_SEL("false"), .ODIV_SEL(16),
	.PSDA_SEL(CLKP_PSDA),
	.DYN_DA_EN("false"),
	.DUTYDA_SEL("1000"),
	.CLKOUT_FT_DIR(1'b1), .CLKOUTP_FT_DIR(1'b1),
	.CLKOUT_DLY_STEP(0), .CLKOUTP_DLY_STEP(0),
	.CLKFB_SEL("internal"),
	.CLKOUT_BYPASS("false"), .CLKOUTP_BYPASS("false"), .CLKOUTD_BYPASS("false"),
	.DYN_SDIV_SEL(2),
	.CLKOUTD_SRC("CLKOUT"), .CLKOUTD3_SRC("CLKOUT"),
	.DEVICE(DEVICE)
) pll_a (
	.CLKOUT(clk), .LOCK(lock_a), .CLKOUTP(clk_p), .CLKOUTD(), .CLKOUTD3(),
	.RESET(1'b0), .RESET_P(1'b0), .CLKIN(clk27), .CLKFB(1'b0),
	.FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0), .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b1111)
);

rPLL #(
	.FCLKIN("27"),
	.DYN_IDIV_SEL("false"), .IDIV_SEL(2),
	.DYN_FBDIV_SEL("false"), .FBDIV_SEL(13),
	.DYN_ODIV_SEL("false"), .ODIV_SEL(8),
	.PSDA_SEL("0000"),
	.DYN_DA_EN("false"),
	.DUTYDA_SEL("1000"),
	.CLKOUT_FT_DIR(1'b1), .CLKOUTP_FT_DIR(1'b1),
	.CLKOUT_DLY_STEP(0), .CLKOUTP_DLY_STEP(0),
	.CLKFB_SEL("internal"),
	.CLKOUT_BYPASS("false"), .CLKOUTP_BYPASS("false"), .CLKOUTD_BYPASS("false"),
	.DYN_SDIV_SEL(2),
	.CLKOUTD_SRC("CLKOUT"), .CLKOUTD3_SRC("CLKOUT"),
	.DEVICE(DEVICE)
) pll_b (
	.CLKOUT(clk_tmds), .LOCK(lock_b), .CLKOUTP(), .CLKOUTD(), .CLKOUTD3(),
	.RESET(1'b0), .RESET_P(1'b0), .CLKIN(clk27), .CLKFB(1'b0),
	.FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0), .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b1111)
);

CLKDIV #(.DIV_MODE("5"), .GSREN("false")) clkdiv5 (
	.CLKOUT(clk_pix), .HCLKIN(clk_tmds), .RESETN(lock_b), .CALIB(1'b0)
);

assign locked = lock_a & lock_b;

endmodule
