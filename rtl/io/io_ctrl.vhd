-- CP-300 FPGA: IO controller.
--
-- A second Z80 (T80s) that replaces the MiST ARM: it talks SPI to the SD card,
-- draws the on-screen menu through the MiST OSD, reads the PS/2 keyboard while
-- the menu is open, and (later phases) serves sectors to the floppy controller.
--
--   0000-3FFF  firmware ROM (io_fw_pkg, built from firmware/)
--   4000-5FFF  RAM 8 KB
--
-- I/O ports (low address byte):
--   00  r: last SPI byte received   w: send a byte (starts an 8 clock transfer)
--   01  r: b0 busy, b1 SD write protect
--       w: b0 SD chip select, b1 OSD select (SS3), b2 slow clock (card init)
--   02  r: b0 PS/2 byte available   w: flush the PS/2 FIFO
--   03  r: pop one raw PS/2 byte
--   04  w: b0 menu open (core keyboard muted), b1 hold the core in reset (set after reset)
--   05  r: next pixel column (0..7) of the glyph selected through port 06, as an OSD byte
--       (bit 0 = top line, the format the MiST OSD wants); the 8 columns follow each other
--   06  w: select a character generator glyph (code); column counter back to 0
--   07  r: A5 (identification)
--   08  w: debug byte (reported in simulation)
--   10  r: floppy controller request: b0 read sector, b1 write sector, b2 read address, b3 side,
--       b5:4 drive, b6 write a deleted data mark
--   11  r: head position (track) of the drive    12  r: track register    17  r: sector number
--   13  w: b0 = acknowledge: the buffer pointer goes to 0 and the buffer port is live while set
--   14  rw: sector buffer data port, auto-increment (write fills it for a read request, read
--       empties it for a write request)
--   15  w: drive flags: b1:0 drive, b2 disk present, b3 write protected
--   18  w: start a ROM load: b0 = 0 system ROM (16 KB), 1 character generator (2 KB); the pointer goes to 0
--   19  w: next byte of the ROM image (four bytes make a word for the core's ROM RAM, rl_*; a
--       character generator load also fills the OSD font)
--   16  w: result of the request, read by the controller when the acknowledge drops:
--       b0 sector found, b1 CRC error, b2 deleted data mark

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.io_fw_pkg.all;

entity io_ctrl is
  generic (
    CPU_HALF : boolean := false   -- true: the helper CPU gets every second clock (slower FPGAs)
  );
  port (
    clk       : in  std_logic;                       -- 42 MHz
    reset     : in  std_logic;                       -- active high

    sd_cs_n   : out std_logic;
    spi_sck   : out std_logic;                       -- shared by the SD card and the OSD
    spi_mosi  : out std_logic;
    sd_miso   : in  std_logic;
    sd_wp_n   : in  std_logic;
    osd_ss3   : out std_logic;                       -- MiST OSD SS3, active low

    ps2clk    : in  std_logic;
    ps2dat    : in  std_logic;
    ext_keys  : in  std_logic_vector(63 downto 0);   -- original keyboard matrix (8 * row + column), menu keys

    -- ROM loader: the core's ROM RAMs are filled from the SD card (see cp300_rom, videoctrl)
    rl_we     : out std_logic;
    rl_waddr  : out std_logic_vector(12 downto 0);
    rl_wdata  : out std_logic_vector(31 downto 0);

    menu_open : out std_logic;
    core_rst  : out std_logic;
    dbg       : out std_logic_vector(7 downto 0);   -- port 08, shown on the green LEDs

    -- floppy controller sector service
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
    drv_wp      : out std_logic_vector(3 downto 0)
  );
end io_ctrl;

