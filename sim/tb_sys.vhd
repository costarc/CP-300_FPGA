-- Whole machine: the CP-300 core (ht1080z) with its WD1793, the IO controller running its real
-- firmware, and an SD card holding BOOT.DSK in drive 0 (CP300.CFG from tools/mkfat.py).
-- The ROM boots the disk; the boot sector writes "BOOT OK" on the screen (sim/out/screen.txt).
--
--   python tools/mkfat.py sim/out/card.img --clusters 4200 --spc 1
--   sim/run_sys.sh [stop-time]

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_sys is
end tb_sys;

architecture sim of tb_sys is
  signal clk    : std_logic := '0';
  signal reset  : std_logic := '1';
  signal core_reset, core_rst, menu_open : std_logic;
  signal sd_dq  : std_logic_vector(15 downto 0);
  signal kclk, kdat : std_logic := '1';

  signal sd_cs_n, spi_sck, spi_mosi, sd_miso, osd_ss3 : std_logic;

  signal fdc_track, fdc_trkreg, fdc_sector : std_logic_vector(7 downto 0);
  signal fdc_rd, fdc_wr, fdc_ra, fdc_dam, fdc_ack, fdc_buff_wr, fdc_side : std_logic;
  signal fdc_res_found, fdc_res_crc, fdc_res_dam : std_logic;
  signal fdc_buff_addr : std_logic_vector(8 downto 0);
  signal fdc_buff_dout, fdc_buff_din : std_logic_vector(7 downto 0);
  signal fdc_drive : std_logic_vector(1 downto 0);
  signal drv_ready, drv_wp : std_logic_vector(3 downto 0);
