//
// CP-300 FPGA, BeagleV-Fire: frame capture. The core's 512 x 192 picture (1 bit per pixel, 12 KB) is
// stored in a frame RAM the host can read, with a frame counter.
//
// Word layout (32 bit, little endian host): word = y * 16 + x / 32; pixel x is bit (x mod 32), so the
// leftmost pixel is the least significant bit. BUFS = 2 keeps two frames (buffer select = word
// address bit 12): the host reads buffer `latest`, the writer fills the other one. The host checks
// frame_cnt before and after the copy and drops the copy if the counter moved on by 2 or more.
//
module bvf_fb #(parameter BUFS = 2) (
	input             clk,
	input             pxen,
	input             screen,
	input             ink,
	input             vs_n,

	input      [12:0] h_addr,
	output reg [31:0] h_dout,       // one clock after h_addr

	output reg [15:0] frame_cnt,
	output            latest
);

reg [31:0] mem [0:(BUFS*3072)-1];     // 3072 words per frame
reg [31:0] sh;
reg  [8:0] x;
reg  [7:0] y;
reg        scr_d;
reg        wbuf = 1'b0;
reg        lat  = 1'b0;

initial begin frame_cnt = 16'd0; y = 8'd0; x = 9'd0; sh = 32'd0; scr_d = 1'b0; end

wire        wr_ok  = pxen && screen && (y < 8'd192) && (x[4:0] == 5'd31);
wire [12:0] waddr  = ((BUFS == 2 && wbuf) ? 13'd3072 : 13'd0) + {1'b0, y[7:0], 4'd0} + {4'd0, x[8:5]};
wire [12:0] raddr  = (BUFS == 2 && h_addr[12]) ? 13'd3072 + {1'b0, h_addr[11:0]} : {1'b0, h_addr[11:0]};

always @(posedge clk) begin
	if (pxen) begin
		scr_d <= screen;
		if (!vs_n) y <= 8'd0;
		else if (scr_d && !screen && y != 8'd255) y <= y + 8'd1;

		if (screen) x <= x + 9'd1; else x <= 9'd0;

		if (screen) sh <= {ink, sh[31:1]};

		// last line finished: the frame is complete
		if (scr_d && !screen && y == 8'd191) begin
			lat       <= wbuf;
			frame_cnt <= frame_cnt + 16'd1;
			if (BUFS == 2) wbuf <= ~wbuf;
		end
	end
	if (wr_ok) mem[waddr] <= {ink, sh[31:1]};
	h_dout <= mem[raddr];
end

assign latest = lat;

endmodule
