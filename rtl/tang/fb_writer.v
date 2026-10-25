//
// Frame buffer writer: stores the CP-300 picture (512 x 192, 1 bit per pixel, 12 KB) in the HyperRAM.
//
// Three frame buffers (FB_BASE + n * 16 KB, n = 0..2) rotate: the writer fills `target`; when the core's
// vertical sync starts the frame is complete (`latest`) and the writer moves on to a buffer that is
// neither `latest` nor the one the scan-out reads (`disp_raw`, from the pixel clock domain).
// Layout: byte address = base + line * 64 + (x / 16) * 2, a 16-bit word holds 16 pixels, leftmost in bit 15.
//
module fb_writer #(parameter [21:0] FB_BASE = 22'h010000) (
	input         clk,
	input         resetn,

	// from the core (see videoctrl): sampled on pxen while screen is high
	input         pxen,
	input         screen,
	input         inkbit,
	input         vs_n,             // core vertical sync, low = active

	// psram_arb client
	output        req,
	output [21:0] addr,
	output [15:0] data,
	input         ack,

	output reg [1:0] latest,        // last complete frame buffer, 3 = none yet
	input      [1:0] disp_raw       // buffer being read by the scan-out (other clock domain), 3 = none
);

wire [1:0] disp;
sync_stable #(.W(2), .INIT(2'd3)) disp_sync (.clk(clk), .din(disp_raw), .dout(disp));

function [1:0] pick(input [1:0] a, input [1:0] b);     // a buffer that is neither a nor b
	pick = (a != 2'd0 && b != 2'd0) ? 2'd0 : (a != 2'd1 && b != 2'd1) ? 2'd1 : 2'd2;
endfunction

function [21:0] base(input [1:0] n);
	base = FB_BASE + {n, 14'd0};
endfunction

reg [15:0] sh;
reg  [8:0] x;
reg  [7:0] y;
reg        screen_d, vs_d;
reg  [1:0] target;

// two words waiting for the arbiter
reg [21:0] a0, a1;
reg [15:0] d0, d1;
reg  [1:0] cnt;

assign req  = (cnt != 2'd0);
assign addr = a0;
assign data = d0;

wire        push   = resetn && pxen && screen && (x[3:0] == 4'd15);
wire [15:0] pushd  = {sh[14:0], inkbit};
wire [21:0] pusha  = base(target) + {8'd0, y[7:0], 6'd0} + {16'd0, x[8:4], 1'b0};
wire        pop    = ack && (cnt != 2'd0);

always @(posedge clk) begin
	screen_d <= screen;
	vs_d     <= vs_n;

	if (!resetn) begin
		x <= 9'd0; y <= 8'd0; cnt <= 2'd0; target <= 2'd0; latest <= 2'd3;
	end else begin
		if (pxen && screen) begin
			sh <= {sh[14:0], inkbit};
			x  <= x + 9'd1;
		end
		if (screen_d && !screen) begin                  // end of a line
			x <= 9'd0;
			if (y != 8'd255) y <= y + 8'd1;
		end
		if (vs_d && !vs_n) begin                        // vertical sync: the frame is complete
			x <= 9'd0;
			y <= 8'd0;
			latest <= target;
			target <= pick(target, disp);
		end

		case ({push, pop})
		2'b10: begin
			if (cnt == 2'd0) begin a0 <= pusha; d0 <= pushd; cnt <= 2'd1; end
			else if (cnt == 2'd1) begin a1 <= pusha; d1 <= pushd; cnt <= 2'd2; end
			// full: the word is dropped
		end
		2'b01: begin
			a0 <= a1; d0 <= d1; cnt <= cnt - 2'd1;
		end
		2'b11: begin
			if (cnt == 2'd1) begin a0 <= pusha; d0 <= pushd; end
			else begin a0 <= a1; d0 <= d1; a1 <= pusha; d1 <= pushd; end
		end
		default: ;
		endcase
	end
end

endmodule
