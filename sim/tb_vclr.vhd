-- A reset clears the video RAM: write a cell, hold RESET low for 2047 clocks (the core's reset length), read it back.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_vclr is
end tb_vclr;

architecture sim of tb_vclr is
  signal clk : std_logic := '0';
  signal reset : std_logic := '1';
  signal a : std_logic_vector(13 downto 0) := (others => '0');
  signal din, dout : std_logic_vector(7 downto 0) := x"00";
  signal cs, wr : std_logic := '1';
begin
  clk <= not clk after 11.905 ns;
  dut : entity work.videoctrl
    port map (reset => reset, clk42 => clk, a => a, din => din, dout => dout, mreq => '1', iorq => '1', wr => wr, cs => cs,
              hz60 => '1', vcut => '0', kana => '0', vvga => '0', page => '0', inkp => '0', paperp => '0', borderp => '0',
              oddline => open, pix_screen => open, pix_ink => open, pix_en => open, ink_c => open, paper_c => open,
              border_c => open, rgbi => open, pclk => open, hsync => open, vsync => open, hblank => open, vblank => open);
  process
    procedure put(addr : integer; v : std_logic_vector(7 downto 0)) is
    begin
      wait until rising_edge(clk);
      a <= std_logic_vector(to_unsigned(addr, 14)); din <= v; cs <= '0'; wr <= '0';
      wait until rising_edge(clk);
      cs <= '1'; wr <= '1';
    end procedure;
    procedure get(addr : integer; v : out std_logic_vector(7 downto 0)) is
    begin
      wait until rising_edge(clk);
      a <= std_logic_vector(to_unsigned(addr, 14));
      wait until rising_edge(clk); wait until rising_edge(clk); wait for 1 ns;
      v := dout;
    end procedure;
    variable v : std_logic_vector(7 downto 0);
    variable bad : integer := 0;
  begin
    wait for 200 ns;
    put(0, x"41"); put(513, x"42"); put(1023, x"43");
    get(513, v); assert v = x"42" report "write failed" severity failure;
    reset <= '0';
    for i in 1 to 2047 loop wait until rising_edge(clk); end loop;
    reset <= '1';
    for k in 0 to 1023 loop
      get(k, v);
      if v /= x"20" then bad := bad + 1; end if;
    end loop;
    if bad = 0 then report "PASS"; else report "FAILED: " & integer'image(bad) & " cells not cleared" severity failure; end if;
    std.env.finish;
  end process;
end sim;
