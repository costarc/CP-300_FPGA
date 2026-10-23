//============================================================================
//
//  ROM loader for the DE0 port.
//
//  On MiST the ARM controller downloads the system ROM into SDRAM through
//  data_io. The DE0 has no such controller, so this module holds the ROM in
//  on-chip memory (M9K, initialised from ROM_FILE at synthesis) and replays
//  it through the same dn_* download interface after the PLL locks.
//
//  ht1080z.vhd latches dn_wr and forwards it to the SDRAM on its 3.5 MHz
//  clkref (every 12 clocks), so one byte is written every WR_GAP clocks.
//
//============================================================================

module rom_loader #(
	parameter ROM_FILE = "boot.hex",
	parameter ROM_SIZE = 16'h3800,  // 0000-37FF: Model I/III ROM space
	parameter WR_GAP   = 48
) (
	input             clk,
	input             pll_locked,

	output reg        dn_go,
	output reg        dn_wr,
	output     [24:0] dn_addr,
	output reg  [7:0] dn_data,
	output reg        loaded
);

reg [7:0] rom[0:ROM_SIZE-1];
initial $readmemh(ROM_FILE, rom);

reg [15:0] addr;
reg [11:0] delay;
reg  [7:0] q;

assign dn_addr = {9'd0, addr};

always @(posedge clk) q <= rom[addr];

localparam S_INIT = 2'd0, S_FETCH = 2'd1, S_WRITE = 2'd2, S_GAP = 2'd3;
reg [1:0] state;

always @(posedge clk) begin
	dn_wr <= 0;
	delay <= delay + 1'd1;

	if (!pll_locked) begin
		state  <= S_INIT;
		dn_go  <= 0;
		loaded <= 0;
		addr   <= 0;
		delay  <= 0;
	end else if (!loaded) case (state)
		S_INIT:
			// let the SDRAM controller finish its init sequence first
			if (&delay) begin
				dn_go <= 1;
				delay <= 0;
				state <= S_FETCH;
			end
		S_FETCH:
			// two clocks for the registered M9K read
			if (delay == 2) state <= S_WRITE;
		S_WRITE: begin
			dn_data <= q;
			dn_wr   <= 1;
			delay   <= 0;
			state   <= S_GAP;
		end
		S_GAP:
			if (delay == WR_GAP) begin
				delay <= 0;
				if (addr == ROM_SIZE - 1) begin
					dn_go  <= 0;
					loaded <= 1;
				end else begin
					addr  <= addr + 1'd1;
					state <= S_FETCH;
				end
			end
	endcase
end

endmodule
