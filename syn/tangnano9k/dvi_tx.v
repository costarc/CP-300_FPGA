//
// DVI/HDMI (video only) transmitter for the Tang Nano 9K: three TMDS channels
// through OSER10 + ELVDS_OBUF, the pixel clock goes straight to the clock pair.
//
module tmds_enc (
	input            clk,
	input      [7:0] d,
	input            c0, c1,
	input            de,
	output reg [9:0] q
);

wire [3:0] n1d = d[0] + d[1] + d[2] + d[3] + d[4] + d[5] + d[6] + d[7];
wire       use_xnor = (n1d > 4'd4) || (n1d == 4'd4 && !d[0]);

wire [8:0] q_m;
assign q_m[0] = d[0];
assign q_m[1] = use_xnor ? ~(q_m[0] ^ d[1]) : (q_m[0] ^ d[1]);
assign q_m[2] = use_xnor ? ~(q_m[1] ^ d[2]) : (q_m[1] ^ d[2]);
assign q_m[3] = use_xnor ? ~(q_m[2] ^ d[3]) : (q_m[2] ^ d[3]);
assign q_m[4] = use_xnor ? ~(q_m[3] ^ d[4]) : (q_m[3] ^ d[4]);
assign q_m[5] = use_xnor ? ~(q_m[4] ^ d[5]) : (q_m[4] ^ d[5]);
assign q_m[6] = use_xnor ? ~(q_m[5] ^ d[6]) : (q_m[5] ^ d[6]);
assign q_m[7] = use_xnor ? ~(q_m[6] ^ d[7]) : (q_m[6] ^ d[7]);
assign q_m[8] = ~use_xnor;

wire [3:0] n1q = q_m[0] + q_m[1] + q_m[2] + q_m[3] + q_m[4] + q_m[5] + q_m[6] + q_m[7];
wire [3:0] n0q = 4'd8 - n1q;

reg signed [4:0] cnt = 5'sd0;    // running disparity

wire signed [4:0] diff_p = $signed({1'b0, n1q}) - $signed({1'b0, n0q});   // n1q - n0q
wire signed [4:0] diff_n = $signed({1'b0, n0q}) - $signed({1'b0, n1q});   // n0q - n1q

always @(posedge clk) begin
	if (de) begin
		if (cnt == 5'sd0 || n1q == 4'd4) begin
			if (!q_m[8]) begin
				q   <= {2'b10, ~q_m[7:0]};
				cnt <= cnt + diff_n;
			end else begin
				q   <= {2'b01, q_m[7:0]};
				cnt <= cnt + diff_p;
			end
		end else if ((cnt > 5'sd0 && n1q > 4'd4) || (cnt < 5'sd0 && n1q < 4'd4)) begin
			q   <= {1'b1, q_m[8], ~q_m[7:0]};
			cnt <= cnt + (q_m[8] ? 5'sd2 : 5'sd0) + diff_n;
		end else begin
			q   <= {1'b0, q_m[8], q_m[7:0]};
			cnt <= cnt - (q_m[8] ? 5'sd0 : 5'sd2) + diff_p;
		end
	end else begin
		cnt <= 5'sd0;
		case ({c1, c0})
			2'b00: q <= 10'b1101010100;
			2'b01: q <= 10'b0010101011;
			2'b10: q <= 10'b0101010100;
			2'b11: q <= 10'b1010101011;
		endcase
	end
end

endmodule


module dvi_tx (
	input        clk_pix,
	input        clk_5x,
	input        rst,
	input  [7:0] r, g, b,
	input        hs, vs, de,
	output       tmds_clk_p, tmds_clk_n,
	output [2:0] tmds_d_p, tmds_d_n
);

wire [9:0] t0, t1, t2;
tmds_enc enc_b (.clk(clk_pix), .d(b), .c0(hs), .c1(vs), .de(de), .q(t0));
tmds_enc enc_g (.clk(clk_pix), .d(g), .c0(1'b0), .c1(1'b0), .de(de), .q(t1));
tmds_enc enc_r (.clk(clk_pix), .d(r), .c0(1'b0), .c1(1'b0), .de(de), .q(t2));

wire [2:0] ser;
OSER10 ser0 (.Q(ser[0]), .D0(t0[0]), .D1(t0[1]), .D2(t0[2]), .D3(t0[3]), .D4(t0[4]),
             .D5(t0[5]), .D6(t0[6]), .D7(t0[7]), .D8(t0[8]), .D9(t0[9]),
             .PCLK(clk_pix), .FCLK(clk_5x), .RESET(rst));
OSER10 ser1 (.Q(ser[1]), .D0(t1[0]), .D1(t1[1]), .D2(t1[2]), .D3(t1[3]), .D4(t1[4]),
             .D5(t1[5]), .D6(t1[6]), .D7(t1[7]), .D8(t1[8]), .D9(t1[9]),
             .PCLK(clk_pix), .FCLK(clk_5x), .RESET(rst));
OSER10 ser2 (.Q(ser[2]), .D0(t2[0]), .D1(t2[1]), .D2(t2[2]), .D3(t2[3]), .D4(t2[4]),
             .D5(t2[5]), .D6(t2[6]), .D7(t2[7]), .D8(t2[8]), .D9(t2[9]),
             .PCLK(clk_pix), .FCLK(clk_5x), .RESET(rst));

ELVDS_OBUF obuf_c  (.I(clk_pix), .O(tmds_clk_p),  .OB(tmds_clk_n));
ELVDS_OBUF obuf_d0 (.I(ser[0]),  .O(tmds_d_p[0]), .OB(tmds_d_n[0]));
ELVDS_OBUF obuf_d1 (.I(ser[1]),  .O(tmds_d_p[1]), .OB(tmds_d_n[1]));
ELVDS_OBUF obuf_d2 (.I(ser[2]),  .O(tmds_d_p[2]), .OB(tmds_d_n[2]));

endmodule
