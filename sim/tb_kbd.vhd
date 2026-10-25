-- Test of the CP-300 keyboard matrix scanner (rtl/kbd/matrix_kbd.vhd) against a model of the
-- passive matrix: a key joins its row line and its column line. sim/run_kbd.sh
library ieee;
use ieee.std_logic_1164.all;

entity tb_kbd is
end tb_kbd;

architecture sim of tb_kbd is
  signal clk   : std_logic := '0';
  signal row_n : std_logic_vector(7 downto 0);
  signal col_n : std_logic_vector(7 downto 0);
  signal keys  : std_logic_vector(63 downto 0);
  signal addr  : std_logic_vector(7 downto 0) := x"00";   -- the CPU address lines A0-A7 at 3800h
  signal dout  : std_logic_vector(7 downto 0);
  signal rst   : std_logic := '1';
  type matrix_t is array (0 to 7) of std_logic_vector(7 downto 0);
  signal down  : matrix_t := (others => (others => '0'));   -- down(r)(c) = key at row r, column c pressed
begin
  clk <= not clk after 11.905 ns;   -- 42 MHz
  rst <= '0' after 1 us;

  dut : entity work.matrix_kbd port map (clk => clk, row_n => row_n, col_n => col_n, keys => keys);

  -- the core's keyboard (PS/2 idle) with the physical matrix merged in
  kbd : entity work.ps2kbd
    port map (RESET => rst, KBCLK => '1', KBDAT => '1', CLK => clk, A => addr, EXT => keys, DOUT => dout,
              SWRES => open, PAGE => open, VCUT => open, INKP => open, PAPERP => open, BORDERP => open);

  -- the columns are pulled up; a pressed key on the selected (low) row pulls its column low
  model : process(row_n, down)
    variable v : std_logic_vector(7 downto 0);
  begin
    v := (others => '1');
    for r in 0 to 7 loop
      if row_n(r) = '0' then
        for c in 0 to 7 loop
          if down(r)(c) = '1' then v(c) := '0'; end if;
        end loop;
      end if;
    end loop;
    col_n <= v;
  end process;

  test : process
    procedure expect(r, c : integer; want : std_logic; what : string) is
    begin
      assert keys(8 * r + c) = want report what & ": key (" & integer'image(r) & "," & integer'image(c) &
        ") is " & std_logic'image(keys(8 * r + c)) severity failure;
    end procedure;
  begin
    wait for 10 ms;
    assert keys = x"0000000000000000" report "keys down with nothing pressed" severity failure;

    -- 'S' is row 2, column 3
    down(2)(3) <= '1';
    wait for 10 ms;
    expect(2, 3, '1', "S pressed");
    -- what the CPU reads: the row is selected by an address line, the column is the data bit
    addr <= x"04"; wait for 1 us;
    assert dout = x"08" report "S: row 2 should read 08, got " & to_hstring(dout) severity failure;
    addr <= x"01"; wait for 1 us;
    assert dout = x"00" report "S: row 0 should read 00" severity failure;
    addr <= x"00"; wait for 1 us;
    assert dout = x"00" report "no row selected should read 00" severity failure;

    -- two keys at once: ENTER (row 6, column 0) and LEFT SHIFT (row 7, column 0)
    down(6)(0) <= '1';
    down(7)(0) <= '1';
    wait for 10 ms;
    expect(6, 0, '1', "ENTER");
    expect(7, 0, '1', "LEFT SHIFT");
    expect(2, 3, '1', "S still down");
    expect(0, 0, '0', "@ not pressed");
    addr <= x"C4"; wait for 1 us;        -- rows 2, 6 and 7 together: S (bit 3), ENTER and LEFT SHIFT (bit 0)
    assert dout = x"09" report "rows 2+6+7 should read 09, got " & to_hstring(dout) severity failure;
    addr <= x"00";

    -- a contact bounce of 1 ms is not a key
    down(4)(5) <= '1';
    wait for 1 ms;
    down(4)(5) <= '0';
    wait for 10 ms;
    expect(4, 5, '0', "bounce");

    -- release
    down(2)(3) <= '0';
    down(6)(0) <= '0';
    down(7)(0) <= '0';
    wait for 10 ms;
    assert keys = (63 downto 0 => '0') report "keys still down after release" severity failure;

    report "matrix scanner: all tests passed";
    wait;
  end process;
end sim;
