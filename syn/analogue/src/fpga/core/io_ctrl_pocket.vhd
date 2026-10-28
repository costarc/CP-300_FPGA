-- CP-300 FPGA, Analogue Pocket: IO controller.
--
-- The same helper Z80 as rtl/io/io_ctrl.vhd (T80s + firmware ROM + 8 KB RAM + the floppy sector
-- window), but its disk images are not on an SD card of its own: they are APF data slots, read and
-- written 512 bytes at a time through apf_dataslot. There is no SPI, no PS/2 and no OSD here; the
-- menu is the Pocket's own (data slots + interact.json) and the on-screen keyboard is plain RTL.
--
--   0000-3FFF  firmware ROM (io_fw_pkg, built from firmware/pocket)
--   4000-5FFF  RAM 8 KB
--   8000-BFFF  track RAM 16 KB (in apf_dataslot): the data slot commands move whole tracks into and out of it
--
-- I/O ports (low address byte):
--   04  w: b1 hold the CP-300 in reset (set after reset, the firmware clears it once it has mounted)
--   07  r: A6 (identification)
--   08  w: debug / status byte, shown by the core's interact menu
--   10  r: floppy controller request: b0 read sector, b1 write sector, b2 read address, b3 side,
--       b5:4 drive, b6 write a deleted data mark
--   11  r: head position (track)   12  r: track register   17  r: sector number
--   13  w: b0 = acknowledge: the buffer pointer goes to 0 and the buffer port is live while set
--   14  rw: sector buffer data port, auto-increment
--   15  w: drive flags: b1:0 drive, b2 disk present, b3 write protected
--   16  w: result of the request: b0 sector found, b1 CRC error, b2 deleted data mark
--   Data slot access (up to 16 KB of an image file in one command, into / out of the track RAM):
--   20-23 w: byte offset in the slot file, least significant byte first (a multiple of 512)
--   24  w: slot (drive) number
--   2C,2D w: number of bytes, low and high (at most 16384)
--   2E,2F w: where in the track RAM (offset from 8000h), low and high
--   25  w: 1 = read the file into the track RAM, 2 = write the track RAM to the file
--       r: b0 busy, b1 error of the last command
--   30-33 r: size of the file in the slot of port 24, least significant byte first (read twice
--       and compare: it comes from another clock domain)
--   29  r: b3:0 slot has a file
--   2A  r: b3:0 the file of the slot was replaced; w: b3:0 clear those bits
--   2B  r: b0 write protect all disks (core setting), b7 the slot table has been scanned once

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.io_fw_pkg.all;

entity io_ctrl_pocket is
  generic (
    CPU_HALF : boolean := true     -- the helper CPU gets every second clock
  );
  port (
    clk       : in  std_logic;                       -- 42 MHz
    reset     : in  std_logic;                       -- active high

    core_rst  : out std_logic;                       -- hold the CP-300 in reset
    dbg       : out std_logic_vector(7 downto 0);

    -- floppy controller sector service (as io_ctrl)
    fdc_rd      : in  std_logic;
    fdc_wr      : in  std_logic;
    fdc_ra      : in  std_logic;
    fdc_track   : in  std_logic_vector(7 downto 0);
    fdc_trkreg  : in  std_logic_vector(7 downto 0);
    fdc_sector  : in  std_logic_vector(7 downto 0);
    fdc_dam     : in  std_logic;
    fdc_res_found : out std_logic;
    fdc_res_crc   : out std_logic;
    fdc_res_dam   : out std_logic;
    fdc_drive   : in  std_logic_vector(1 downto 0);
    fdc_side    : in  std_logic;
    fdc_ack     : out std_logic;
    fdc_buff_addr : out std_logic_vector(8 downto 0);
    fdc_buff_dout : out std_logic_vector(7 downto 0);
    fdc_buff_wr   : out std_logic;
    fdc_buff_din  : in  std_logic_vector(7 downto 0);
    drv_ready   : out std_logic_vector(3 downto 0);
    drv_wp      : out std_logic_vector(3 downto 0);

    -- data slot access (apf_dataslot)
    slot_req_tog : out std_logic;
    slot_req_wr  : out std_logic;
    slot_num     : out std_logic_vector(1 downto 0);
    slot_offset  : out std_logic_vector(31 downto 0);
    slot_len     : out std_logic_vector(15 downto 0);
    slot_boff    : out std_logic_vector(13 downto 0);
    slot_busy    : in  std_logic;
    slot_err     : in  std_logic;
    slot_size    : in  std_logic_vector(31 downto 0);   -- size of the file in slot_num
    trk_addr     : out std_logic_vector(13 downto 0);   -- the track RAM (apf_dataslot)
    trk_we       : out std_logic;
    trk_din      : out std_logic_vector(7 downto 0);
    trk_dout     : in  std_logic_vector(7 downto 0);
    slot_present : in  std_logic_vector(3 downto 0);
    slot_changed : in  std_logic_vector(3 downto 0);
    slot_chg_clr : out std_logic_vector(3 downto 0);
    scan_valid   : in  std_logic;
    opt_wp       : in  std_logic;
    opt_eject    : in  std_logic := '0'
  );