begin
  clk <= not clk after 11.905 ns;  -- 42 MHz
  reset <= '0' after 2 us;
  core_reset <= reset or core_rst;

  io : entity work.io_ctrl
    port map (clk => clk, reset => reset,
              sd_cs_n => sd_cs_n, spi_sck => spi_sck, spi_mosi => spi_mosi,
              sd_miso => sd_miso, sd_wp_n => '1', osd_ss3 => osd_ss3,
              ps2clk => '1', ps2dat => '1',
              menu_open => menu_open, core_rst => core_rst,
              fdc_rd => fdc_rd, fdc_wr => fdc_wr, fdc_ra => fdc_ra, fdc_track => fdc_track,
              fdc_trkreg => fdc_trkreg, fdc_sector => fdc_sector, fdc_dam => fdc_dam,
              fdc_res_found => fdc_res_found, fdc_res_crc => fdc_res_crc, fdc_res_dam => fdc_res_dam,
              fdc_drive => fdc_drive,
              fdc_side => fdc_side, fdc_ack => fdc_ack, fdc_buff_addr => fdc_buff_addr,
              fdc_buff_dout => fdc_buff_dout, fdc_buff_wr => fdc_buff_wr, fdc_buff_din => fdc_buff_din,
              drv_ready => drv_ready, drv_wp => drv_wp);

  sdcard : entity work.sdcard_model
    port map (sd_cs_n => sd_cs_n, spi_sck => spi_sck, spi_mosi => spi_mosi, sd_miso => sd_miso);

  core : entity work.ht1080z
    port map (
      clk42m => clk, pllLocked => '1', reset => core_reset, led => open, ntsc => '1',
      cass_in => '0', cass_out => open, turbo => '1',
      fdc_svc_rd => fdc_rd, fdc_svc_wr => fdc_wr, fdc_svc_ra => fdc_ra, fdc_svc_track => fdc_track,
      fdc_svc_trkreg => fdc_trkreg, fdc_svc_sector => fdc_sector, fdc_svc_dam => fdc_dam,
      fdc_svc_ack => fdc_ack, fdc_res_found => fdc_res_found, fdc_res_crc => fdc_res_crc,
      fdc_res_dam => fdc_res_dam,
      fdc_buff_addr => fdc_buff_addr, fdc_buff_dout => fdc_buff_dout, fdc_buff_din => fdc_buff_din,
      fdc_buff_wr => fdc_buff_wr, fdc_drive => fdc_drive, fdc_side => fdc_side,
      drv_ready => drv_ready, drv_wp => drv_wp,
      ps2clk => kclk, ps2dat => kdat,
      ht_rgb => open, hs => open, vs => open, hb => open, vb => open, audiomix => open,
      dn_go => '0', dn_wr => '0', dn_addr => (others => '0'), dn_data => (others => '0'),
      dn_idx => (others => '0'),
      exp_addr => open, exp_in => open, exp_out => open, exp_dout => open,
      exp_din => (others => '0'), exp_oe => '0',
      SDRAM_nCS => open, SDRAM_DQ => sd_dq, SDRAM_A => open, SDRAM_DQMH => open, SDRAM_DQML => open,
      SDRAM_nWE => open, SDRAM_nCAS => open, SDRAM_nRAS => open, SDRAM_BA => open, SDRAM_CKE => open);

  -- Keyboard script, sim/out/keys.txt (optional), one command per line:
  --   K n          PS/2 set 2 scan code n (decimal): pressed 90 ms, then released
  --   S 1 | S 0    left shift down / up
  --   W n          wait n ms of simulated time
  --   T n TEXT     wait until TEXT is on the screen (screen.txt, case ignored), at most n ms
  keys : process
    file f : text;
    file scr : text;
    variable st : file_open_status;
    variable l, sl : line;
    variable c : character;
    variable v, t0 : integer;
    variable ok, found : boolean;
    variable want : string(1 to 40);
    variable wl : integer;

    procedure send(b : std_logic_vector(7 downto 0)) is
      variable par : std_logic := '1';
      variable fr  : std_logic_vector(10 downto 0);
    begin
      for i in 0 to 7 loop par := par xor b(i); end loop;
      fr := '1' & par & b & '0';
      for i in 0 to 10 loop
        kdat <= fr(i);
        wait for 20 us;
        kclk <= '0';
        wait for 40 us;
        kclk <= '1';
        wait for 20 us;
      end loop;
      kdat <= '1';
      wait for 200 us;
    end procedure;

    function up(ch : character) return character is
    begin
      if ch >= 'a' and ch <= 'z' then return character'val(character'pos(ch) - 32); end if;
      return ch;
    end function;

    -- is w(1 to n) somewhere in s (case ignored)?
    function has(s : string; w : string; n : integer) return boolean is
      variable same : boolean;
    begin
      if n = 0 or s'length < n then return false; end if;
      for i in s'low to s'high - n + 1 loop
        same := true;
        for j in 0 to n - 1 loop
          if up(s(i + j)) /= up(w(w'low + j)) then same := false; exit; end if;
        end loop;
        if same then return true; end if;
      end loop;
      return false;
    end function;
  begin
    file_open(st, f, "keys.txt", read_mode);
    if st /= open_ok then wait; end if;
    while not endfile(f) loop
      readline(f, l);
      read(l, c, ok);
      if not ok then next; end if;
      if c = 'K' then
        read(l, v);
        send(std_logic_vector(to_unsigned(v, 8)));
        wait for 90 ms;
        send(x"F0"); send(std_logic_vector(to_unsigned(v, 8)));
        wait for 90 ms;
      elsif c = 'S' then
        read(l, v);
        if v = 1 then send(x"12"); else send(x"F0"); send(x"12"); end if;
      elsif c = 'W' then
        read(l, v);
        wait for v * 1 ms;
      elsif c = 'T' then
        read(l, v);
        read(l, c);                         -- the blank
        wl := 0;
        while l'length > 0 and wl < 40 loop
          read(l, c);
          wl := wl + 1;
          want(wl) := c;
        end loop;
        t0 := 0;
        found := false;
        while not found and t0 < v loop
          wait for 200 ms;
          t0 := t0 + 200;
          file_open(st, scr, "screen.txt", read_mode);
          if st = open_ok then
            while not endfile(scr) loop
              readline(scr, sl);
              if sl /= null and has(sl.all, want, wl) then found := true; end if;
            end loop;
            file_close(scr);
          end if;
        end loop;
        if found then
          report "key script: found " & want(1 to wl) & " after " & integer'image(t0) & " ms";
        else
          report "key script: gave up on " & want(1 to wl) & " after " & integer'image(t0) & " ms";
        end if;
      end if;
    end loop;
    wait;
  end process;

  -- trace of the floppy service requests
  process(fdc_rd, fdc_wr, fdc_ra, fdc_ack, fdc_res_found)
  begin
    report "svc rd=" & std_logic'image(fdc_rd) & " wr=" & std_logic'image(fdc_wr) & " ra=" & std_logic'image(fdc_ra) &
           " ack=" & std_logic'image(fdc_ack) & " found=" & std_logic'image(fdc_res_found) &
           " trk=" & to_hstring(fdc_track) & " reg=" & to_hstring(fdc_trkreg) & " sec=" & to_hstring(fdc_sector);
  end process;

end sim;
