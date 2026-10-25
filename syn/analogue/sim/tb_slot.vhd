-- Analogue Pocket IO controller test: the real firmware (firmware/pocket) and io_ctrl_pocket +
-- apf_dataslot against a behavioural APF host (data slot read/write commands, slot size table,
-- data slot update event), with the floppy controller's sector requests played by this bench.
--
--   syn/analogue/sim/run_slot.sh
--
-- Checks: the firmware mounts drive 0 from slot 0 and releases the CP-300; sector reads through the
-- DMK image return the right bytes; a missing sector is reported; a sector write goes back to the
-- file (read back through the same path); an eject and a new file are seen as a mount change.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_slot is
end tb_slot;

architecture sim of tb_slot is
  signal clk, clk74 : std_logic := '0';
  signal reset, reset_n_74 : std_logic := '0';

  signal core_rst : std_logic;
  signal dbg : std_logic_vector(7 downto 0);

  signal fdc_rd, fdc_wr, fdc_ra : std_logic := '0';
  signal fdc_track, fdc_trkreg, fdc_sector : std_logic_vector(7 downto 0) := (others => '0');
  signal fdc_res_found, fdc_res_crc, fdc_res_dam : std_logic;
  signal fdc_drive : std_logic_vector(1 downto 0) := "00";
  signal fdc_ack : std_logic;
  signal fdc_buff_addr : std_logic_vector(8 downto 0);
  signal fdc_buff_dout, fdc_buff_din : std_logic_vector(7 downto 0);
  signal fdc_buff_wr : std_logic;
  signal drv_ready, drv_wp : std_logic_vector(3 downto 0);

  signal req_tog, req_wr, busy, err, tx_we, scan_valid : std_logic;
  signal req_slot : std_logic_vector(1 downto 0);
  signal req_offset : std_logic_vector(31 downto 0);
  signal rx_addr, tx_addr : std_logic_vector(8 downto 0);
  signal rx_data, tx_data : std_logic_vector(7 downto 0);
  signal present, changed, chg_clr : std_logic_vector(3 downto 0);

  -- bridge
  signal bridge_wr : std_logic := '0';
  signal bridge_addr, bridge_wr_data, tx_rd_data : std_logic_vector(31 downto 0) := (others => '0');
  signal dataslot_update : std_logic := '0';
  signal dataslot_update_id : std_logic_vector(15 downto 0) := (others => '0');
  signal t_read, t_write, t_ack, t_done : std_logic := '0';
  signal t_err : std_logic_vector(2 downto 0) := "000";
  signal t_id : std_logic_vector(15 downto 0);
  signal t_off, t_baddr, t_len : std_logic_vector(31 downto 0);
  signal dt_addr : std_logic_vector(9 downto 0);
  signal dt_q : std_logic_vector(31 downto 0) := (others => '0');

  -- the host's view of slot 0
  type img_t is array (0 to 262143) of std_logic_vector(7 downto 0);
  shared variable img : img_t := (others => x"FF");
  signal img_size : integer := 0;
  shared variable slot0_size : integer := 0;     -- what the size table says (0 = no file)
  signal host_ops, host_writes : integer := 0;

  type buf_t is array (0 to 511) of std_logic_vector(7 downto 0);
  shared variable fbuf : buf_t := (others => x"00");

  signal fails : integer := 0;
  signal mount_done : std_logic := '0';

