-- Whole machine: the CP-300 core (ht1080z) with its WD1793, the IO controller running its real
-- firmware, and an SD card holding BOOT.DSK in drive 0 (CP300.CFG from tools/mkfat.py).
-- The ROM boots the disk; the boot sector writes "BOOT OK" on the screen (sim/out/screen.txt).
--
--   python tools/mkfat.py sim/out/card.img --clusters 4200 --spc 1
--   sim/run_sys.sh [stop-time]

library ieee;
use ieee.std_logic_1164.all;

entity tb_sys is
end tb_sys;

architecture sim of tb_sys is
  signal clk    : std_logic := '0';
  signal reset  : std_logic := '1';
  signal core_reset, core_rst, menu_open : std_logic;
  signal sd_dq  : std_logic_vector(15 downto 0);

  signal sd_cs_n, spi_sck, spi_mosi, sd_miso, osd_ss3 : std_logic;

  signal fdc_lba : std_logic_vector(10 downto 0);
  signal fdc_rd, fdc_wr, fdc_ack, fdc_buff_wr, fdc_side : std_logic;
  signal fdc_buff_addr : std_logic_vector(8 downto 0);
  signal fdc_buff_dout, fdc_buff_din : std_logic_vector(7 downto 0);
  signal fdc_drive : std_logic_vector(1 downto 0);
  signal drv_ready, drv_wp, drv_two : std_logic_vector(3 downto 0);
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
              fdc_rd => fdc_rd, fdc_wr => fdc_wr, fdc_lba => fdc_lba, fdc_drive => fdc_drive,
              fdc_side => fdc_side, fdc_ack => fdc_ack, fdc_buff_addr => fdc_buff_addr,
              fdc_buff_dout => fdc_buff_dout, fdc_buff_wr => fdc_buff_wr, fdc_buff_din => fdc_buff_din,
              drv_ready => drv_ready, drv_wp => drv_wp, drv_two => drv_two);

  sdcard : entity work.sdcard_model
    port map (sd_cs_n => sd_cs_n, spi_sck => spi_sck, spi_mosi => spi_mosi, sd_miso => sd_miso);

  core : entity work.ht1080z
    port map (
      clk42m => clk, pllLocked => '1', reset => core_reset, led => open, ntsc => '1',
      cass_in => '0', cass_out => open, turbo => '1',
      fdc_sd_lba => fdc_lba, fdc_sd_rd => fdc_rd, fdc_sd_wr => fdc_wr, fdc_sd_ack => fdc_ack,
      fdc_buff_addr => fdc_buff_addr, fdc_buff_dout => fdc_buff_dout, fdc_buff_din => fdc_buff_din,
      fdc_buff_wr => fdc_buff_wr, fdc_drive => fdc_drive, fdc_side => fdc_side,
      drv_ready => drv_ready, drv_wp => drv_wp, drv_two => drv_two,
      ps2clk => '1', ps2dat => '1',
      ht_rgb => open, hs => open, vs => open, hb => open, vb => open, audiomix => open,
      dn_go => '0', dn_wr => '0', dn_addr => (others => '0'), dn_data => (others => '0'),
      dn_idx => (others => '0'),
      exp_addr => open, exp_in => open, exp_out => open, exp_dout => open,
      exp_din => (others => '0'), exp_oe => '0',
      SDRAM_nCS => open, SDRAM_DQ => sd_dq, SDRAM_A => open, SDRAM_DQMH => open, SDRAM_DQML => open,
      SDRAM_nWE => open, SDRAM_nCAS => open, SDRAM_nRAS => open, SDRAM_BA => open, SDRAM_CKE => open);

end sim;
