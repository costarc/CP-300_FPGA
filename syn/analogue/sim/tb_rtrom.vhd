-- Runtime ROM equivalence test: cp300_rom and videoctrl with RUNTIME_ROM (RAM loaded through the rl_*
-- word port from the ROM package) against the same entities built from the package, bit for bit:
-- every system ROM address, and a frame of the video picture with text in the video RAM (normal
-- and kana character sets).
--
--   syn/analogue/sim/run_rtrom.sh      (needs roms/cp300_roms_pkg.vhd)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.cp300_roms_pkg.all;

entity tb_rtrom is
end tb_rtrom;

architecture sim of tb_rtrom is
  signal clk : std_logic := '0';
  signal rl_we : std_logic := '0';
  signal rl_waddr : std_logic_vector(12 downto 0) := (others => '0');
  signal rl_wdata : std_logic_vector(31 downto 0) := (others => '0');

  signal a : std_logic_vector(13 downto 0) := (others => '0');
  signal d_ref, d_rt : std_logic_vector(7 downto 0);

  signal reset, mreq, iorq, wr, cs, kana : std_logic := '1';
  signal vdin : std_logic_vector(7 downto 0) := (others => '0');
  signal va : std_logic_vector(13 downto 0) := (others => '0');
  signal vdo_ref, vdo_rt : std_logic_vector(7 downto 0);
  signal rgbi_ref, rgbi_rt : std_logic_vector(3 downto 0);
  signal ink_ref, ink_rt, scr_ref, scr_rt, en_ref, en_rt : std_logic;

  signal vmis, vink, smis : integer := 0;
  signal loaded : std_logic := '0';
begin
  clk <= not clk after 11.905 ns;

  rom_ref : entity work.cp300_rom port map (clk => clk, a => a, dout => d_ref);
  rom_rt  : entity work.cp300_rom generic map (RUNTIME_ROM => true)
    port map (clk => clk, a => a, dout => d_rt, rl_clk => clk, rl_we => rl_we, rl_waddr => rl_waddr, rl_wdata => rl_wdata);

  vid_ref : entity work.videoctrl
    port map (reset => reset, clk42 => clk, a => va, din => vdin, dout => vdo_ref, mreq => mreq, iorq => iorq,
              wr => wr, cs => cs, hz60 => '1', vcut => '0', kana => kana, vvga => '0', page => '0',
              inkp => '0', paperp => '0', borderp => '0', pix_screen => scr_ref, pix_ink => ink_ref,
              pix_en => en_ref, rgbi => rgbi_ref);
  vid_rt  : entity work.videoctrl generic map (RUNTIME_ROM => true)
    port map (reset => reset, clk42 => clk, a => va, din => vdin, dout => vdo_rt, mreq => mreq, iorq => iorq,
              wr => wr, cs => cs, hz60 => '1', vcut => '0', kana => kana, vvga => '0', page => '0',
              inkp => '0', paperp => '0', borderp => '0', pix_screen => scr_rt, pix_ink => ink_rt,
              pix_en => en_rt, rgbi => rgbi_rt, rl_clk => clk, rl_we => rl_we, rl_waddr => rl_waddr, rl_wdata => rl_wdata);

  process
    variable bad : integer := 0;
    variable w : std_logic_vector(31 downto 0);
  begin
    reset <= '0';
    for i in 1 to 4 loop wait until rising_edge(clk); end loop;
    reset <= '1';

    -- load: 4096 words of system ROM (the four EPROMs one after the other), 512 words of character generator
    for k in 0 to 4095 loop
      if k < 1024 then w := EPROM_900_61(4*k) & EPROM_900_61(4*k+1) & EPROM_900_61(4*k+2) & EPROM_900_61(4*k+3);
      elsif k < 2048 then w := EPROM_900_62(4*(k-1024)) & EPROM_900_62(4*(k-1024)+1) & EPROM_900_62(4*(k-1024)+2) & EPROM_900_62(4*(k-1024)+3);
      elsif k < 3072 then w := EPROM_900_63(4*(k-2048)) & EPROM_900_63(4*(k-2048)+1) & EPROM_900_63(4*(k-2048)+2) & EPROM_900_63(4*(k-2048)+3);
      else w := EPROM_900_64(4*(k-3072)) & EPROM_900_64(4*(k-3072)+1) & EPROM_900_64(4*(k-3072)+2) & EPROM_900_64(4*(k-3072)+3);
      end if;
      rl_waddr <= std_logic_vector(to_unsigned(k, 13)); rl_wdata <= w; rl_we <= '1';
      wait until rising_edge(clk);
    end loop;
    for k in 0 to 511 loop
      w := CHARGEN_900_65(4*k) & CHARGEN_900_65(4*k+1) & CHARGEN_900_65(4*k+2) & CHARGEN_900_65(4*k+3);
      rl_waddr <= std_logic_vector(to_unsigned(4096 + k, 13)); rl_wdata <= w; rl_we <= '1';
      wait until rising_edge(clk);
    end loop;
    rl_we <= '0';
    wait until rising_edge(clk);

    -- system ROM: every address
    for i in 0 to 16383 loop
      a <= std_logic_vector(to_unsigned(i, 14));
      wait until rising_edge(clk); wait until rising_edge(clk); wait until rising_edge(clk);
      if d_ref /= d_rt then bad := bad + 1; end if;
    end loop;
    report "system ROM: " & integer'image(bad) & " mismatches of 16384";
    if bad /= 0 then report "FAILED" severity failure; end if;

    -- video RAM: text with every character code, written through the CPU interface (3C00-3FFF)
    for i in 0 to 1023 loop
      va <= std_logic_vector(to_unsigned(16#3C00# + i, 14));
      vdin <= std_logic_vector(to_unsigned((i * 7 + i / 64) mod 256, 8));
      mreq <= '0'; wr <= '0'; cs <= '0';
      wait until rising_edge(clk); wait until rising_edge(clk); wait until rising_edge(clk);
      mreq <= '1'; wr <= '1'; cs <= '1';
      wait until rising_edge(clk);
    end loop;
    loaded <= '1';
    wait;
  end process;

  -- compare the pictures once the video RAM is written, for a normal frame and a kana frame
  process
    variable mis, ink, n : integer := 0;
  begin
    wait until loaded = '1';
    kana <= '0';
    for i in 1 to 700000 loop
      wait until rising_edge(clk);
      n := n + 1;
      if ink_ref /= ink_rt or scr_ref /= scr_rt or rgbi_ref /= rgbi_rt then mis := mis + 1; end if;
      if ink_ref = '1' and scr_ref = '1' and en_ref = '1' then ink := ink + 1; end if;
    end loop;
    report "picture (kana off): " & integer'image(mis) & " mismatches, " & integer'image(ink) & " ink pixels";
    if mis /= 0 or ink < 1000 then report "FAILED" severity failure; end if;
    kana <= '1';
    mis := 0; ink := 0;
    for i in 1 to 700000 loop
      wait until rising_edge(clk);
      if ink_ref /= ink_rt or scr_ref /= scr_rt or rgbi_ref /= rgbi_rt then mis := mis + 1; end if;
      if ink_ref = '1' and scr_ref = '1' and en_ref = '1' then ink := ink + 1; end if;
    end loop;
    report "picture (kana on): " & integer'image(mis) & " mismatches, " & integer'image(ink) & " ink pixels";
    if mis /= 0 or ink < 1000 then report "FAILED" severity failure; end if;
    report "PASS";
    finish;
  end process;
end sim;
