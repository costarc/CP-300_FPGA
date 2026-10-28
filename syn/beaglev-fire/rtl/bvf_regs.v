//
// CP-300 FPGA, BeagleV-Fire: host register block (clk domain). One simple bus, 20 bit byte address,
// 32 bit data, write strobe `wr`, read strobe `rd`; read data is valid TWO clocks after `rd` is
// seen (axil_regbus waits). axil_regbus.v puts an AXI4-Lite slave in front of it.
//
//   0x00000  registers (below)
//   0x10000  ROM load, write only: word n of the ROM image at 0x10000 + 4n (big endian packing:
//            first byte in bits 31:24, as rtl/ht1080z expects); 16 KB system ROM at 0x0000-0x3FFF,
//            2 KB character generator at 0x4000-0x47FF of this window
//   0x20000  track RAM (16 KB), little endian words
//   0x30000  frame RAM, word = y * 16 + x / 32 (+ 0x1000 words for buffer 1), pixel x = bit x mod 32
//
// Registers (byte offsets):
//   00 r  ID = 0x43503001
//   04 rw CTRL    b0 run (0 holds the core and the IO controller in reset), b1 reset pulse (w), b2 turbo,
//                 b3 write protect all disks
//   08 r  STATUS  b0 core held by IO controller, b1 scan valid, b2 disk request pending, b3 request is a write,
//                 b4 request error flag, b5 audio FIFO lost, b6 frame buffer latest
//   0C rw KEYS_LO  matrix bits 31:0   10 rw KEYS_HI  bits 63:32  (bit = 8 * row + column)
//   14 r  FRAME   [15:0] frame counter, [16] buffer holding the newest frame
//   18 r  AUDIO count [8:0]; w b0 clears `lost`      1C r audio head {level,time}; w pops it
//   20 r  DEBUG   last debug byte of the IO controller
//   40 r  REQ_SLOT   44 r REQ_OFFSET   48 r REQ_LEN   4C r REQ_BOFF     the disk request
//   50 w  DONE    b0 = error; completes the request
//   60 w  SIZE_n  (60 + 4n) size of the file in slot n (0-3 floppy drives)   70 w PRESENT mask (8 bits)
//   74 w CHG_SET mask (8 bits)   78 w SCAN_VALID b0   80 w SIZE_6   84 w SIZE_7 (the two FreeHD hard disk images)
//
module bvf_regs (
	input         clk,
	input         reset,
	input  [19:0] addr,
	input         wr,
	input  [31:0] wdata,
	input         rd,
	output reg [31:0] rdata,

	output reg        run,
	output reg        rst_pulse,
	output reg        turbo,
	output reg        wp_all,
	output reg [63:0] keys,

	input             io_hold, scan_valid, req_pending, req_is_wr, req_err,
	input       [7:0] dbg,
	input      [31:0] req_slot, req_offset, req_len, req_boff,

	// frame
	input      [15:0] frame_cnt,
	input             frame_latest,
	output     [12:0] fb_addr,
	input      [31:0] fb_dout,

	// audio
	input       [8:0] aud_count,
	input      [31:0] aud_head,
	input             aud_lost,
	output reg        aud_pop,
	output reg        aud_clr_lost,

	// track RAM
	output     [11:0] trk_addr,
	output            trk_we,
	input      [31:0] trk_dout,

	// disk slots
	output reg        done_pulse,
	output reg        done_err,
	output reg        sz_we,
	output reg  [2:0] sz_idx,
	output reg [31:0] sz_val,
	output reg        pres_we,
	output reg  [7:0] pres_val,
	output reg  [7:0] chg_set,
	output reg        scan_we,
	output reg        scan_val,

	// ROM load (clk)
	output            rl_we,
	output     [12:0] rl_waddr
);

assign fb_addr  = addr[14:2];
assign trk_addr = addr[13:2];
assign trk_we   = wr && addr[19:16] == 4'h2;
assign rl_we    = wr && addr[19:16] == 4'h1;
assign rl_waddr = addr[14:2];
wire   r_sel    = addr[19:8] == 12'h000;

reg  [3:0] win_q;
reg [31:0] reg_q;

initial begin
	run = 1'b0; turbo = 1'b0; wp_all = 1'b0; keys = 64'd0;
	rst_pulse = 1'b0; aud_pop = 1'b0; aud_clr_lost = 1'b0; done_pulse = 1'b0; done_err = 1'b0;
	sz_we = 1'b0; sz_idx = 3'd0; sz_val = 32'd0; pres_we = 1'b0; pres_val = 8'd0; chg_set = 8'd0;
	scan_we = 1'b0; scan_val = 1'b0;
end

always @(posedge clk) begin
	rst_pulse    <= 1'b0;
	aud_pop      <= 1'b0;
	aud_clr_lost <= 1'b0;
	done_pulse   <= 1'b0;
	sz_we        <= 1'b0;
	pres_we      <= 1'b0;
	scan_we      <= 1'b0;
	chg_set      <= 8'd0;

	if (reset) begin
		run <= 1'b0; turbo <= 1'b0; wp_all <= 1'b0; keys <= 64'd0;
	end else if (wr && r_sel) begin
		case (addr[7:2])
		6'h01: begin run <= wdata[0]; rst_pulse <= wdata[1]; turbo <= wdata[2]; wp_all <= wdata[3]; end
		6'h03: keys[31:0]  <= wdata;
		6'h04: keys[63:32] <= wdata;
		6'h06: aud_clr_lost <= wdata[0];
		6'h07: aud_pop <= 1'b1;
		6'h14: begin done_pulse <= 1'b1; done_err <= wdata[0]; end
		6'h18, 6'h19, 6'h1A, 6'h1B: begin sz_we <= 1'b1; sz_idx <= {1'b0, addr[3:2]}; sz_val <= wdata; end
		6'h20, 6'h21: begin sz_we <= 1'b1; sz_idx <= {2'b11, addr[2]}; sz_val <= wdata; end
		6'h1C: begin pres_we <= 1'b1; pres_val <= wdata[7:0]; end
		6'h1D: chg_set <= wdata[7:0];
		6'h1E: begin scan_we <= 1'b1; scan_val <= wdata[0]; end
		default: ;
		endcase
	end

	// read: the registers answer from reg_q, the RAMs from their own output register
	win_q <= addr[19:16];
	if (!r_sel) reg_q <= 32'd0;
	else case (addr[7:2])
	6'h00: reg_q <= 32'h43503001;
	6'h01: reg_q <= {28'd0, wp_all, turbo, 1'b0, run};
	6'h02: reg_q <= {25'd0, frame_latest, aud_lost, req_err, req_is_wr, req_pending, scan_valid, io_hold};
	6'h03: reg_q <= keys[31:0];
	6'h04: reg_q <= keys[63:32];
	6'h05: reg_q <= {15'd0, frame_latest, frame_cnt};
	6'h06: reg_q <= {23'd0, aud_count};
	6'h07: reg_q <= aud_head;
	6'h08: reg_q <= {24'd0, dbg};
	6'h10: reg_q <= req_slot;
	6'h11: reg_q <= req_offset;
	6'h12: reg_q <= req_len;
	6'h13: reg_q <= req_boff;
	default: reg_q <= 32'd0;
	endcase
end

always @(*) begin
	case (win_q)
	4'h0:    rdata = reg_q;
	4'h2:    rdata = trk_dout;
	4'h3:    rdata = fb_dout;
	default: rdata = 32'd0;
	endcase
end

endmodule