begin

  clk   <= not clk after 11.905 ns;
  clk74 <= not clk74 after 6.734 ns;
  reset_n_74 <= '0', '1' after 2 us;
  reset <= not reset_n_74;

  dut : entity work.io_ctrl_pocket
    generic map (CPU_HALF => false)
    port map (clk => clk, reset => reset, core_rst => core_rst, dbg => dbg,
              fdc_rd => fdc_rd, fdc_wr => fdc_wr, fdc_ra => fdc_ra, fdc_track => fdc_track,
              fdc_trkreg => fdc_trkreg, fdc_sector => fdc_sector, fdc_dam => '0',
              fdc_res_found => fdc_res_found, fdc_res_crc => fdc_res_crc, fdc_res_dam => fdc_res_dam,
              fdc_drive => fdc_drive, fdc_side => '0', fdc_ack => fdc_ack,
              fdc_buff_addr => fdc_buff_addr, fdc_buff_dout => fdc_buff_dout, fdc_buff_wr => fdc_buff_wr,
              fdc_buff_din => fdc_buff_din, drv_ready => drv_ready, drv_wp => drv_wp,
              slot_req_tog => req_tog, slot_req_wr => req_wr, slot_num => req_slot, slot_offset => req_offset,
              slot_busy => busy, slot_err => err, rx_addr => rx_addr, rx_data => rx_data,
              tx_we => tx_we, tx_addr => tx_addr, tx_data => tx_data,
              slot_present => present, slot_changed => changed, slot_chg_clr => chg_clr,
              scan_valid => scan_valid, opt_wp => '0');

  slots : entity work.apf_dataslot
    port map (clk_74a => clk74, reset_n_74 => reset_n_74, clk => clk, reset => reset,
              bridge_wr => bridge_wr, bridge_addr => bridge_addr, bridge_wr_data => bridge_wr_data,
              tx_rd_data => tx_rd_data,
              dataslot_update => dataslot_update, dataslot_update_id => dataslot_update_id,
              target_dataslot_read => t_read, target_dataslot_write => t_write,
              target_dataslot_ack => t_ack, target_dataslot_done => t_done, target_dataslot_err => t_err,
              target_dataslot_id => t_id, target_dataslot_slotoffset => t_off,
              target_dataslot_bridgeaddr => t_baddr, target_dataslot_length => t_len,
              datatable_addr => dt_addr, datatable_q => dt_q,
              req_tog => req_tog, req_wr => req_wr, req_slot => req_slot, req_offset => req_offset,
              busy => busy, err => err, rx_addr => rx_addr, rx_data => rx_data,
              tx_we => tx_we, tx_addr => tx_addr, tx_data => tx_data,
              present => present, changed => changed, chg_clr => chg_clr, scan_valid => scan_valid);

  ----------------------------------------------------------------------
  -- slot size table (core_bridge_cmd's RAM): entry 0 = slot 0, the rest unused (id 0, size 0)
  ----------------------------------------------------------------------
  process(clk74)
    variable e : integer;
  begin
    if rising_edge(clk74) then
      e := to_integer(unsigned(dt_addr(5 downto 1)));
      if dt_addr(0) = '0' then
        dt_q <= x"00000000";                          -- slot id 0 in every entry (as an unused entry reads)
      elsif e = 0 then
        dt_q <= std_logic_vector(to_unsigned(slot0_size, 32));
      else
        dt_q <= x"00000000";
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------
  -- APF host: executes the target commands of core_bridge_cmd
  ----------------------------------------------------------------------
  host : process
    type cf is file of character;
    file f : cf;
    variable c : character;
    variable n, off, w : integer;
    variable word : std_logic_vector(31 downto 0);
  begin
    -- load the disk image
    file_open(f, "disk.dmk", read_mode);
    n := 0;
    while not endfile(f) loop
      read(f, c);
      img(n) := std_logic_vector(to_unsigned(character'pos(c), 8));
      n := n + 1;
    end loop;
    file_close(f);
    img_size <= n;
    slot0_size := n;
    loop
      wait until rising_edge(clk74) and (t_read = '1' or t_write = '1');
      host_ops <= host_ops + 1;
      off := to_integer(unsigned(t_off));
      -- the command is taken: done and err are cleared, ack rises when the host starts to work
      for i in 1 to 4 loop wait until rising_edge(clk74); end loop;
      t_done <= '0'; t_err <= "000";
      for i in 1 to 3 loop wait until rising_edge(clk74); end loop;
      t_ack <= '1';
      for i in 1 to 100 loop wait until rising_edge(clk74); end loop;     -- the host's latency
      assert t_len = x"00000200" report "bad length" severity failure;
      if t_read = '1' or (t_baddr(31 downto 28) = x"2") then
        -- host writes the block into the core, one word per ~75 clocks
        assert t_baddr = x"20000000" report "read: bad bridge address" severity failure;
        for k in 0 to 127 loop
          word := img(off + 4*k) & img(off + 4*k + 1) & img(off + 4*k + 2) & img(off + 4*k + 3);
          bridge_addr <= std_logic_vector(unsigned(t_baddr) + to_unsigned(4*k, 32));
          bridge_wr_data <= word;
          bridge_wr <= '1';
          wait until rising_edge(clk74);
          bridge_wr <= '0';
          for i in 1 to 8 loop wait until rising_edge(clk74); end loop;
        end loop;
      else
        -- host reads the block out of the core
        assert t_baddr = x"30000000" report "write: bad bridge address" severity failure;
        host_writes <= host_writes + 1;
        for k in 0 to 127 loop
          bridge_addr <= std_logic_vector(unsigned(t_baddr) + to_unsigned(4*k, 32));
          for i in 1 to 4 loop wait until rising_edge(clk74); end loop;
          word := tx_rd_data;
          img(off + 4*k)     := word(31 downto 24);
          img(off + 4*k + 1) := word(23 downto 16);
          img(off + 4*k + 2) := word(15 downto 8);
          img(off + 4*k + 3) := word(7 downto 0);
        end loop;
      end if;
      wait until rising_edge(clk74);
      t_done <= '1';
      wait until rising_edge(clk74);
      t_ack <= '0';
    end loop;
  end process;

  ----------------------------------------------------------------------
  -- floppy controller side: the sector buffer
  ----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if fdc_buff_wr = '1' then
        fbuf(to_integer(unsigned(fdc_buff_addr))) := fdc_buff_dout;
      end if;
      fdc_buff_din <= fbuf(to_integer(unsigned(fdc_buff_addr)));
    end if;
  end process;

  mon : process(scan_valid, dbg, core_rst, present, busy, drv_ready, changed)
  begin
    report "t=" & time'image(now) & " scan_valid=" & std_logic'image(scan_valid) & " dbg=" &
           integer'image(to_integer(unsigned(dbg))) & " core_rst=" & std_logic'image(core_rst) &
           " present=" & integer'image(to_integer(unsigned(present))) & " busy=" & std_logic'image(busy) &
           " ready=" & integer'image(to_integer(unsigned(drv_ready))) & " chg=" & integer'image(to_integer(unsigned(changed)));
  end process;

  ----------------------------------------------------------------------
  -- the test
  ----------------------------------------------------------------------
  test : process
    variable found, crc : std_logic;

    procedure check(cond : boolean; msg : string) is
    begin
      if not cond then
        report "FAIL: " & msg severity error;
        fails <= fails + 1;
      end if;
    end procedure;

    -- one request like the WD1793 makes it: held until the IO controller acknowledges
    procedure request(rd, wr, ra : std_logic; trk, sec : integer) is
    begin
      fdc_track <= std_logic_vector(to_unsigned(trk, 8));
      fdc_trkreg <= std_logic_vector(to_unsigned(trk, 8));
      fdc_sector <= std_logic_vector(to_unsigned(sec, 8));
      fdc_rd <= rd; fdc_wr <= wr; fdc_ra <= ra;
      wait until rising_edge(clk) and fdc_ack = '1';
      for i in 1 to 6 loop wait until rising_edge(clk); end loop;
      fdc_rd <= '0'; fdc_wr <= '0'; fdc_ra <= '0';
      wait until rising_edge(clk) and fdc_ack = '0';
      found := fdc_res_found; crc := fdc_res_crc;
      wait until rising_edge(clk);
    end procedure;

    procedure read_check(trk, sec : integer) is
      variable bad : integer := 0;
    begin
      request('1', '0', '0', trk, sec);
      check(found = '1', "sector " & integer'image(trk) & "/" & integer'image(sec) & " not found");
      check(crc = '0', "CRC error on " & integer'image(trk) & "/" & integer'image(sec));
      for i in 0 to 255 loop
        if fbuf(i) /= std_logic_vector(to_unsigned((trk * 31 + sec * 7 + i) mod 256, 8)) then
          bad := bad + 1;
        end if;
      end loop;
      check(bad = 0, "data differs in " & integer'image(trk) & "/" & integer'image(sec) & ": " & integer'image(bad) & " bytes");
      report "read " & integer'image(trk) & "/" & integer'image(sec) & " ok=" & boolean'image(bad = 0 and found = '1');
    end procedure;
  begin
    wait until core_rst = '0' for 60 ms;
    check(core_rst = '0', "firmware did not release the CP-300 within 60 ms");
    check(drv_ready(0) = '1', "drive 0 not ready after mount");
    check(drv_ready(1) = '0', "drive 1 ready without a file");
    report "mounted at " & time'image(now) & " dbg=" & integer'image(to_integer(unsigned(dbg)));
    mount_done <= '1';

    read_check(0, 0);
    read_check(0, 9);
    read_check(17, 5);
    read_check(34, 3);

    request('1', '0', '0', 5, 12);
    check(found = '0', "sector 12 should not exist");

    -- write a sector with a different pattern, then read it back
    fdc_drive <= "00";
    for i in 0 to 255 loop
      fbuf(i) := std_logic_vector(to_unsigned((255 - i) mod 256, 8));
    end loop;
    wait until rising_edge(clk);
    request('0', '1', '0', 2, 4);
    check(found = '1', "write of 2/4 failed");
    check(host_writes > 0, "no data slot write reached the host");
    for i in 0 to 255 loop fbuf(i) := x"00"; end loop;
    wait until rising_edge(clk);
    request('1', '0', '0', 2, 4);
    check(found = '1' and crc = '0', "read back of 2/4: found/crc");
    for i in 0 to 255 loop
      check(fbuf(i) = std_logic_vector(to_unsigned((255 - i) mod 256, 8)), "read back byte " & integer'image(i));
      exit when fails > 5;
    end loop;
    read_check(2, 3);
    read_check(2, 5);

    -- read address: the next ID field of the track
    request('0', '0', '1', 3, 0);
    check(found = '1', "read address");
    check(fbuf(0) = x"03", "ID cylinder");

    -- eject: the size table shows no file and the host sends a data slot update
    slot0_size := 0;
    dataslot_update_id <= x"0000"; dataslot_update <= '1';
    wait until rising_edge(clk74); dataslot_update <= '0';
    wait until drv_ready(0) = '0' for 5 ms;
    check(drv_ready(0) = '0', "drive 0 still ready after eject");
    -- and a file again
    slot0_size := img_size;
    dataslot_update_id <= x"0000"; dataslot_update <= '1';
    wait until rising_edge(clk74); dataslot_update <= '0';
    wait until drv_ready(0) = '1' for 5 ms;
    check(drv_ready(0) = '1', "drive 0 not ready after the file came back");
    read_check(2, 3);                                          -- after the remount
    report "host ops: " & integer'image(host_ops);

    if fails = 0 then
      report "PASS";
    else
      report "FAILED: " & integer'image(fails) & " checks" severity failure;
    end if;
    finish;
  end process;

end sim;
