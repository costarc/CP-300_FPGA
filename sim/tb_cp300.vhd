--
-- Boot test: the ht1080z core with the CP-300 ROMs, behavioural SDRAM,
-- idle PS/2 keyboard. videoctrl writes the screen to screen.txt each frame.
--
--   sim/run.sh [stop-time]     (default 1500ms)
--

library ieee;
use ieee.std_logic_1164.all;

entity tb_cp300 is
end tb_cp300;

architecture sim of tb_cp300 is
  signal clk    : std_logic := '0';
  signal reset  : std_logic := '1';
  signal sd_dq  : std_logic_vector(15 downto 0);
  signal exp_addr : std_logic_vector(15 downto 0);
  signal exp_dout : std_logic_vector(7 downto 0);
  signal exp_in, exp_out : std_logic;
begin
  clk <= not clk after 11.905 ns;  -- 42 MHz
  reset <= '0' after 2 us;

  -- where the CPU is, every 10 ms
  process
  begin
    wait for 10 ms;
    report "CPU address " & to_hstring(exp_addr);
  end process;


  dut : entity work.ht1080z
    port map (
      clk42m    => clk,
      pllLocked => '1',
      reset     => reset,
      led       => open,
      ntsc      => '1',
      cass_in   => '0',
      cass_out  => open,
      turbo     => '1',  -- 3.5 MHz: the no-disk timeout before "Cass?" is ~4.8M T-states
      ps2clk    => '1',
      ps2dat    => '1',
      ht_rgb    => open,
      hs        => open,
      vs        => open,
      hb        => open,
      vb        => open,
      audiomix  => open,
      dn_go     => '0',
      dn_wr     => '0',
      dn_addr   => (others => '0'),
      dn_data   => (others => '0'),
      dn_idx    => (others => '0'),
      exp_addr  => exp_addr,
      exp_in    => exp_in,
      exp_out   => exp_out,
      exp_dout  => exp_dout,
      exp_din   => (others => '0'),
      exp_oe    => '0',
      SDRAM_nCS => open,
      SDRAM_DQ  => sd_dq,
      SDRAM_A   => open,
      SDRAM_DQMH => open,
      SDRAM_DQML => open,
      SDRAM_nWE => open,
      SDRAM_nCAS => open,
      SDRAM_nRAS => open,
      SDRAM_BA  => open,
      SDRAM_CKE => open
    );

end sim;
