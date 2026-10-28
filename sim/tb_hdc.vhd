-- Testbench of the FreeHD controller (rtl/hdc/wd1010.vhd) alone, with a behavioural IO controller
-- and a Z80 that holds every I/O cycle for three CPU clocks (a read or write lasts several enables).
-- Checks the xtrs-style behaviour the drivers rely on: READ SECTOR, WRITE SECTOR, status bits, errors.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_hdc is
end tb_hdc;

architecture sim of tb_hdc is
  signal clk : std_logic := '0';
  signal ce  : std_logic := '0';
  signal reset : std_logic := '1';
  signal io_en, rd, wr : std_logic := '0';
  signal addr : std_logic_vector(3 downto 0) := x"0";
  signal din, dout : std_logic_vector(7 downto 0) := x"00";
  signal hd_ready : std_logic_vector(1 downto 0) := "01";
  signal hd_wp : std_logic_vector(1 downto 0) := "00";
  signal svc_rd, svc_wr, svc_busy, svc_ack : std_logic;
  signal svc_cyl : std_logic_vector(9 downto 0);
  signal svc_head : std_logic_vector(2 downto 0);
  signal svc_sector : std_logic_vector(7 downto 0);
  signal svc_drive : std_logic_vector(1 downto 0);
  signal res_found : std_logic := '1';
  signal bufa : std_logic_vector(8 downto 0) := (others => '0');
  signal bufo, bufi : std_logic_vector(7 downto 0) := x"00";
  signal bufw : std_logic := '0';
  signal ack_r : std_logic := '0';
  signal fails : integer := 0;
  type disk_t is array (0 to 255) of std_logic_vector(7 downto 0);
  shared variable wsec : disk_t;
  signal nreads, nwrites : integer := 0;
  signal last_cyl : std_logic_vector(9 downto 0);
  signal last_head : std_logic_vector(2 downto 0);
  signal last_sec : std_logic_vector(7 downto 0);
