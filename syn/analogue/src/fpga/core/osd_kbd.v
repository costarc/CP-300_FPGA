//
// CP-300 FPGA, Analogue Pocket: on-screen keyboard.
//
// Select opens and closes a keyboard drawn over the lower (or upper) 128 lines of the 512 x 192 picture.
// The d-pad moves a cursor over the keys of the CP-300 keyboard (layout and navigation come from
// tools/mkoskbd.py), A presses the key under the cursor for as long as it is held, B latches SHIFT for
// the next key (so ! " # $ ... can be typed), X Y L R are SPACE ENTER BREAK CLEAR, Start moves the
// keyboard between the bottom and the top of the picture.
//
// With the keyboard closed the buttons are keys too: d-pad = arrows, A = SPACE, B = ENTER, X = BREAK,
// Y = CLEAR, L = SHIFT.
//
// `keys` is the 8 x 8 matrix of the CP-300 (bit 8 * row + column, as ext_keys of ht1080z), high = down.
//
// The picture side: for the pixel (px, py) of the 512 x 192 picture the module returns, three clocks
// later, whether the keyboard covers it and its colour. px/py must only change every fourth clock or
// slower (the 10.5 MHz pixel clock enable of the core).
//
// Font: the CP-300 character generator through osd_font (VHDL, rtl/cp300 ROM package); a simulation
// stand-in with the same ports is in sim/.
//
module osd_kbd #(
	parameter TEXT_FILE  = "core/osd_kbd_text.hex",
	parameter CELLS_FILE = "core/osd_kbd_cells.hex",
	parameter NAV_FILE   = "core/osd_kbd_nav.hex",
	parameter [6:0] START_CELL = 7'd32
) (
	input             clk,            // 42 MHz
	input             reset,

	input      [15:0] pad,            // Pocket buttons, synchronised, high = pressed (cont1_key[15:0])
	input             pad_keys_en,    // d-pad and buttons are keys while the keyboard is closed

	input       [8:0] px,
	input       [7:0] py,
	output reg        ovl_on,         // the keyboard covers this pixel
	output reg [23:0] ovl_rgb,

	output reg [63:0] keys,
	output reg        open_o
);

// ------------------------------------------------------------------ ROMs
reg [7:0]  text  [0:2047];
reg [7:0]  cells [0:127];
reg [27:0] nav   [0:127];
initial begin
	$readmemh(TEXT_FILE, text);
	$readmemh(CELLS_FILE, cells);
	$readmemh(NAV_FILE, nav);
end

// ------------------------------------------------------------------ cursor, keys
reg        pos;              // 0 = bottom, 1 = top
reg        shl;              // SHIFT latched
reg  [6:0] cursor;
reg  [7:0] cur_q;            // cells[cursor]
reg [27:0] nav_q;            // nav[cursor]
reg  [3:0] dprev;
reg        a_prev, b_prev, sel_prev, st_prev, quick_prev;
reg  [9:0] rep;
reg [15:0] tcnt;
reg        move;
reg  [1:0] mdir;