architecture rtl of io_ctrl is

  type ram_t is array (0 to 8191) of std_logic_vector(7 downto 0);
  type fifo_t is array (0 to 15) of std_logic_vector(7 downto 0);

  signal cen    : std_logic := '0';

  signal a      : std_logic_vector(15 downto 0);
  signal di, cpu_do: std_logic_vector(7 downto 0);
  signal mreq_n, iorq_n, rd_n, wr_n, m1_n : std_logic;

  signal kbd_avail : std_logic;
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

  -- SPI master
  signal spi_sr, spi_rx : std_logic_vector(7 downto 0) := (others => '0');
  signal spi_busy  : std_logic := '0';
  signal spi_sck_r : std_logic := '0';
  signal spi_cnt   : unsigned(3 downto 0) := (others => '0');
  signal spi_div   : unsigned(5 downto 0) := (others => '0');
  signal spi_ctl   : std_logic_vector(2 downto 0) := (others => '0');
  signal miso_r    : std_logic := '1';

  -- PS/2
  signal ps2_d   : std_logic_vector(7 downto 0);
  signal ps2_f, ps2_f_r : std_logic := '0';
  signal fifo    : fifo_t := (others => (others => '0'));
  signal fifo_wp, fifo_rp : unsigned(3 downto 0) := (others => '0');
  signal fifo_do : std_logic_vector(7 downto 0);

  -- menu keys from the original keyboard, turned into the PS/2 codes the firmware knows
  signal ek_prev  : std_logic_vector(63 downto 0) := (others => '0');
  signal chord_prev : std_logic := '0';
  signal ev_b0, ev_b1 : std_logic_vector(7 downto 0) := (others => '0');
  signal ev_cnt   : integer range 0 to 2 := 0;

  signal dbg_r   : std_logic_vector(7 downto 0) := (others => '0');
  signal ctl4    : std_logic_vector(1 downto 0) := (others => '0');

  -- character generator
  signal glyph   : unsigned(7 downto 0) := (others => '0');
  signal gcol    : unsigned(2 downto 0) := (others => '0');
  signal gdata   : std_logic_vector(7 downto 0) := (others => '0');
  signal fcnt    : unsigned(3 downto 0) := to_unsigned(10, 4);
  type grows_t is array (0 to 7) of std_logic_vector(7 downto 0);
  signal grows   : grows_t := (others => (others => '0'));
  signal gcolbyte : std_logic_vector(7 downto 0);
  type chram_t is array (0 to 2047) of std_logic_vector(7 downto 0);
  signal chram   : chram_t := (others => (others => '0'));

  -- ROM loader
  signal rl_tgt  : std_logic := '0';
  signal rl_ptr  : unsigned(11 downto 0) := (others => '0');
  signal rl_cnt  : unsigned(1 downto 0) := (others => '0');
  signal rl_sh   : std_logic_vector(23 downto 0) := (others => '0');
  signal rl_bidx : unsigned(10 downto 0) := (others => '0');
  signal rl_we_r : std_logic := '0';
  signal rl_wa_r : std_logic_vector(12 downto 0) := (others => '0');
  signal rl_wd_r : std_logic_vector(31 downto 0) := (others => '0');

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

  -- The CPU runs at the full 42 MHz: the design meets timing at that clock anyway (the enable only
  -- gates registers, it adds no slower paths). Memory is synchronous, one clock of latency.
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

  -- character generator: a glyph select loads its 8 scan lines, the columns are read back
  process(clk)
  begin
    if rising_edge(clk) then
      gdata <= chram(to_integer(glyph & fcnt(2 downto 0)));
      if fcnt < 10 then
        -- gdata is the line fetched one clock ago, i.e. line fcnt - 1
        if fcnt >= 1 and fcnt <= 8 then grows(to_integer(fcnt) - 1) <= gdata; end if;
        fcnt <= fcnt + 1;
      end if;
      if cen = '1' and iowr = '1' and port_a = x"06" then
        glyph <= unsigned(cpu_do); fcnt <= (others => '0'); gcol <= (others => '0');
      end if;
      if cen = '1' and rdp = '1' and rd_port = x"05" then gcol <= gcol + 1; end if;
    end if;
  end process;

  colbits : for y in 0 to 7 generate
    gcolbyte(y) <= grows(y)(7 - to_integer(gcol));
  end generate;

  -- ROM loader: bytes pushed to port 19 are packed into words (first byte = bits 31:24)
  process(clk)
  begin
    if rising_edge(clk) then
      rl_we_r <= '0';
      if cen = '1' and wrp = '1' then
        if port_a = x"18" then
          rl_tgt <= cpu_do(0); rl_ptr <= (others => '0'); rl_cnt <= (others => '0'); rl_bidx <= (others => '0');
        elsif port_a = x"19" then
          rl_sh <= rl_sh(15 downto 0) & cpu_do;
          rl_cnt <= rl_cnt + 1;
          if rl_tgt = '1' then
            chram(to_integer(rl_bidx)) <= cpu_do;
            rl_bidx <= rl_bidx + 1;
          end if;
          if rl_cnt = 3 then
            rl_we_r <= '1';
            rl_wa_r <= rl_tgt & std_logic_vector(rl_ptr);
            rl_wd_r <= rl_sh & cpu_do;
            rl_ptr <= rl_ptr + 1;
          end if;
        end if;
      end if;
    end if;
  end process;
  rl_we <= rl_we_r; rl_waddr <= rl_wa_r; rl_wdata <= rl_wd_r;

  -- SPI master, mode 0, MSB first
  process(clk)
    variable term : unsigned(5 downto 0);
  begin
    if rising_edge(clk) then
      miso_r <= sd_miso;
      if spi_ctl(2) = '1' then term := to_unsigned(63, 6); else term := to_unsigned(2, 6); end if;
      if reset = '1' then
        spi_busy <= '0'; spi_sck_r <= '0'; spi_ctl <= (others => '0');
      else
        if cen = '1' and iowr = '1' and port_a = x"01" then
          spi_ctl <= cpu_do(2 downto 0);
        end if;
        if cen = '1' and iowr = '1' and port_a = x"00" then
          spi_sr <= cpu_do; spi_busy <= '1'; spi_cnt <= (others => '0');
          spi_div <= (others => '0'); spi_sck_r <= '0';
        elsif spi_busy = '1' then
          if spi_div = term then
            spi_div <= (others => '0');
            if spi_sck_r = '0' then
              spi_sck_r <= '1';
              spi_rx <= spi_rx(6 downto 0) & miso_r;
              spi_cnt <= spi_cnt + 1;
            else
              spi_sck_r <= '0';
              if spi_cnt = 8 then spi_busy <= '0';
              else spi_sr <= spi_sr(6 downto 0) & '1'; end if;
            end if;
          else
            spi_div <= spi_div + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  spi_sck  <= spi_sck_r;
  spi_mosi <= spi_sr(7);
  sd_cs_n  <= not spi_ctl(0);
  osd_ss3  <= not spi_ctl(1);

  -- PS/2 keyboard reader and FIFO
  ps2 : entity work.ps2reader
    port map (mclk => clk, PS2C => ps2clk, PS2D => ps2dat, rst => reset,
              Ps2Dout => ps2_d, fRd => ps2_f);

  fifo_do <= fifo(to_integer(fifo_rp));


  -- SHIFT + BREAK opens and closes the menu (F12, scan code 07). While the menu is open the arrow
  -- keys, ENTER and BREAK move around in it: UP / DOWN, LEFT = PgUp, RIGHT = PgDn, ENTER, BREAK = Esc.
  process(clk)
    variable pressed : std_logic_vector(63 downto 0);
    variable chord   : std_logic;
  begin
    if rising_edge(clk) then
      ps2_f_r <= ps2_f;
      ek_prev <= ext_keys;
      pressed := ext_keys and not ek_prev;                       -- keys that went down this clock
      chord := ext_keys(50) and (ext_keys(56) or ext_keys(57));  -- BREAK with a SHIFT
      chord_prev <= chord;
      if reset = '1' or (cen = '1' and iowr = '1' and port_a = x"02") then
        fifo_wp <= (others => '0'); fifo_rp <= (others => '0');
        ev_cnt <= 0;
      else
        if ps2_f = '1' and ps2_f_r = '0' and (fifo_wp + 1) /= fifo_rp then
          fifo(to_integer(fifo_wp)) <= ps2_d;
          fifo_wp <= fifo_wp + 1;
        elsif ev_cnt /= 0 and (fifo_wp + 1) /= fifo_rp then
          -- a keyboard event waits: its bytes go into the FIFO behind the PS/2 bytes
          fifo(to_integer(fifo_wp)) <= ev_b0;
          fifo_wp <= fifo_wp + 1;
          ev_b0 <= ev_b1;
          ev_cnt <= ev_cnt - 1;
        end if;
        if cen = '1' and rdp = '1' and rd_port = x"03" and fifo_rp /= fifo_wp then
          fifo_rp <= fifo_rp + 1;
        end if;
        -- keys of the original keyboard, as PS/2 scan codes for the firmware
        if ev_cnt = 0 then
          if chord = '1' and chord_prev = '0' then
            ev_b0 <= x"07"; ev_cnt <= 1;                                                  -- F12
          elsif ctl4(0) = '1' and (ext_keys(56) or ext_keys(57)) = '0' then               -- menu open
            if    pressed(51) = '1' then ev_b0 <= x"E0"; ev_b1 <= x"75"; ev_cnt <= 2;     -- UP
            elsif pressed(52) = '1' then ev_b0 <= x"E0"; ev_b1 <= x"72"; ev_cnt <= 2;     -- DOWN
            elsif pressed(53) = '1' then ev_b0 <= x"E0"; ev_b1 <= x"7D"; ev_cnt <= 2;     -- LEFT = PgUp
            elsif pressed(54) = '1' then ev_b0 <= x"E0"; ev_b1 <= x"7A"; ev_cnt <= 2;     -- RIGHT = PgDn
            elsif pressed(48) = '1' then ev_b0 <= x"5A"; ev_cnt <= 1;                     -- ENTER
            elsif pressed(50) = '1' then ev_b0 <= x"76"; ev_cnt <= 1;                     -- BREAK = Esc
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- synthesis translate_off
  process(clk)
  begin
    if rising_edge(clk) then
      if ps2_f = '1' and ps2_f_r = '0' then
        report "PS2 byte " & to_hstring(ps2_d);
      end if;
    end if;
  end process;
  process(clk)
  begin
    if rising_edge(clk) and cen = '1' then
      if iowr = '1' and port_a = x"08" then
        report "DBG " & to_hstring(cpu_do);
      end if;
    end if;
  end process;

  -- synthesis translate_on

  -- floppy controller sector buffer window
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

  -- control register and glyph select
  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        ctl4 <= "10";                    -- the CP-300 waits in reset until the firmware has mounted the disks
      elsif cen = '1' and iowr = '1' then
        if port_a = x"04" then ctl4 <= cpu_do(1 downto 0); end if;
      end if;
    end if;
  end process;
  process(clk)
  begin
    if rising_edge(clk) then
      if cen = '1' and iowr = '1' and port_a = x"08" then dbg_r <= cpu_do; end if;
    end if;
  end process;
  dbg <= dbg_r;
  menu_open <= ctl4(0);
  core_rst  <= ctl4(1);

  kbd_avail <= '1' when fifo_wp /= fifo_rp else '0';

  di <= rom_do when mreq_n = '0' and rom_sel = '1' else
        ram_do when mreq_n = '0' and ram_sel = '1' else
        x"FF"  when mreq_n = '0' else
        spi_rx when port_a = x"00" else
        "000000" & (not sd_wp_n) & spi_busy when port_a = x"01" else
        "0000000" & kbd_avail when port_a = x"02" else
        fifo_do when port_a = x"03" else
        gcolbyte when port_a = x"05" else
        '0' & fdc_dam & fdc_drive & fdc_side & fdc_ra & fdc_wr & fdc_rd when port_a = x"10" else
        fdc_track when port_a = x"11" else
        fdc_trkreg when port_a = x"12" else
        fdc_sector when port_a = x"17" else
        fdc_buff_din when port_a = x"14" else
        x"A5"   when port_a = x"07" else
        x"00";

end rtl;
