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
  signal menu_open, core_rst : std_logic;

  type byte_arr is array (natural range <>) of std_logic_vector(7 downto 0);
  type char_file is file of character;

  constant IMG_SIZE : natural := 2216960;
  type img_t is array (0 to IMG_SIZE - 1) of std_logic_vector(7 downto 0);

  type img_p is access img_t;

  signal log_cmd : integer := 0;

begin

  clk <= not clk after 11.905 ns;
  reset <= '1', '0' after 1 us;

  dut : entity work.io_ctrl
    port map (clk => clk, reset => reset,
              sd_cs_n => sd_cs_n, spi_sck => spi_sck, spi_mosi => spi_mosi,
              sd_miso => sd_miso, sd_wp_n => '1', osd_ss3 => osd_ss3,
              ps2clk => ps2clk, ps2dat => ps2dat,
              menu_open => menu_open, core_rst => core_rst);

  ----------------------------------------------------------------------
  -- SD card (SPI mode 0, SDHC)
  ----------------------------------------------------------------------
  sdcard : process
    variable card : img_p := new img_t'(others => x"FF");
    variable rx   : std_logic_vector(7 downto 0);
    file f : char_file;
    variable st : file_open_status;
    variable ch : character;
    variable nbit : integer;
    variable tx   : std_logic_vector(7 downto 0) := x"FF";
    variable q    : byte_arr(0 to 600);
    variable qh, qt : integer := 0;
    variable cmdb : byte_arr(0 to 5);
    variable ncmd : integer := 0;
    variable wr_lba : integer;
    variable wr_state : integer := 0;       -- 0 none, 1 wait token, 2 data
    variable wr_cnt : integer;
    variable wrbuf : byte_arr(0 to 511);
    variable acmd41_n : integer := 0;
    variable app : boolean := false;
    variable lba : integer;
    variable arg : unsigned(31 downto 0);

    procedure push(b : std_logic_vector(7 downto 0)) is
    begin
      q(qt) := b; qt := qt + 1;
    end procedure;

    procedure byte_done is
      variable b : std_logic_vector(7 downto 0);
    begin
      b := rx;
      if wr_state = 1 then
        if b = x"FE" then wr_state := 2; wr_cnt := 0; end if;
      elsif wr_state = 2 then
        if wr_cnt < 512 then wrbuf(wr_cnt) := b; end if;
        wr_cnt := wr_cnt + 1;
        if wr_cnt = 514 then
          for i in 0 to 511 loop card.all(wr_lba * 512 + i) := wrbuf(i); end loop;
          push(x"05"); push(x"00"); push(x"00"); push(x"FF");
          wr_state := 0;
        end if;
      elsif ncmd > 0 or b(7 downto 6) = "01" then
        cmdb(ncmd) := b; ncmd := ncmd + 1;
        if ncmd = 6 then
          ncmd := 0;
          arg := unsigned(std_logic_vector'(cmdb(1) & cmdb(2) & cmdb(3) & cmdb(4)));
          push(x"FF");
          case to_integer(unsigned(cmdb(0)(5 downto 0))) is
            when 0  => push(x"01"); app := false;
            when 8  => push(x"01"); push(x"00"); push(x"00"); push(x"01"); push(x"AA");
            when 55 => push(x"01"); app := true;
            when 41 =>
              if app and acmd41_n < 3 then push(x"01"); acmd41_n := acmd41_n + 1;
              else push(x"00"); end if;
              app := false;
            when 58 => push(x"00"); push(x"C0"); push(x"FF"); push(x"80"); push(x"00");
            when 16 => push(x"00");
            when 17 =>
              lba := to_integer(arg);
              push(x"00"); push(x"FF"); push(x"FF"); push(x"FE");
              for i in 0 to 511 loop push(card.all(lba * 512 + i)); end loop;
              push(x"AA"); push(x"AA");
            when 24 =>
              wr_lba := to_integer(arg);
              push(x"00");
              wr_state := 1;
            when others => push(x"04");
          end case;
        end if;
      end if;
      -- next byte the card shifts out
      if qh < qt then tx := q(qh); qh := qh + 1; else tx := x"FF"; qh := 0; qt := 0; end if;
    end procedure;
  begin
    file_open(st, f, "card.img", read_mode);
    assert st = open_ok report "card.img not found (python tools/mkfat.py card.img --clusters 4200 --spc 1)" severity failure;
    for i in 0 to IMG_SIZE - 1 loop
      exit when endfile(f);
      read(f, ch);
      card.all(i) := std_logic_vector(to_unsigned(character'pos(ch), 8));
    end loop;
    file_close(f);
    sd_miso <= '1';
    loop
      if sd_cs_n = '1' then
        nbit := 0; ncmd := 0; qh := 0; qt := 0; tx := x"FF"; wr_state := 0;
        sd_miso <= '1';
        wait on sd_cs_n;
      else
        if nbit = 0 then sd_miso <= tx(7); end if;
        wait on spi_sck, sd_cs_n;
        if sd_cs_n = '0' then
          if spi_sck'event and spi_sck = '1' then
            rx := rx(6 downto 0) & spi_mosi;
            nbit := nbit + 1;
            if nbit = 8 then
              byte_done;
              nbit := 0;
              -- first bit of the next byte is on MISO right after the last rising edge
              sd_miso <= tx(7);
            end if;
          elsif spi_sck'event and spi_sck = '0' and nbit > 0 then
            sd_miso <= tx(7 - nbit);
          end if;
        end if;
      end if;
    end loop;
  end process;

  mon : process(menu_open, core_rst, sd_cs_n)
  begin
    report "t=" & time'image(now) & " menu_open=" & std_logic'image(menu_open) &
           " core_rst=" & std_logic'image(core_rst) & " sd_cs_n=" & std_logic'image(sd_cs_n);
  end process;

  ----------------------------------------------------------------------
  -- OSD (decodes the same SPI protocol as osd.v)
  ----------------------------------------------------------------------
  osd : process
    type osd_mem_t is array (0 to 2047) of std_logic_vector(7 downto 0);
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
              write(l, string'("256 64")); writeline(f, l);
              for y in 0 to 63 loop
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

end sim;
