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
--   10  r: floppy controller request: b0 read, b1 write, b2 side, b4:3 drive
--   11  r: block number (512-byte block inside the disk image), low 8 bits
--   12  r: block number, high 3 bits
--   13  w: b0 = acknowledge: the buffer pointer goes to 0 and the buffer port is live while set
--   14  rw: sector buffer data port, 512 bytes, auto-increment (write fills it for a read request,
--       read empties it for a write request)
--   15  w: drive flags: b1:0 drive, b2 disk present, b3 write protected, b4 two sided

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.io_fw_pkg.all;
use work.cp300_roms_pkg.CHARGEN_900_65;

entity io_ctrl is
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

    menu_open : out std_logic;
    core_rst  : out std_logic;
    dbg       : out std_logic_vector(7 downto 0);   -- port 08, shown on the green LEDs

    -- floppy controller sector service
    fdc_rd      : in  std_logic;
    fdc_wr      : in  std_logic;
    fdc_lba     : in  std_logic_vector(10 downto 0);
    fdc_drive   : in  std_logic_vector(1 downto 0);
    fdc_side    : in  std_logic;
    fdc_ack     : out std_logic;
    fdc_buff_addr : out std_logic_vector(8 downto 0);
    fdc_buff_dout : out std_logic_vector(7 downto 0);
    fdc_buff_wr   : out std_logic;
    fdc_buff_din  : in  std_logic_vector(7 downto 0);
    drv_ready   : out std_logic_vector(3 downto 0);
    drv_wp      : out std_logic_vector(3 downto 0);
    drv_two     : out std_logic_vector(3 downto 0)
  );
end io_ctrl;

architecture rtl of io_ctrl is

  type ram_t is array (0 to 8191) of std_logic_vector(7 downto 0);
  type fifo_t is array (0 to 15) of std_logic_vector(7 downto 0);

  signal cen    : std_logic := '0';
  signal cdiv   : unsigned(1 downto 0) := (others => '0');

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
  signal dr_ready, dr_wp, dr_two : std_logic_vector(3 downto 0) := (others => '0');
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

  -- 14 MHz CPU clock enable
  process(clk)
  begin
    if rising_edge(clk) then
      if cdiv = 2 then cdiv <= (others => '0'); cen <= '1';
      else cdiv <= cdiv + 1; cen <= '0'; end if;
    end if;
  end process;

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
      gdata <= CHARGEN_900_65(to_integer(glyph & fcnt(2 downto 0)));
      if fcnt < 10 then
        if fcnt >= 2 then grows(to_integer(fcnt) - 2) <= gdata; end if;
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

  process(clk)
  begin
    if rising_edge(clk) then
      ps2_f_r <= ps2_f;
      if reset = '1' or (cen = '1' and iowr = '1' and port_a = x"02") then
        fifo_wp <= (others => '0'); fifo_rp <= (others => '0');
      else
        if ps2_f = '1' and ps2_f_r = '0' and (fifo_wp + 1) /= fifo_rp then
          fifo(to_integer(fifo_wp)) <= ps2_d;
          fifo_wp <= fifo_wp + 1;
        end if;
        if cen = '1' and rdp = '1' and rd_port = x"03" and fifo_rp /= fifo_wp then
          fifo_rp <= fifo_rp + 1;
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
        dr_ready <= (others => '0'); dr_wp <= (others => '0'); dr_two <= (others => '0');
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
              dr_ready(d) <= cpu_do(2); dr_wp(d) <= cpu_do(3); dr_two(d) <= cpu_do(4);
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
  drv_ready <= dr_ready; drv_wp <= dr_wp; drv_two <= dr_two;

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
        "000" & fdc_drive & fdc_side & fdc_wr & fdc_rd when port_a = x"10" else
        fdc_lba(7 downto 0) when port_a = x"11" else
        "00000" & fdc_lba(10 downto 8) when port_a = x"12" else
        fdc_buff_din when port_a = x"14" else
        x"A5"   when port_a = x"07" else
        x"00";

end rtl;