end io_ctrl_pocket;

architecture rtl of io_ctrl_pocket is

  type ram_t is array (0 to 8191) of std_logic_vector(7 downto 0);

  signal cen    : std_logic := '0';

  signal a      : std_logic_vector(15 downto 0);
  signal di, cpu_do: std_logic_vector(7 downto 0);
  signal mreq_n, iorq_n, rd_n, wr_n, m1_n : std_logic;

  signal rom_do, ram_do : std_logic_vector(7 downto 0) := (others => '0');
  signal ram     : ram_t := (others => (others => '0'));
  signal rom_sel, ram_sel : std_logic;
  signal iord, iowr, iord_q, iowr_q, rdp, wrp : std_logic;
  signal ack_r, bw_r : std_logic := '0';
  signal baddr : unsigned(8 downto 0) := (others => '0');
  signal bdout : std_logic_vector(7 downto 0) := (others => '0');
  signal dr_ready, dr_wp : std_logic_vector(3 downto 0) := (others => '0');
  signal res_r : std_logic_vector(2 downto 0) := (others => '0');
  signal rd_port : std_logic_vector(7 downto 0) := (others => '0');
  signal port_a  : std_logic_vector(7 downto 0);

  signal dbg_r   : std_logic_vector(7 downto 0) := (others => '0');
  signal hold_r  : std_logic := '1';

  -- data slot access
  signal off_r   : std_logic_vector(31 downto 0) := (others => '0');
  signal slot_r  : std_logic_vector(1 downto 0) := (others => '0');
  signal tog_r, wr_r : std_logic := '0';
  signal len_r   : std_logic_vector(15 downto 0) := (others => '0');
  signal boff_r  : std_logic_vector(13 downto 0) := (others => '0');
  signal err_r   : std_logic := '0';
  signal trk_sel : std_logic;
  signal trk_we_r : std_logic := '0';
  signal trk_wa  : std_logic_vector(13 downto 0) := (others => '0');
  signal trk_wd  : std_logic_vector(7 downto 0) := (others => '0');
  signal size_r  : std_logic_vector(31 downto 0) := (others => '0');
  signal chg_clr_r : std_logic_vector(3 downto 0) := (others => '0');
  signal busy_i  : std_logic;

