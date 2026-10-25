//
// The Tang Nano 20K's embedded 64 Mbit SDRAM behind the same interface as PsramController (rtl/tang),
// so the arbiter, frame buffer and Z80 RAM bridge are the same on both boards:
//   read / write (one clock pulse), addr = byte address (22 bits), din, byte_write (1: only the byte addr[0]
//   selects), dout = the 16-bit word at addr[21:1] (valid when busy has fallen), busy.
// Adds the periodic auto-refresh the SDRAM needs (every 14 us, while no access is going on).
//
module sdram_ctrl #(parameter FREQ = 42_000_000) (
	input         clk,
	input         clk_sdram,        // clk, 180 degrees later
	input         resetn,
	input         read,
	input         write,
	input  [21:0] addr,
	input  [15:0] din,
	input         byte_write,
	output reg [15:0] dout,
	output        busy,

	inout  [31:0] SDRAM_DQ,
	output [10:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	output        SDRAM_nCS,
	output        SDRAM_nWE,
	output        SDRAM_nRAS,
	output        SDRAM_nCAS,
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output  [3:0] SDRAM_DQM
);

localparam REFRESH_CLKS = FREQ / 1_000_000 * 14;     // 14 us: 4096 refreshes fit in 64 ms with room to spare

wire        s_busy, s_ready, s_enabled;
wire [15:0] s_dout;
reg         s_rd, s_wr, s_ref;
reg  [21:0] s_addr;
reg  [15:0] s_din;
reg   [1:0] s_wdm;
reg  [10:0] tmr;
reg         due;

sdram #(.FREQ(FREQ)) sd (
	.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE), .SDRAM_DQM(SDRAM_DQM),
	.clk(clk), .clk_sdram(clk_sdram), .resetn(resetn),
	.rd(s_rd), .wr(s_wr), .refresh(s_ref),
	.addr({1'b0, s_addr}), .din(s_din), .wdm(s_wdm),
	.dout(s_dout), .dout32(), .data_ready(s_ready), .busy(s_busy), .enabled(s_enabled)
);

assign busy = s_busy | due | s_rd | s_wr | s_ref;

always @(posedge clk) begin
	s_rd  <= 1'b0;
	s_wr  <= 1'b0;
	s_ref <= 1'b0;

	if (!resetn) begin
		tmr <= 0; due <= 1'b0;
	end else begin
		if (tmr == REFRESH_CLKS) begin tmr <= 0; due <= 1'b1; end
		else tmr <= tmr + 1'd1;

		if (s_ready) dout <= s_dout;           // the data is on the bus for this one clock

		if (read || write) begin
			s_addr <= {1'b0, addr[21:1]};
			s_din  <= din;
			s_wdm  <= byte_write ? {~addr[0], addr[0]} : 2'b00;
			s_rd   <= read;
			s_wr   <= write;
		end else if (due && !s_busy && !s_rd && !s_wr) begin
			s_ref <= 1'b1;
			due   <= 1'b0;
		end
	end
end

endmodule
