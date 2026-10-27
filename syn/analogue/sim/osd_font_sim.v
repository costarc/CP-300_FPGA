// Simulation stand-in for osd_font.vhd: the character generator read from out/font.hex (made by
// run_osd.sh from roms/900-65.BIN; not committed, the ROM is copyrighted).
module osd_font (input clk, input [10:0] addr, output reg [7:0] dout,
	input rl_clk, input rl_we, input [12:0] rl_waddr, input [31:0] rl_wdata);
	reg [7:0] rom [0:2047];
	initial $readmemh("font.hex", rom);
	always @(posedge clk) dout <= rom[addr];
endmodule