begin

  process(clk)
  begin
    if rising_edge(clk) then
      if cen = '1' then
        iord_q <= iord;
        iowr_q <= iowr;
        if iord = '1' then rd_port <= port_a; end if;
      end if;
    end if;
  end process;

  gen_full : if not CPU_HALF generate
    cen <= '1';
  end generate;
  gen_half : if CPU_HALF generate
    process(clk)
    begin
      if rising_edge(clk) then
        cen <= not cen;
      end if;
    end process;
  end generate;

  cpu : entity work.T80s
    port map (
      RESET_n => not reset,
      CLK     => clk,
      CEN     => cen,
      WAIT_n  => '1',
      INT_n   => '1',
      NMI_n   => '1',
      BUSRQ_n => '1',
      M1_n    => m1_n,
      MREQ_n  => mreq_n,
      IORQ_n  => iorq_n,
      RD_n    => rd_n,
      WR_n    => wr_n,
      RFSH_n  => open,
      HALT_n  => open,
      BUSAK_n => open,
      A       => a,
      DI      => di,
      DO      => cpu_do
    );

  port_a  <= a(7 downto 0);
  iord    <= '1' when iorq_n = '0' and rd_n = '0' and m1_n = '1' else '0';
  iowr    <= '1' when iorq_n = '0' and wr_n = '0' else '0';
  -- side effects of an IN happen once, after the CPU has taken the data (end of the bus cycle)
  wrp     <= iowr and not iowr_q;
  rdp     <= iord_q and not iord;
  rom_sel <= '1' when a(15 downto 14) = "00" else '0';
  trk_sel <= '1' when a(15 downto 14) = "10" else '0';
  ram_sel <= '1' when a(15 downto 13) = "010" else '0';

  -- memories
  process(clk)
  begin
    if rising_edge(clk) then
      rom_do <= FW_ROM(to_integer(unsigned(a(13 downto 0))));
      ram_do <= ram(to_integer(unsigned(a(12 downto 0))));
      if cen = '1' and mreq_n = '0' and wr_n = '0' and ram_sel = '1' then
        ram(to_integer(unsigned(a(12 downto 0)))) <= cpu_do;
      end if;
    end if;
  end process;

  -- floppy controller sector buffer window, drive flags
  process(clk)
    variable d : integer;
  begin
    if rising_edge(clk) then
      bw_r <= '0';
      if reset = '1' then
        ack_r <= '0'; baddr <= (others => '0');
        dr_ready <= (others => '0'); dr_wp <= (others => '0'); res_r <= (others => '0');
      else
        if bw_r = '1' then baddr <= baddr + 1; end if;
        if cen = '1' and rdp = '1' and rd_port = x"14" then baddr <= baddr + 1; end if;
        if cen = '1' and wrp = '1' then
          case port_a is
            when x"13" =>
              ack_r <= cpu_do(0);
              if cpu_do(0) = '1' then baddr <= (others => '0'); end if;
            when x"14" =>
              bdout <= cpu_do; bw_r <= '1';
            when x"15" =>
              d := to_integer(unsigned(cpu_do(1 downto 0)));
              dr_ready(d) <= cpu_do(2); dr_wp(d) <= cpu_do(3);
            when x"16" =>
              res_r <= cpu_do(2 downto 0);
            when others => null;
          end case;
        end if;
      end if;
    end if;
  end process;
  fdc_ack <= ack_r;
  fdc_buff_addr <= std_logic_vector(baddr);
  fdc_buff_dout <= bdout;
  fdc_buff_wr <= bw_r;
  drv_ready <= dr_ready; drv_wp <= dr_wp;
  fdc_res_found <= res_r(0); fdc_res_crc <= res_r(1); fdc_res_dam <= res_r(2);

  -- data slot commands and buffers
  -- slot_busy is the request toggle against the synchronised completion toggle, so it rises with
  -- the write to port 25 and falls when the 74 MHz side has finished.
  busy_i <= slot_busy;
  process(clk)
  begin
    if rising_edge(clk) then
      chg_clr_r <= (others => '0');
      size_r <= slot_size;
      if reset = '1' then
        tog_r <= '0'; err_r <= '0';
      else
        if cen = '1' and wrp = '1' then
          case port_a is
            when x"20" => off_r(7 downto 0)   <= cpu_do;
            when x"21" => off_r(15 downto 8)  <= cpu_do;
            when x"22" => off_r(23 downto 16) <= cpu_do;
            when x"23" => off_r(31 downto 24) <= cpu_do;
            when x"24" => slot_r <= cpu_do(1 downto 0);
            when x"25" =>
              if cpu_do(1 downto 0) /= "00" then
                wr_r <= cpu_do(1);
                tog_r <= not tog_r;
              end if;
            when x"2A" => chg_clr_r <= cpu_do(3 downto 0);
            when x"2C" => len_r(7 downto 0)  <= cpu_do;
            when x"2D" => len_r(15 downto 8) <= cpu_do;
            when x"2E" => boff_r(7 downto 0) <= cpu_do;
            when x"2F" => boff_r(13 downto 8) <= cpu_do(5 downto 0);
            when others => null;
          end case;
        end if;
        -- the error bit of the last command: sampled when busy drops
        if busy_i = '0' then err_r <= slot_err; end if;
      end if;
    end if;
  end process;
  slot_req_tog <= tog_r;
  slot_req_wr  <= wr_r;
  slot_num     <= slot_r;
  slot_offset  <= off_r;
  slot_len     <= len_r;
  slot_boff    <= boff_r;
  slot_chg_clr <= chg_clr_r;

  -- track RAM: a write is registered and goes in one clock later (nothing reads it that soon)
  process(clk)
  begin
    if rising_edge(clk) then
      trk_we_r <= '0';
      if cen = '1' and mreq_n = '0' and wr_n = '0' and trk_sel = '1' then
        trk_we_r <= '1';
        trk_wa <= a(13 downto 0);
        trk_wd <= cpu_do;
      end if;
    end if;
  end process;
  trk_we   <= trk_we_r;
  trk_addr <= trk_wa when trk_we_r = '1' else a(13 downto 0);
  trk_din  <= trk_wd;

  -- control register and debug byte
  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        hold_r <= '1';                   -- the CP-300 waits in reset until the firmware has mounted the disks
      elsif cen = '1' and iowr = '1' then
        if port_a = x"04" then hold_r <= cpu_do(1); end if;
        if port_a = x"08" then dbg_r <= cpu_do; end if;
      end if;
    end if;
  end process;
  dbg <= dbg_r;
  core_rst <= hold_r;

  di <= rom_do when mreq_n = '0' and rom_sel = '1' else
        ram_do when mreq_n = '0' and ram_sel = '1' else
        trk_dout when mreq_n = '0' and trk_sel = '1' else
        x"FF"  when mreq_n = '0' else
        x"A6"   when port_a = x"07" else
        '0' & fdc_dam & fdc_drive & fdc_side & fdc_ra & fdc_wr & fdc_rd when port_a = x"10" else
        fdc_track when port_a = x"11" else
        fdc_trkreg when port_a = x"12" else
        fdc_sector when port_a = x"17" else
        fdc_buff_din when port_a = x"14" else
        "000000" & err_r & busy_i when port_a = x"25" else
        size_r(7 downto 0)   when port_a = x"30" else
        size_r(15 downto 8)  when port_a = x"31" else
        size_r(23 downto 16) when port_a = x"32" else
        size_r(31 downto 24) when port_a = x"33" else
        "0000" & slot_present when port_a = x"29" else
        "0000" & slot_changed when port_a = x"2A" else
        scan_valid & "00000" & opt_eject & "0" & opt_wp when port_a = x"2B" else
        x"00";

end rtl;
