//
// CP-300 for the Analogue Pocket: core top-level
//
// Instantiated by the real top-level: apf_top. Framework glue around the CP-300 core of this repository
// (rtl/ht1080z, rtl/fdc, rtl/cp300); the pin tie-offs below are the framework template's.
//

`default_nettype none

module core_top (

//
// physical connections
//

///////////////////////////////////////////////////
// clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

input   wire            clk_74a, // mainclk1
input   wire            clk_74b, // mainclk1 

///////////////////////////////////////////////////
// cartridge interface
// switches between 3.3v and 5v mechanically
// output enable for multibit translators controlled by pic32

// GBA AD[15:8]
inout   wire    [7:0]   cart_tran_bank2,
output  wire            cart_tran_bank2_dir,

// GBA AD[7:0]
inout   wire    [7:0]   cart_tran_bank3,
output  wire            cart_tran_bank3_dir,

// GBA A[23:16]
inout   wire    [7:0]   cart_tran_bank1,
output  wire            cart_tran_bank1_dir,

// GBA [7] PHI#
// GBA [6] WR#
// GBA [5] RD#
// GBA [4] CS1#/CS#
//     [3:0] unwired
inout   wire    [7:4]   cart_tran_bank0,
output  wire            cart_tran_bank0_dir,

// GBA CS2#/RES#
inout   wire            cart_tran_pin30,
output  wire            cart_tran_pin30_dir,
// when GBC cart is inserted, this signal when low or weak will pull GBC /RES low with a special circuit
// the goal is that when unconfigured, the FPGA weak pullups won't interfere.
// thus, if GBC cart is inserted, FPGA must drive this high in order to let the level translators
// and general IO drive this pin.
output  wire            cart_pin30_pwroff_reset,

// GBA IRQ/DRQ
inout   wire            cart_tran_pin31,
output  wire            cart_tran_pin31_dir,

// infrared
input   wire            port_ir_rx,
output  wire            port_ir_tx,
output  wire            port_ir_rx_disable, 

// GBA link port
inout   wire            port_tran_si,
output  wire            port_tran_si_dir,
inout   wire            port_tran_so,
output  wire            port_tran_so_dir,
inout   wire            port_tran_sck,
output  wire            port_tran_sck_dir,
inout   wire            port_tran_sd,
output  wire            port_tran_sd_dir,
 
///////////////////////////////////////////////////
// cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

output  wire    [21:16] cram0_a,
inout   wire    [15:0]  cram0_dq,
input   wire            cram0_wait,
output  wire            cram0_clk,
output  wire            cram0_adv_n,
output  wire            cram0_cre,
output  wire            cram0_ce0_n,
output  wire            cram0_ce1_n,
output  wire            cram0_oe_n,
output  wire            cram0_we_n,
output  wire            cram0_ub_n,
output  wire            cram0_lb_n,

output  wire    [21:16] cram1_a,
inout   wire    [15:0]  cram1_dq,
input   wire            cram1_wait,
output  wire            cram1_clk,
output  wire            cram1_adv_n,
output  wire            cram1_cre,
output  wire            cram1_ce0_n,
output  wire            cram1_ce1_n,
output  wire            cram1_oe_n,
output  wire            cram1_we_n,
output  wire            cram1_ub_n,
output  wire            cram1_lb_n,

///////////////////////////////////////////////////
// sdram, 512mbit 16bit

output  wire    [12:0]  dram_a,
output  wire    [1:0]   dram_ba,
inout   wire    [15:0]  dram_dq,
output  wire    [1:0]   dram_dqm,
output  wire            dram_clk,
output  wire            dram_cke,
output  wire            dram_ras_n,
output  wire            dram_cas_n,
output  wire            dram_we_n,

///////////////////////////////////////////////////
// sram, 1mbit 16bit

output  wire    [16:0]  sram_a,
inout   wire    [15:0]  sram_dq,
output  wire            sram_oe_n,
output  wire            sram_we_n,
output  wire            sram_ub_n,
output  wire            sram_lb_n,

///////////////////////////////////////////////////
// vblank driven by dock for sync in a certain mode

input   wire            vblank,

///////////////////////////////////////////////////
// i/o to 6515D breakout usb uart

output  wire            dbg_tx,
input   wire            dbg_rx,

///////////////////////////////////////////////////
// i/o pads near jtag connector user can solder to

output  wire            user1,
input   wire            user2,

///////////////////////////////////////////////////
// RFU internal i2c bus 

inout   wire            aux_sda,
output  wire            aux_scl,

///////////////////////////////////////////////////
// RFU, do not use
output  wire            vpll_feed,


//
// logical connections
//

///////////////////////////////////////////////////
// video, audio output to scaler
output  wire    [23:0]  video_rgb,
output  wire            video_rgb_clock,
output  wire            video_rgb_clock_90,
output  wire            video_de,
output  wire            video_skip,
output  wire            video_vs,
output  wire            video_hs,
    
output  wire            audio_mclk,
input   wire            audio_adc,
output  wire            audio_dac,
output  wire            audio_lrck,

///////////////////////////////////////////////////
// bridge bus connection
// synchronous to clk_74a
output  wire            bridge_endian_little,
input   wire    [31:0]  bridge_addr,
input   wire            bridge_rd,
output  reg     [31:0]  bridge_rd_data,
input   wire            bridge_wr,
input   wire    [31:0]  bridge_wr_data,

///////////////////////////////////////////////////
// controller data
// 
// key bitmap:
//   [0]    dpad_up
//   [1]    dpad_down
//   [2]    dpad_left
//   [3]    dpad_right
//   [4]    face_a
//   [5]    face_b
//   [6]    face_x
//   [7]    face_y
//   [8]    trig_l1
//   [9]    trig_r1
//   [10]   trig_l2
//   [11]   trig_r2
//   [12]   trig_l3
//   [13]   trig_r3
//   [14]   face_select
//   [15]   face_start
//   [31:28] type
// joy values - unsigned
//   [ 7: 0] lstick_x
//   [15: 8] lstick_y
//   [23:16] rstick_x
//   [31:24] rstick_y
// trigger values - unsigned
//   [ 7: 0] ltrig
//   [15: 8] rtrig
//
input   wire    [31:0]  cont1_key,
input   wire    [31:0]  cont2_key,
input   wire    [31:0]  cont3_key,
input   wire    [31:0]  cont4_key,
input   wire    [31:0]  cont1_joy,
input   wire    [31:0]  cont2_joy,
input   wire    [31:0]  cont3_joy,
input   wire    [31:0]  cont4_joy,
input   wire    [15:0]  cont1_trig,
input   wire    [15:0]  cont2_trig,
input   wire    [15:0]  cont3_trig,
input   wire    [15:0]  cont4_trig
    
);

// not using the IR port, so turn off both the LED, and
// disable the receive circuit to save power
assign port_ir_tx = 0;
assign port_ir_rx_disable = 1;

// bridge endianness
assign bridge_endian_little = 0;

// cart is unused, so set all level translators accordingly
// directions are 0:IN, 1:OUT
assign cart_tran_bank3 = 8'hzz;
assign cart_tran_bank3_dir = 1'b0;
assign cart_tran_bank2 = 8'hzz;
assign cart_tran_bank2_dir = 1'b0;
assign cart_tran_bank1 = 8'hzz;
assign cart_tran_bank1_dir = 1'b0;
assign cart_tran_bank0 = 4'hf;
assign cart_tran_bank0_dir = 1'b1;
assign cart_tran_pin30 = 1'b0;      // reset or cs2, we let the hw control it by itself
assign cart_tran_pin30_dir = 1'bz;
assign cart_pin30_pwroff_reset = 1'b0;  // hardware can control this
assign cart_tran_pin31 = 1'bz;      // input
assign cart_tran_pin31_dir = 1'b0;  // input

// link port is unused, set to input only to be safe
// each bit may be bidirectional in some applications
assign port_tran_so = 1'bz;
assign port_tran_so_dir = 1'b0;     // SO is output only
assign port_tran_si = 1'bz;
assign port_tran_si_dir = 1'b0;     // SI is input only
assign port_tran_sck = 1'bz;
assign port_tran_sck_dir = 1'b0;    // clock direction can change
assign port_tran_sd = 1'bz;
assign port_tran_sd_dir = 1'b0;     // SD is input and not used

// tie off the rest of the pins we are not using
assign cram0_a = 'h0;
assign cram0_dq = {16{1'bZ}};
assign cram0_clk = 0;
assign cram0_adv_n = 1;
assign cram0_cre = 0;
assign cram0_ce0_n = 1;
assign cram0_ce1_n = 1;
assign cram0_oe_n = 1;
assign cram0_we_n = 1;
assign cram0_ub_n = 1;
assign cram0_lb_n = 1;

assign cram1_a = 'h0;
assign cram1_dq = {16{1'bZ}};
assign cram1_clk = 0;
assign cram1_adv_n = 1;
assign cram1_cre = 0;
assign cram1_ce0_n = 1;
assign cram1_ce1_n = 1;
assign cram1_oe_n = 1;
assign cram1_we_n = 1;
assign cram1_ub_n = 1;
assign cram1_lb_n = 1;

assign dram_a = 'h0;
assign dram_ba = 'h0;
assign dram_dq = {16{1'bZ}};
assign dram_dqm = 'h0;
assign dram_clk = 'h0;
assign dram_cke = 'h0;
assign dram_ras_n = 'h1;
assign dram_cas_n = 'h1;
assign dram_we_n = 'h1;

assign sram_a = 'h0;
assign sram_dq = {16{1'bZ}};
assign sram_oe_n  = 1;
assign sram_we_n  = 1;
assign sram_ub_n  = 1;
assign sram_lb_n  = 1;

assign dbg_tx = 1'bZ;
assign user1 = 1'bZ;
assign aux_scl = 1'bZ;
assign vpll_feed = 1'bZ;


    wire    clk42;
    wire    clk_vid;
    wire    clk_vid_90;
    wire    pll_core_locked;
    wire    pll_core_locked_s;
    reg [23:0] ink_rgb;
    wire    [31:0]  cmd_bridge_rd_data;
    wire            reset_n;                // driven by host commands, can be used as core-wide reset

// ------------------------------------------------------------------ bridge address map
//
//   2xxxxxxx  w  track RAM, written by a "data slot read" (apf_dataslot, up to 16 KB)
//   3xxxxxxx  r  track RAM, read by a "data slot write"
//   40000000+ rw core settings, see interact.json (one 32-bit register each)
//   F8xxxxxx     framework commands (core_bridge_cmd)
//
// Bridge write data is broadcast to every device; reads are muxed.

wire [31:0] tx_rd_data;
reg  [31:0] settings_rd;

always @(*) begin
    casex(bridge_addr)
    32'h3xxxxxxx: bridge_rd_data = tx_rd_data;
    32'h40xxxxxx: bridge_rd_data = settings_rd;
    32'hF8xxxxxx: bridge_rd_data = cmd_bridge_rd_data;
    default:      bridge_rd_data = 32'h0;
    endcase
end

// settings (clk_74a domain). Defaults are the defaultval of interact.json; persisted values are written
// into these registers at boot.
reg  [1:0] set_phos    = 2'd0;      // 0 white, 1 green, 2 amber
reg        set_turbo   = 1'b0;
reg        set_sound   = 1'b1;
reg  [1:0] set_vol     = 2'd2;
reg        set_wp      = 1'b0;      // write protect all disks
reg        set_padkeys = 1'b1;      // d-pad and buttons are keys while the keyboard is closed
reg        reset_tog   = 1'b0;      // "Reset CP-300" action

wire [7:0] io_dbg;
wire [7:0] io_dbg_s;
synch_3 #(.WIDTH(8)) s_dbg (.i(io_dbg), .o(io_dbg_s), .clk(clk_74a), .rise(), .fall());

always @(posedge clk_74a) begin
    if (bridge_wr && bridge_addr[31:24] == 8'h40) begin
        case (bridge_addr[7:2])
        6'd0: set_phos    <= bridge_wr_data[1:0];
        6'd1: set_turbo   <= bridge_wr_data[0];
        6'd2: set_sound   <= bridge_wr_data[0];
        6'd3: set_vol     <= bridge_wr_data[1:0];
        6'd4: set_wp      <= bridge_wr_data[0];
        6'd5: set_padkeys <= bridge_wr_data[0];
        6'd6: reset_tog   <= ~reset_tog;
        default: ;
        endcase
    end
end

always @(*) begin
    case (bridge_addr[7:2])
    6'd0:    settings_rd = {30'd0, set_phos};
    6'd1:    settings_rd = {31'd0, set_turbo};
    6'd2:    settings_rd = {31'd0, set_sound};
    6'd3:    settings_rd = {30'd0, set_vol};
    6'd4:    settings_rd = {31'd0, set_wp};
    6'd5:    settings_rd = {31'd0, set_padkeys};
    6'd9:    settings_rd = {24'd0, io_dbg_s};         // IO controller status (read only)
    default: settings_rd = 32'h0;
    endcase
end


//
// host/target command handler
//

// bridge host commands
// synchronous to clk_74a
    wire            status_boot_done = pll_core_locked_s;
    wire            status_setup_done = pll_core_locked_s; // rising edge triggers a target command
    wire            status_running = reset_n; // we are running as soon as reset_n goes high

    wire            dataslot_requestread;
    wire    [15:0]  dataslot_requestread_id;
    wire            dataslot_requestread_ack = 1;
    wire            dataslot_requestread_ok = 1;

    wire            dataslot_requestwrite;
    wire    [15:0]  dataslot_requestwrite_id;
    wire    [31:0]  dataslot_requestwrite_size;
    wire            dataslot_requestwrite_ack = 1;
    wire            dataslot_requestwrite_ok = 1;

    wire            dataslot_update;
    wire    [15:0]  dataslot_update_id;
    wire    [31:0]  dataslot_update_size;

    wire            dataslot_allcomplete;

    wire     [31:0] rtc_epoch_seconds;
    wire     [31:0] rtc_date_bcd;
    wire     [31:0] rtc_time_bcd;
    wire            rtc_valid;

    // no save states
    wire            savestate_supported = 1'b0;
    wire    [31:0]  savestate_addr = 32'h0;
    wire    [31:0]  savestate_size = 32'h0;
    wire    [31:0]  savestate_maxloadsize = 32'h0;

    wire            savestate_start;
    wire            savestate_start_ack = 1'b0;
    wire            savestate_start_busy = 1'b0;
    wire            savestate_start_ok = 1'b0;
    wire            savestate_start_err = 1'b0;

    wire            savestate_load;
    wire            savestate_load_ack = 1'b0;
    wire            savestate_load_busy = 1'b0;
    wire            savestate_load_ok = 1'b0;
    wire            savestate_load_err = 1'b0;

    wire            osnotify_inmenu;

// bridge target commands: the data slot reads and writes of apf_dataslot
// synchronous to clk_74a

    wire            target_dataslot_read;
    wire            target_dataslot_write;

    wire            target_dataslot_ack;
    wire            target_dataslot_done;
    wire    [2:0]   target_dataslot_err;

    wire    [15:0]  target_dataslot_id;
    wire    [31:0]  target_dataslot_slotoffset;
    wire    [31:0]  target_dataslot_bridgeaddr;
    wire    [31:0]  target_dataslot_length;

    wire    [31:0]  target_buffer_param_struct; // not used
    wire    [31:0]  target_buffer_resp_struct;  // not used

// bridge data slot access
// synchronous to clk_74a

    wire    [9:0]   datatable_addr;
    wire    [31:0]  datatable_q;

core_bridge_cmd icb (

    .clk                ( clk_74a ),
    .reset_n            ( reset_n ),

    .bridge_endian_little   ( bridge_endian_little ),
    .bridge_addr            ( bridge_addr ),
    .bridge_rd              ( bridge_rd ),
    .bridge_rd_data         ( cmd_bridge_rd_data ),
    .bridge_wr              ( bridge_wr ),
    .bridge_wr_data         ( bridge_wr_data ),

    .status_boot_done       ( status_boot_done ),
    .status_setup_done      ( status_setup_done ),
    .status_running         ( status_running ),

    .dataslot_requestread       ( dataslot_requestread ),
    .dataslot_requestread_id    ( dataslot_requestread_id ),
    .dataslot_requestread_ack   ( dataslot_requestread_ack ),
    .dataslot_requestread_ok    ( dataslot_requestread_ok ),

    .dataslot_requestwrite      ( dataslot_requestwrite ),
    .dataslot_requestwrite_id   ( dataslot_requestwrite_id ),
    .dataslot_requestwrite_size ( dataslot_requestwrite_size ),
    .dataslot_requestwrite_ack  ( dataslot_requestwrite_ack ),
    .dataslot_requestwrite_ok   ( dataslot_requestwrite_ok ),

    .dataslot_update            ( dataslot_update ),
    .dataslot_update_id         ( dataslot_update_id ),
    .dataslot_update_size       ( dataslot_update_size ),

    .dataslot_allcomplete   ( dataslot_allcomplete ),

    .rtc_epoch_seconds      ( rtc_epoch_seconds ),
    .rtc_date_bcd           ( rtc_date_bcd ),
    .rtc_time_bcd           ( rtc_time_bcd ),
    .rtc_valid              ( rtc_valid ),

    .savestate_supported    ( savestate_supported ),
    .savestate_addr         ( savestate_addr ),
    .savestate_size         ( savestate_size ),
    .savestate_maxloadsize  ( savestate_maxloadsize ),

    .savestate_start        ( savestate_start ),
    .savestate_start_ack    ( savestate_start_ack ),
    .savestate_start_busy   ( savestate_start_busy ),
    .savestate_start_ok     ( savestate_start_ok ),
    .savestate_start_err    ( savestate_start_err ),

    .savestate_load         ( savestate_load ),
    .savestate_load_ack     ( savestate_load_ack ),
    .savestate_load_busy    ( savestate_load_busy ),
    .savestate_load_ok      ( savestate_load_ok ),
    .savestate_load_err     ( savestate_load_err ),

    .osnotify_inmenu        ( osnotify_inmenu ),

    .target_dataslot_read       ( target_dataslot_read ),
    .target_dataslot_write      ( target_dataslot_write ),
    .target_dataslot_getfile    ( 1'b0 ),
    .target_dataslot_openfile   ( 1'b0 ),

    .target_dataslot_ack        ( target_dataslot_ack ),
    .target_dataslot_done       ( target_dataslot_done ),
    .target_dataslot_err        ( target_dataslot_err ),

    .target_dataslot_id         ( target_dataslot_id ),
    .target_dataslot_slotoffset ( target_dataslot_slotoffset ),
    .target_dataslot_bridgeaddr ( target_dataslot_bridgeaddr ),
    .target_dataslot_length     ( target_dataslot_length ),

    .target_buffer_param_struct ( target_buffer_param_struct ),
    .target_buffer_resp_struct  ( target_buffer_resp_struct ),

    .datatable_addr         ( datatable_addr ),
    .datatable_wren         ( 1'b0 ),
    .datatable_data         ( 32'h0 ),
    .datatable_q            ( datatable_q )

);

assign target_buffer_param_struct = 32'h0;
assign target_buffer_resp_struct  = 32'h0;


// ------------------------------------------------------------------ clocks and resets
//
// clk42: the CP-300 core (the same 42 MHz as the other boards: Z80 2.0 MHz = 42 / 21)
// clk_vid: 10.5 MHz pixel clock of the core's picture (512 active pixels per line), clk_vid_90 90 degrees later

synch_3 s01(pll_core_locked, pll_core_locked_s, clk_74a);

mf_pllbase mp1 (
    .refclk         ( clk_74a ),
    .rst            ( 1'b0 ),

    .outclk_0       ( clk42 ),
    .outclk_1       ( clk_vid ),
    .outclk_2       ( clk_vid_90 ),
    .outclk_3       (  ),
    .outclk_4       (  ),

    .locked         ( pll_core_locked )
);

wire run42;                                 // the host has released the core and the PLL is locked
synch_3 s_run (.i(reset_n & pll_core_locked), .o(run42), .clk(clk42), .rise(), .fall());

wire        rst_rise, rst_fall;
wire        reset_pulse = rst_rise | rst_fall;
wire [2:0]  vol42;
wire [1:0]  phos42;
wire        turbo42, sound42, padkeys42, wp42;
synch_3 #(.WIDTH(1)) s_rst (.i(reset_tog),   .o(),           .clk(clk42), .rise(rst_rise), .fall(rst_fall));
synch_3 #(.WIDTH(2)) s_vol (.i(set_vol),     .o(vol42[1:0]), .clk(clk42), .rise(), .fall());
synch_3 #(.WIDTH(2)) s_phs (.i(set_phos),    .o(phos42),     .clk(clk42), .rise(), .fall());
synch_3 #(.WIDTH(1)) s_trb (.i(set_turbo),   .o(turbo42),    .clk(clk42), .rise(), .fall());
synch_3 #(.WIDTH(1)) s_snd (.i(set_sound),   .o(sound42),    .clk(clk42), .rise(), .fall());
synch_3 #(.WIDTH(1)) s_pdk (.i(set_padkeys), .o(padkeys42),  .clk(clk42), .rise(), .fall());
synch_3 #(.WIDTH(1)) s_wp  (.i(set_wp),      .o(wp42),       .clk(clk42), .rise(), .fall());
assign vol42[2] = 1'b0;

// "Reset CP-300" from the Core Settings menu: the core is held in reset for 1 ms
reg [15:0] rst_cnt = 16'd0;
always @(posedge clk42) begin
    if (reset_pulse) rst_cnt <= 16'd42000;
    else if (rst_cnt != 16'd0) rst_cnt <= rst_cnt - 16'd1;
end

// controller 1, into the core clock domain
wire [15:0] pad;
synch_3 #(.WIDTH(16)) s_pad (.i(cont1_key[15:0]), .o(pad), .clk(clk42), .rise(), .fall());


// ------------------------------------------------------------------ the CP-300
//
// Z80 RAM (4000-FFFF) is a 64 KB block RAM; the access takes one clock, far less than a Z80 T state
// (21 clocks), so the core never needs to wait.

wire [15:0] ext_addr;
wire        ext_rd, ext_wr;
wire  [7:0] ext_din;
reg   [7:0] ext_dout;
reg   [7:0] ram64 [0:65535];

always @(posedge clk42) begin
    if (ext_wr) ram64[ext_addr] <= ext_din;
    ext_dout <= ram64[ext_addr];
end

wire        vid_screen, vid_ink, vid_pxen;
wire        hs_n, vs_n;
wire  [8:0] audio;

wire  [7:0] fdc_track, fdc_trkreg, fdc_sector;
wire        fdc_rd, fdc_wr, fdc_ra, fdc_dam, fdc_ack, fdc_buff_wr, fdc_side;
wire        fdc_res_found, fdc_res_crc, fdc_res_dam;
wire  [8:0] fdc_buff_addr;
wire  [7:0] fdc_buff_dout, fdc_buff_din;
wire  [1:0] fdc_drive;
wire  [3:0] drv_ready, drv_wp;

wire [63:0] keys;                           // osd_kbd: the buttons as CP-300 keys
wire        io_hold;                        // the IO controller holds the CP-300 in reset until the disks are mounted
wire        core_reset = ~run42 | io_hold | (rst_cnt != 16'd0);

// SDRAM and exp port of the HT1080Z core: unused here
wire        sd_nCS, sd_nWE, sd_nCAS, sd_nRAS, sd_dqmh, sd_dqml, sd_cke;
wire [12:0] sd_a;
wire  [1:0] sd_ba;
wire [15:0] sd_dq;
wire [15:0] exp_addr;
wire  [7:0] exp_dout;
wire        exp_in, exp_out;

ht1080z_ext cp300 (
    .clk42m (clk42),
    .pllLocked(run42),
    .reset(core_reset),
    .led(),
    .ntsc(1'b1),                // 60 Hz, as the PAL-M CP-300
    .turbo(turbo42),
    .ext_keys(keys),
    .cass_in(1'b0),
    .cass_out(),

    .fdc_svc_rd(fdc_rd),
    .fdc_svc_wr(fdc_wr),
    .fdc_svc_ra(fdc_ra),
    .fdc_svc_track(fdc_track),
    .fdc_svc_trkreg(fdc_trkreg),
    .fdc_svc_sector(fdc_sector),
    .fdc_svc_dam(fdc_dam),
    .fdc_svc_ack(fdc_ack),
    .fdc_res_found(fdc_res_found),
    .fdc_res_crc(fdc_res_crc),
    .fdc_res_dam(fdc_res_dam),
    .fdc_buff_addr(fdc_buff_addr),
    .fdc_buff_dout(fdc_buff_dout),
    .fdc_buff_din(fdc_buff_din),
    .fdc_buff_wr(fdc_buff_wr),
    .fdc_drive(fdc_drive),
    .fdc_side(fdc_side),
    .drv_ready(drv_ready),
    .drv_wp(drv_wp),

    .ps2clk(1'b1),
    .ps2dat(1'b1),

    .ht_rgb(),
    .hs(hs_n),
    .vs(vs_n),
    .hb(),
    .vb(),
    .vid_screen(vid_screen),
    .vid_ink(vid_ink),
    .vid_pxen(vid_pxen),
    .vid_ink_rgb(),
    .vid_paper_rgb(),
    .vid_border_rgb(),

    .audiomix(audio),

    .dn_go(1'b0),
    .dn_wr(1'b0),
    .dn_addr(25'd0),
    .dn_data(8'd0),
    .dn_idx(5'd0),

    .exp_addr(exp_addr),
    .exp_din(8'h00),
    .exp_dout(exp_dout),
    .exp_in(exp_in),
    .exp_out(exp_out),
    .exp_oe(1'b0),

    .ext_ram_addr(ext_addr),
    .ext_ram_rd(ext_rd),
    .ext_ram_wr(ext_wr),
    .ext_ram_din(ext_din),
    .ext_ram_dout(ext_dout),
    .ext_ram_wait(1'b0),

    .SDRAM_nCS(sd_nCS),
    .SDRAM_DQ(sd_dq),
    .SDRAM_A(sd_a),
    .SDRAM_DQMH(sd_dqmh),
    .SDRAM_DQML(sd_dqml),
    .SDRAM_nWE(sd_nWE),
    .SDRAM_nCAS(sd_nCAS),
    .SDRAM_nRAS(sd_nRAS),
    .SDRAM_BA(sd_ba),
    .SDRAM_CKE(sd_cke)
);


// ------------------------------------------------------------------ IO controller and data slots
//
// The helper Z80 serves the floppy controller's sector requests out of the DMK images in data
// slots 0-3 (drives 0-3), see apf_dataslot.vhd and firmware/pocket.

wire        slot_req_tog, slot_req_wr, slot_busy, slot_err, trk_we, scan_valid;
wire  [1:0] slot_num;
wire [31:0] slot_offset;
wire [15:0] slot_len;
wire [13:0] slot_boff, trk_addr;
wire  [7:0] trk_din, trk_dout;
wire [31:0] slot_size;
wire  [3:0] slot_present, slot_changed, slot_chg_clr;

io_ctrl_pocket io_ctrl (
    .clk(clk42),
    .reset(~run42),
    .core_rst(io_hold),
    .dbg(io_dbg),

    .fdc_rd(fdc_rd),
    .fdc_wr(fdc_wr),
    .fdc_ra(fdc_ra),
    .fdc_track(fdc_track),
    .fdc_trkreg(fdc_trkreg),
    .fdc_sector(fdc_sector),
    .fdc_dam(fdc_dam),
    .fdc_res_found(fdc_res_found),
    .fdc_res_crc(fdc_res_crc),
    .fdc_res_dam(fdc_res_dam),
    .fdc_drive(fdc_drive),
    .fdc_side(fdc_side),
    .fdc_ack(fdc_ack),
    .fdc_buff_addr(fdc_buff_addr),
    .fdc_buff_dout(fdc_buff_dout),
    .fdc_buff_wr(fdc_buff_wr),
    .fdc_buff_din(fdc_buff_din),
    .drv_ready(drv_ready),
    .drv_wp(drv_wp),

    .slot_req_tog(slot_req_tog),
    .slot_req_wr(slot_req_wr),
    .slot_num(slot_num),
    .slot_offset(slot_offset),
    .slot_busy(slot_busy),
    .slot_err(slot_err),
    .slot_len(slot_len),
    .slot_boff(slot_boff),
    .slot_size(slot_size),
    .trk_addr(trk_addr),
    .trk_we(trk_we),
    .trk_din(trk_din),
    .trk_dout(trk_dout),
    .slot_present(slot_present),
    .slot_changed(slot_changed),
    .slot_chg_clr(slot_chg_clr),
    .scan_valid(scan_valid),
    .opt_wp(wp42)
);

apf_dataslot slots (
    .clk_74a(clk_74a),
    .reset_n_74(reset_n),
    .clk(clk42),
    .reset(~run42),

    .bridge_wr(bridge_wr),
    .bridge_addr(bridge_addr),
    .bridge_wr_data(bridge_wr_data),
    .tx_rd_data(tx_rd_data),

    .dataslot_update(dataslot_update),
    .dataslot_update_id(dataslot_update_id),

    .target_dataslot_read(target_dataslot_read),
    .target_dataslot_write(target_dataslot_write),
    .target_dataslot_ack(target_dataslot_ack),
    .target_dataslot_done(target_dataslot_done),
    .target_dataslot_err(target_dataslot_err),
    .target_dataslot_id(target_dataslot_id),
    .target_dataslot_slotoffset(target_dataslot_slotoffset),
    .target_dataslot_bridgeaddr(target_dataslot_bridgeaddr),
    .target_dataslot_length(target_dataslot_length),

    .datatable_addr(datatable_addr),
    .datatable_q(datatable_q),

    .req_tog(slot_req_tog),
    .req_wr(slot_req_wr),
    .req_slot(slot_num),
    .req_offset(slot_offset),
    .busy(slot_busy),
    .err(slot_err),
    .req_len(slot_len),
    .req_boff(slot_boff),
    .size_sel(slot_size),
    .trk_addr(trk_addr),
    .trk_we(trk_we),
    .trk_din(trk_din),
    .trk_dout(trk_dout),
    .present(slot_present),
    .changed(slot_changed),
    .chg_clr(slot_chg_clr),
    .scan_valid(scan_valid)
);


// ------------------------------------------------------------------ video
//
// The core's picture is 512 x 192 pixels at 10.5 MHz (vid_pxen is that pixel clock as an enable of
// clk42). Everything up to the output registers runs on clk42 with vid_pxen; the framework gets
// the 10.5 MHz clk_vid, which samples the held values.
//
// pocket_video counts the pixels, osd_kbd colours the keyboard area, and the registers below hand
// the held values to clk_vid.

wire  [8:0] a_x;
wire  [7:0] a_y;
wire [23:0] o_rgb;
wire        o_de, o_hs, o_vs;
wire        ovl_on;
wire [23:0] ovl_rgb;
wire        kbd_open;

always @(*) begin
    case (phos42)
    2'd1:    ink_rgb = 24'h40FF60;     // green phosphor
    2'd2:    ink_rgb = 24'hFFB000;     // amber
    default: ink_rgb = 24'hE8E8E8;     // white
    endcase
end

pocket_video pvideo (
    .clk(clk42),
    .pxen(vid_pxen),
    .screen(vid_screen),
    .ink(vid_ink),
    .hs_n(hs_n),
    .vs_n(vs_n),
    .ovl_on(ovl_on),
    .ovl_rgb(ovl_rgb),
    .ink_rgb(ink_rgb),
    .a_x(a_x),
    .a_y(a_y),
    .o_rgb(o_rgb),
    .o_de(o_de),
    .o_hs(o_hs),
    .o_vs(o_vs)
);

osd_kbd kbd (
    .clk(clk42),
    .reset(~run42),
    .pad(pad),
    .pad_keys_en(padkeys42),
    .px(a_x),
    .py(a_y),
    .ovl_on(ovl_on),
    .ovl_rgb(ovl_rgb),
    .keys(keys),
    .open_o(kbd_open)
);

reg [23:0] vid_rgb_q;
reg        vid_de_q, vid_hs_q, vid_vs_q;
always @(posedge clk_vid) begin
    vid_rgb_q <= o_rgb;
    vid_de_q  <= o_de;
    vid_hs_q  <= o_hs;
    vid_vs_q  <= o_vs;
end

assign video_rgb_clock    = clk_vid;
assign video_rgb_clock_90 = clk_vid_90;
assign video_rgb          = vid_rgb_q;
assign video_de           = vid_de_q;
assign video_skip         = 1'b0;
assign video_vs           = vid_vs_q;
assign video_hs           = vid_hs_q;


// ------------------------------------------------------------------ audio
//
// The core's audio is the cassette port speaker bit (port FF, three levels); it is centred, scaled
// by the volume setting and sent as mono 16 bit I2S at 48 kHz (sound_i2s does the clock crossing).

wire signed [9:0]  a_c = {1'b0, audio} - 10'sd16;          // 0x10 is the idle level: no DC
wire signed [15:0] a_scaled = a_c <<< (6 + vol42[1:0]);    // +-16 << 6..9 = +-1024 .. +-8192 (volume 0..3)
wire signed [15:0] a_out    = sound42 ? a_scaled : 16'sd0;

sound_i2s #(.CHANNEL_WIDTH(16), .SIGNED_INPUT(1)) i2s (
    .clk_74a    ( clk_74a ),
    .clk_audio  ( clk42 ),
    .audio_l    ( a_out ),
    .audio_r    ( a_out ),
    .audio_mclk ( audio_mclk ),
    .audio_lrck ( audio_lrck ),
    .audio_dac  ( audio_dac )
);

endmodule