wire        tick   = (tcnt == 16'd41999);
wire  [5:0] cur_mat = cur_q[5:0];
wire        cur_is_shift = (cur_mat == 6'd56) || (cur_mat == 6'd57);
wire  [3:0] dnow   = pad[3:0];
wire  [3:0] dedge  = dnow & ~dprev;
wire        quick  = pad[6] | pad[7] | pad[8] | pad[9];

function [1:0] first_dir(input [3:0] d);       // 0 up, 1 down, 2 left, 3 right
	first_dir = d[0] ? 2'd0 : d[1] ? 2'd1 : d[2] ? 2'd2 : 2'd3;
endfunction

always @(posedge clk) begin
	tcnt  <= tick ? 16'd0 : tcnt + 16'd1;
	cur_q <= cells[cursor];
	nav_q <= nav[cursor];

	dprev    <= dnow;
	a_prev   <= pad[4];
	b_prev   <= pad[5];
	sel_prev <= pad[14];
	st_prev  <= pad[15];
	quick_prev <= quick;
	move     <= 1'b0;

	if (reset) begin
		open_o <= 1'b0; pos <= 1'b0; shl <= 1'b0; cursor <= START_CELL; rep <= 10'd0;
	end else begin
		if (pad[14] && !sel_prev) open_o <= ~open_o;

		if (open_o) begin
			if (pad[15] && !st_prev) pos <= ~pos;

			// d-pad: one step on the press, then auto-repeat after 350 ms, every 80 ms
			if (dedge != 4'd0) begin
				move <= 1'b1; mdir <= first_dir(dedge); rep <= 10'd350;
			end else if (dnow != 4'd0 && tick) begin
				if (rep == 10'd0) begin
					move <= 1'b1; mdir <= first_dir(dnow); rep <= 10'd80;
				end else
					rep <= rep - 10'd1;
			end

			// SHIFT latch: B, or A on a SHIFT key; the next key that is pressed and let go clears it
			if (pad[5] && !b_prev) shl <= ~shl;
			else if (pad[4] && !a_prev && cur_is_shift) shl <= ~shl;
			else if ((!pad[4] && a_prev && !cur_is_shift) || (!quick && quick_prev)) shl <= 1'b0;
		end
	end

	if (move) begin
		case (mdir)
			2'd0: cursor <= nav_q[20:14];   // up
			2'd1: cursor <= nav_q[27:21];   // down
			2'd2: cursor <= nav_q[6:0];     // left
			2'd3: cursor <= nav_q[13:7];    // right
		endcase
	end
end

always @* begin
	keys = 64'd0;
	if (open_o) begin
		if (pad[4] && cur_q[7] && !cur_is_shift) keys[cur_mat] = 1'b1;
		keys[55] = pad[6];                  // SPACE
		keys[48] = pad[7];                  // ENTER
		keys[50] = pad[8];                  // BREAK
		keys[49] = pad[9];                  // CLEAR
	end else if (pad_keys_en) begin
		keys[51] = pad[0];                  // UP
		keys[52] = pad[1];                  // DOWN
		keys[53] = pad[2];                  // LEFT
		keys[54] = pad[3];                  // RIGHT
		keys[55] = pad[4];                  // A = SPACE
		keys[48] = pad[5];                  // B = ENTER
		keys[50] = pad[6];                  // X = BREAK
		keys[49] = pad[7];                  // Y = CLEAR
		keys[56] = pad[8];                  // L = SHIFT
	end
	if (shl) keys[56] = 1'b1;
end

// ------------------------------------------------------------------ picture
// stage 0: the position in the keyboard from (px, py)
wire [7:0] yrel   = pos ? py : (py - 8'd64);
wire       inreg  = pos ? (py < 8'd128) : (py >= 8'd64);
wire [3:0] trow   = yrel[6:3];
wire [5:0] tcol   = px[8:3];
wire [2:0] line   = yrel[2:0];
wire [2:0] xbit   = px[2:0];

reg [2:0] krow;               // key row 0..4 of text rows 1..15
always @* begin
	case (trow)
		4'd1, 4'd2, 4'd3:    krow = 3'd0;
		4'd4, 4'd5, 4'd6:    krow = 3'd1;
		4'd7, 4'd8, 4'd9:    krow = 3'd2;
		4'd10, 4'd11, 4'd12: krow = 3'd3;
		default:             krow = 3'd4;
	endcase
end

// stage 1: character and cell
reg [7:0] ch1, cell1;
reg [2:0] line1, xbit1;
reg       hdr1, on1;
always @(posedge clk) begin
	ch1   <= text[{shl, trow, tcol}];
	cell1 <= cells[{krow, tcol[5:2]}];
	line1 <= line;
	xbit1 <= xbit;
	hdr1  <= (trow == 4'd0);
	on1   <= inreg && open_o;
end

// stage 2: glyph row (osd_font has one clock of latency)
wire [7:0] glyph;
osd_font font (.clk(clk), .addr({ch1, line1}), .dout(glyph));
reg [7:0] cell2;
reg [2:0] xbit2;
reg       hdr2, on2;
always @(posedge clk) begin
	cell2 <= cell1;
	xbit2 <= xbit1;
	hdr2  <= hdr1;
	on2   <= on1;
end

// stage 3: colour
wire        dot      = glyph[3'd7 - xbit2];
wire  [5:0] cmat     = cell2[5:0];
wire        key_here = cell2[7] && !hdr2;
wire        cur_hl   = key_here && (cmat == cur_mat) && cur_q[7];
wire        shl_hl   = key_here && shl && (cmat == 6'd56 || cmat == 6'd57);
wire        pressed  = cur_hl && pad[4];

always @(posedge clk) begin
	ovl_on <= on2;
	if (hdr2)
		ovl_rgb <= dot ? 24'hFFFF90 : 24'h203868;
	else if (pressed)
		ovl_rgb <= dot ? 24'h101828 : 24'hFF6040;
	else if (cur_hl)
		ovl_rgb <= dot ? 24'h101828 : 24'hFFD040;
	else if (shl_hl)
		ovl_rgb <= dot ? 24'h101828 : 24'h40D060;
	else
		ovl_rgb <= dot ? 24'hE0E0E0 : 24'h101828;
end

endmodule