begin
  clk <= not clk after 11.905 ns;
  process(clk)
    variable n : integer := 0;
  begin
    if rising_edge(clk) then
      if n = 20 then n := 0; ce <= '1'; else n := n + 1; ce <= '0'; end if;
    end if;
  end process;
  reset <= '0' after 1 us;

  dut : entity work.wd1010
    port map (clk_sys => clk, ce => ce, reset => reset, io_en => io_en, rd => rd, wr => wr, addr => addr,
              din => din, dout => dout, hd_ready => hd_ready, hd_wp => hd_wp,
              svc_rd => svc_rd, svc_wr => svc_wr, svc_busy => svc_busy, svc_cyl => svc_cyl,
              svc_head => svc_head, svc_sector => svc_sector, svc_drive => svc_drive,
              svc_ack => svc_ack, res_found => res_found,
              svc_buff_addr => bufa, svc_buff_dout => bufo, svc_buff_din => bufi, svc_buff_wr => bufw);
  svc_ack <= ack_r;

  -- the IO controller: sector (cyl, head, sec) holds byte i = 7 * (cyl * 64 + head * 32 + sec) + i, except
  -- cylinder 9 which does not exist
  io : process
    variable x : integer;
  begin
    wait until rising_edge(clk) and (svc_rd = '1' or svc_wr = '1');
    last_cyl <= svc_cyl; last_head <= svc_head; last_sec <= svc_sector;
    x := to_integer(unsigned(svc_cyl)) * 64 + to_integer(unsigned(svc_head)) * 32 + to_integer(unsigned(svc_sector));
    for i in 1 to 50 loop wait until rising_edge(clk); end loop;
    if svc_rd = '1' then
      nreads <= nreads + 1;
      if unsigned(svc_cyl) = 9 then
        res_found <= '0';
        ack_r <= '1'; wait until rising_edge(clk); ack_r <= '0';
      else
        res_found <= '1';
        ack_r <= '1';
        wait until rising_edge(clk);
        for i in 0 to 255 loop
          bufa <= std_logic_vector(to_unsigned(i, 9));
          bufo <= std_logic_vector(to_unsigned((7 * x + i) mod 256, 8));
          bufw <= '1';
          wait until rising_edge(clk);
        end loop;
        bufw <= '0';
        wait until rising_edge(clk);
        ack_r <= '0';
      end if;
    else
      nwrites <= nwrites + 1;
      ack_r <= '1';
      wait until rising_edge(clk);
      for i in 0 to 255 loop
        bufa <= std_logic_vector(to_unsigned(i, 9));
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wsec(i) := bufi;
      end loop;
      res_found <= '1';
      ack_r <= '0';
    end if;
    wait until rising_edge(clk);
  end process;

  test : process
    procedure check(c : boolean; m : string) is
    begin
      if not c then report "FAIL: " & m severity error; fails <= fails + 1; end if;
    end procedure;

    -- a Z80 I/O cycle: strobe held for 3 CPU clocks
    procedure outp(a : integer; v : integer) is
    begin
      wait until rising_edge(ce);
      addr <= std_logic_vector(to_unsigned(a, 4)); din <= std_logic_vector(to_unsigned(v, 8)); io_en <= '1'; wr <= '1';
      for i in 1 to 3 loop wait until rising_edge(ce); end loop;
      wr <= '0'; io_en <= '0';
    end procedure;
    procedure inp(a : integer; v : out integer) is
    begin
      wait until rising_edge(ce);
      addr <= std_logic_vector(to_unsigned(a, 4)); io_en <= '1'; rd <= '1';
      for i in 1 to 2 loop wait until rising_edge(ce); end loop;
      wait for 5 ns;
      v := to_integer(unsigned(dout));         -- sampled at the end of the cycle
      wait until rising_edge(ce);
      rd <= '0'; io_en <= '0';
    end procedure;
    procedure wait_status(mask : integer; want : integer) is
      variable s : integer;
    begin
      for i in 1 to 2000 loop
        inp(15, s);
        exit when (s mod (2 * mask)) / mask = want;
        wait until rising_edge(ce);
      end loop;
    end procedure;
    procedure setup(cyl, head, sec : integer) is
    begin
      outp(14, head);                 -- drive 0
      outp(11, sec);
      outp(12, cyl mod 256);
      outp(13, cyl / 256);
    end procedure;
    variable v, bad : integer;
  begin
    wait for 2 us;
    outp(1, 8);
    inp(1, v); check(v = 8, "control readback");
    inp(15, v); check(v = 16#50#, "idle status 50, got " & integer'image(v));

    -- READ cylinder 1 head 1 sector 5 (x = 101)
    setup(1, 1, 5);
    outp(15, 16#20#);
    inp(15, v); check(v = 16#D0#, "busy after the command, got " & integer'image(v));
    wait_status(8, 1);                                       -- DRQ
    inp(15, v); check(v = 16#58#, "DRQ status 58, got " & integer'image(v));
    bad := 0;
    for i in 0 to 255 loop
      inp(8, v);
      if v /= (7 * 101 + i) mod 256 then bad := bad + 1; end if;
    end loop;
    check(bad = 0, "read data: " & integer'image(bad) & " bytes wrong");
    inp(15, v); check(v = 16#50#, "status after the 256th byte 50, got " & integer'image(v));
    check(last_cyl = "0000000001" and last_head = "001" and last_sec = x"05", "service address of the read");

    -- WRITE the same sector with a new pattern
    outp(15, 16#30#);
    inp(15, v); check(v = 16#58#, "write DRQ status 58, got " & integer'image(v));
    for i in 0 to 255 loop outp(8, (255 - i) mod 256); end loop;
    wait_status(128, 0);                                     -- not busy
    inp(15, v); check(v = 16#50#, "status after the write 50, got " & integer'image(v));
    bad := 0;
    for i in 0 to 255 loop
      if wsec(i) /= std_logic_vector(to_unsigned((255 - i) mod 256, 8)) then bad := bad + 1; end if;
    end loop;
    check(bad = 0, "written data: " & integer'image(bad) & " bytes wrong");
    check(nwrites = 1 and nreads = 1, "one read and one write expected");

    -- a sector that does not exist: ID not found
    setup(9, 0, 0);
    outp(15, 16#20#);
    wait_status(128, 0);
    inp(15, v); check(v = 16#51#, "error status 51, got " & integer'image(v));
    inp(9, v); check(v = 16#10#, "ID not found error 10, got " & integer'image(v));

    -- multi-sector is refused, a protected image refuses writes, a missing drive reports not found
    setup(0, 0, 0);
    outp(15, 16#24#);
    inp(15, v); check(v = 16#51#, "multi-sector refused, got " & integer'image(v));
    inp(9, v); check(v = 4, "abort error 04");
    hd_wp <= "01";
    outp(15, 16#30#);
    inp(15, v); check(v = 16#51#, "write to a protected image refused, got " & integer'image(v));
    inp(0, v); check(v = 16#82#, "write protect register 82, got " & integer'image(v));
    hd_wp <= "00";
    outp(14, 8);                                             -- drive 1, no image
    outp(15, 16#20#);
    inp(15, v); check(v = 16#51#, "missing drive not found, got " & integer'image(v));

    -- RESTORE and SEEK finish at once
    outp(14, 0);
    outp(15, 16#10#);
    inp(15, v); check(v = 16#50#, "restore status 50");
    outp(15, 16#70#);
    inp(15, v); check(v = 16#50#, "seek status 50");

    if fails = 0 then
      report "PASS";
    else
      report "FAILED: " & integer'image(fails) & " checks" severity failure;
    end if;
    std.env.finish;
  end process;
end sim;
