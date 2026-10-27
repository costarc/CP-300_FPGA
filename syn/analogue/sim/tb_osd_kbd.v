// On-screen keyboard test: presses the buttons the way the Pocket would, checks the key matrix and
// writes frames of the keyboard picture to osd_<n>.ppm.
`timescale 1ns/1ps
module tb_osd_kbd;
	reg clk = 0;
	reg reset = 1;
	reg [15:0] pad = 0;
	reg  [8:0] px = 0;
	reg  [7:0] py = 0;
	wire        ovl_on;
	wire [23:0] ovl_rgb;
	wire [63:0] keys;
	wire        open_o;
	integer fails = 0;

	osd_kbd #(.TEXT_FILE("../../src/fpga/core/osd_kbd_text.hex"),
	          .CELLS_FILE("../../src/fpga/core/osd_kbd_cells.hex"),
	          .NAV_FILE("../../src/fpga/core/osd_kbd_nav.hex")) dut (
		.clk(clk), .reset(reset), .pad(pad), .pad_keys_en(1'b1), .px(px), .py(py),
		.ovl_on(ovl_on), .ovl_rgb(ovl_rgb), .keys(keys), .open_o(open_o),
		.rl_clk(1'b0), .rl_we(1'b0), .rl_waddr(13'd0), .rl_wdata(32'd0));

	always #11.905 clk = ~clk;

	task tick(input integer n);
		integer i;
		begin for (i = 0; i < n; i = i + 1) @(posedge clk); end
	endtask

	// a button press long enough for the 42 MHz logic
	task press(input integer bit_n);
		begin
			pad[bit_n] = 1'b1; tick(40); pad[bit_n] = 1'b0; tick(40);
		end
	endtask

	task check(input cond, input [255:0] msg);
		begin
			if (!cond) begin $display("FAIL: %0s (t=%0t)", msg, $time); fails = fails + 1; end
		end
	endtask

	// render the picture like core_top does: one pixel per 4 clocks, result read at the 4th
	integer frame = 0;
	task render;
		integer x, y, f, c;
		reg [23:0] rgb;
		begin
			f = $fopen($sformatf("osd_%0d.ppm", frame), "wb");
			$fwrite(f, "P6\n512 192\n255\n");
			for (y = 0; y < 192; y = y + 1)
				for (x = 0; x < 512; x = x + 1) begin
					px = x; py = y;
					tick(4);
					rgb = ovl_on ? ovl_rgb : {8'h30, 8'h30, 8'h30};
					$fwrite(f, "%c%c%c", rgb[23:16], rgb[15:8], rgb[7:0]);
				end
			$fclose(f);
			frame = frame + 1;
		end
	endtask

	initial begin
		tick(10); reset = 0; tick(10);

		// closed: the buttons are keys
		check(!open_o, "closed at start");
		pad[0] = 1; tick(5); check(keys[51], "UP key from d-pad up"); pad[0] = 0; tick(5);
		pad[4] = 1; tick(5); check(keys[55], "SPACE key from A"); pad[4] = 0; tick(5);
		pad[5] = 1; tick(5); check(keys[48], "ENTER key from B"); pad[5] = 0; tick(5);
		pad[8] = 1; tick(5); check(keys[56], "SHIFT key from L"); pad[8] = 0; tick(5);
		render;                                            // frame 0: nothing covered
		check(!ovl_on, "no overlay when closed");

		// open with Select; the cursor starts on A
		press(14);
		check(open_o, "opened by Select");
		pad[4] = 1; tick(10); check(keys == (64'd1 << 1), "A key (matrix 1) pressed on the A key"); pad[4] = 0; tick(10);
		check(keys == 0, "released");
		render;                                            // frame 1: bottom, cursor on A

		// right x3 -> F (matrix 5)
		press(3); press(3); press(3);
		pad[4] = 1; tick(10); check(keys == (64'd1 << 6), "F key after 3 x right"); render; pad[4] = 0; tick(10);  // frame 2: pressed
		// up: row 1 key above D = E? (Q W E R T..): D is at cell col 3 -> R (matrix 18)
		press(0);
		pad[4] = 1; tick(10); check(keys == (64'd1 << 18), "R key after up"); pad[4] = 0; tick(10);
		// down twice -> row 3: cell col 3 is C? (LSHIFT is cells 0-1, Z col2, X col3) -> X = matrix 24
		press(1); press(1);
		pad[4] = 1; tick(10); check(keys == (64'd1 << 24), "X key after down down"); pad[4] = 0; tick(10);

		// SHIFT latch with B: the next key goes out with SHIFT, then the latch is gone
		press(5);
		pad[4] = 1; tick(10);
		check(keys[56] && keys[24], "X with SHIFT while latched");
		render;                                            // frame 3: shift latched, shifted legends
		pad[4] = 0; tick(10);
		check(keys == 0, "latch cleared after the key");

		// A on a SHIFT key toggles the latch instead of pressing it
		press(2); press(2); press(2);                      // left from X: Z, then LSHIFT cells
		pad[4] = 1; tick(10); pad[4] = 0; tick(10);
		check(keys[56], "SHIFT latched by A on the SHIFT key");
		press(5); check(!keys[56], "unlatched by B");

		// quick keys
		pad[6] = 1; tick(5); check(keys[55], "X = SPACE when open"); pad[6] = 0;
		pad[7] = 1; tick(5); check(keys[48], "Y = ENTER when open"); pad[7] = 0;
		pad[8] = 1; tick(5); check(keys[50], "L = BREAK when open"); pad[8] = 0;
		pad[9] = 1; tick(5); check(keys[49], "R = CLEAR when open"); pad[9] = 0;
		tick(10);

		// move to the top with Start
		press(15);
		render;                                            // frame 4: top
		press(14);
		check(!open_o, "closed again");

		if (fails == 0) $display("PASS"); else $display("FAILED: %0d", fails);
		$finish;
	end
endmodule
