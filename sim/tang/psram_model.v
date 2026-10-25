// Behavioural stand-in for rtl/tang/psram_controller.v (simulation only): same ports, 16-bit word RAM,
// busy for the power-up delay and then 12 clocks per access (read 15, as the real one is slower).
module PsramController #(parameter FREQ = 42_000_000, parameter LATENCY = 3) (
	input clk, input clk_p, input resetn,
	input read, input write, input [21:0] addr, input [15:0] din, input byte_write,
	output reg [15:0] dout, output busy,
	output [1:0] O_psram_ck, inout [1:0] IO_psram_rwds, inout [15:0] IO_psram_dq, output [1:0] O_psram_cs_n
);
reg [15:0] mem [0:131071];
reg [7:0] cnt;
reg       init;
reg       op_w;
reg [21:0] a;
reg [15:0] d;
reg       bw;
assign busy = init || (cnt != 0);
assign O_psram_ck = 0; assign O_psram_cs_n = 3;
integer i;
initial begin for (i = 0; i < 131072; i = i + 1) mem[i] = 16'hxxxx; end
always @(posedge clk) begin
	if (!resetn) begin init <= 1; cnt <= 200; end
	else if (init) begin if (cnt != 0) cnt <= cnt - 1; else init <= 0; end
	else begin
		if (cnt != 0) begin
			cnt <= cnt - 1;
			if (cnt == 1) begin
				if (op_w) begin
					if (bw) begin
						if (a[0]) mem[a[21:1]][15:8] <= d[15:8]; else mem[a[21:1]][7:0] <= d[7:0];
					end else mem[a[21:1]] <= d;
				end else dout <= mem[a[21:1]];
			end
		end else if (read || write) begin
			op_w <= write; a <= addr; d <= din; bw <= byte_write;
			cnt <= write ? 10 : 15;
		end
	end
end
endmodule
