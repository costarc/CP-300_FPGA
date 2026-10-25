-- IO controller test: the real firmware (io_fw_pkg) against a behavioural SD
-- card (sim/out/card.img, made by tools/mkfat.py) and a PS/2 key sender.
--
-- The OSD SPI traffic is decoded like rtl/mist-modules/osd.v does it and
-- written to osd_<n>.pbm every time the OSD is enabled by a command 0x41.
--
--   sim/run_io.sh [stop-time]

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_io is
end tb_io;

architecture sim of tb_io is
  signal clk, reset : std_logic := '0';
  signal sd_cs_n, spi_sck, spi_mosi, sd_miso, osd_ss3 : std_logic;
  signal ps2clk, ps2dat : std_logic := '1';
  signal ext : std_logic_vector(63 downto 0) := (others => '0');   -- original keyboard matrix
  signal menu_open, core_rst : std_logic;

  signal log_cmd : integer := 0;

begin

  clk <= not clk after 11.905 ns;
  reset <= '1', '0' after 1 us;

  dut : entity work.io_ctrl
    port map (clk => clk, reset => reset,
              sd_cs_n => sd_cs_n, spi_sck => spi_sck, spi_mosi => spi_mosi,
              sd_miso => sd_miso, sd_wp_n => '1', osd_ss3 => osd_ss3,
              ps2clk => ps2clk, ps2dat => ps2dat, ext_keys => ext,
              menu_open => menu_open, core_rst => core_rst,
              fdc_rd => '0', fdc_wr => '0', fdc_ra => '0', fdc_track => x"00", fdc_trkreg => x"00",
              fdc_sector => x"00", fdc_dam => '0', fdc_res_found => open, fdc_res_crc => open,
              fdc_res_dam => open, fdc_drive => "00", fdc_side => '0',
              fdc_ack => open, fdc_buff_addr => open, fdc_buff_dout => open, fdc_buff_wr => open,
              fdc_buff_din => x"00", drv_ready => open, drv_wp => open);

  ----------------------------------------------------------------------
  -- SD card (SPI mode 0, SDHC)
  ----------------------------------------------------------------------
  sdcard : entity work.sdcard_model
    port map (sd_cs_n => sd_cs_n, spi_sck => spi_sck, spi_mosi => spi_mosi, sd_miso => sd_miso);

  mon : process(menu_open, core_rst, sd_cs_n)
  begin
    report "t=" & time'image(now) & " menu_open=" & std_logic'image(menu_open) &
           " core_rst=" & std_logic'image(core_rst) & " sd_cs_n=" & std_logic'image(sd_cs_n);
  end process;

  ----------------------------------------------------------------------
  -- OSD (decodes the same SPI protocol as osd.v)
  ----------------------------------------------------------------------
  osd : process
    type osd_mem_t is array (0 to 4095) of std_logic_vector(7 downto 0);
    variable mem : osd_mem_t := (others => x"00");
    variable sbuf : std_logic_vector(7 downto 0);
    variable cnt  : integer := 0;
    variable nbyte : integer := 0;
    variable cmd  : std_logic_vector(7 downto 0);
    variable bcnt : integer;
    variable shots : integer := 0;
    file f : text;
    variable l : line;
    variable b : std_logic_vector(7 downto 0);
    variable full : std_logic_vector(7 downto 0);
  begin
    loop
      wait on spi_sck, osd_ss3;
      if osd_ss3 = '1' then
        cnt := 0; nbyte := 0; bcnt := 0;
      elsif spi_sck'event and spi_sck = '1' then
        full := sbuf(6 downto 0) & spi_mosi;
        sbuf := full;
        cnt := cnt + 1;
        if cnt = 8 then
          cnt := 0;
          nbyte := nbyte + 1;
          if nbyte = 1 then
            cmd := full;
            bcnt := to_integer(unsigned(full(3 downto 0))) * 256;
            if full(7 downto 4) = "0100" and full(0) = '1' then
              shots := shots + 1;
              file_open(f, "osd_" & integer'image(shots) & ".pbm", write_mode);
              write(l, string'("P1")); writeline(f, l);
              write(l, string'("256 128")); writeline(f, l);
              for y in 0 to 127 loop
                for x in 0 to 255 loop
                  b := mem((y / 8) * 256 + x);
                  if b(y mod 8) = '1' then write(l, string'("1 ")); else write(l, string'("0 ")); end if;
                end loop;
                writeline(f, l);
              end loop;
              file_close(f);
              report "OSD snapshot " & integer'image(shots);
            end if;
          elsif cmd(7 downto 4) = "0010" then
            mem(bcnt) := full;
            bcnt := bcnt + 1;
          end if;
        end if;
      end if;
    end loop;
  end process;

  ----------------------------------------------------------------------
  -- PS/2 keyboard: scan code set 2
  ----------------------------------------------------------------------
  keys : process
    procedure send(b : std_logic_vector(7 downto 0)) is
      variable par : std_logic := '1';
      variable fr  : std_logic_vector(10 downto 0);
    begin
      for i in 0 to 7 loop par := par xor b(i); end loop;
      fr := '1' & par & b & '0';             -- stop, parity, data (bit 0 first below), start
      for i in 0 to 10 loop
        ps2dat <= fr(i);
        wait for 20 us;
        ps2clk <= '0';
        wait for 40 us;
        ps2clk <= '1';
        wait for 20 us;
      end loop;
      ps2dat <= '1';
      wait for 200 us;
    end procedure;
    procedure tap(b : std_logic_vector(7 downto 0)) is
    begin
      send(b); send(x"F0"); send(b);
    end procedure;
    procedure tap_ext(b : std_logic_vector(7 downto 0)) is
    begin
      send(x"E0"); send(b); send(x"E0"); send(x"F0"); send(b);
    end procedure;
  begin
    wait for 60 ms;           -- firmware has initialised the card
    tap(x"07");               -- F12: menu opens
    wait for 40 ms;
    tap_ext(x"72");           -- down
    tap_ext(x"72");           -- down: Drive 1
    tap(x"5A");               -- enter: browse
    wait for 40 ms;
    tap_ext(x"72");           -- second file
    tap(x"5A");               -- mount
    wait for 40 ms;
    tap(x"76");               -- esc
    wait for 40 ms;
    wait;
  end process;

  -- the original keyboard: SHIFT + BREAK opens the menu, then DOWN, ENTER and BREAK (= Esc) move in it
  matrix : process
    procedure tap(k : integer) is
    begin
      ext(k) <= '1'; wait for 20 ms; ext(k) <= '0'; wait for 20 ms;
    end procedure;
  begin
    wait for 330 ms;                      -- after the PS/2 key script above
    ext(56) <= '1'; wait for 20 ms;       -- left shift down
    ext(50) <= '1'; wait for 20 ms;       -- BREAK: SHIFT + BREAK
    ext(50) <= '0'; ext(56) <= '0'; wait for 60 ms;
    tap(52);                              -- DOWN
    tap(52);                              -- DOWN
    tap(48);                              -- ENTER: the file list
    wait for 40 ms;
    tap(50);                              -- BREAK = Esc: back to the main menu
    wait for 40 ms;
    ext(57) <= '1'; wait for 20 ms; ext(50) <= '1'; wait for 20 ms;   -- right shift + BREAK closes the menu
    ext(50) <= '0'; ext(57) <= '0';
    wait;
  end process;

end sim;
