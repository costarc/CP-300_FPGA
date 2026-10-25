// Behavioural 64 Mbit SDR SDRAM (4 banks x 2048 rows x 256 columns x 32 bits), simulation only.
// Handles mode register (CAS latency), ACTIVE, READ, WRITE (with DQM), AUTO REFRESH; counts refreshes.
module sdram_chip (
	inout  [31:0] DQ, input [10:0] A, input [1:0] BA, input nCS, nWE, nRAS, nCAS, input CLK, CKE, input [3:0] DQM
);
reg [31:0] mem [0:2097151];
reg [10:0] row [0:3];
reg [2:0]  cl = 2;
reg [31:0] dq_out;
reg        dq_oe = 0;
reg [31:0] rd_pipe [0:7];
reg        rd_v [0:7];
integer    i, refreshes = 0, bad = 0;
reg        loaded = 0;
initial begin for (i = 0; i < 8; i = i + 1) rd_v[i] = 0; end
assign DQ = dq_oe ? dq_out : 32'hzzzzzzzz;
wire [2:0] cmd = {nRAS, nCAS, nWE};
wire [20:0] widx = {BA, row[BA], A[7:0]};
always @(posedge CLK) begin
	dq_oe <= 0;
	for (i = 7; i > 0; i = i - 1) begin rd_pipe[i] <= rd_pipe[i-1]; rd_v[i] <= rd_v[i-1]; end
	rd_v[0] <= 0;
	if (rd_v[cl-1]) begin dq_out <= rd_pipe[cl-1]; dq_oe <= 1; end
	if (!nCS) case (cmd)
		3'b000: begin cl <= A[6:4]; loaded <= 1; end
		3'b001: refreshes <= refreshes + 1;
		3'b011: row[BA] <= A;
		3'b101: begin rd_pipe[0] <= mem[widx]; rd_v[0] <= 1; end
		3'b100: begin
			if (!DQM[0]) mem[widx][7:0]   <= DQ[7:0];
			if (!DQM[1]) mem[widx][15:8]  <= DQ[15:8];
			if (!DQM[2]) mem[widx][23:16] <= DQ[23:16];
			if (!DQM[3]) mem[widx][31:24] <= DQ[31:24];
		end
		default: ;
	endcase
end
endmodule
