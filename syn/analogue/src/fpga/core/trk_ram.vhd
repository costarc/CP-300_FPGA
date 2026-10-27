-- CP-300 FPGA, Analogue Pocket: one byte lane of the 16 KB track RAM (see apf_dataslot).
-- True dual port, two clocks: port A on the bridge clock, port B on the core clock.
-- The simulation uses sim/trk_ram_sim.vhd instead (same entity, no megafunction library).

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library altera_mf;
use altera_mf.altera_mf_components.all;

entity trk_ram is
  port (
    clk_a  : in  std_logic;
    addr_a : in  std_logic_vector(11 downto 0);
    we_a   : in  std_logic;
    din_a  : in  std_logic_vector(7 downto 0);
    dout_a : out std_logic_vector(7 downto 0);
    clk_b  : in  std_logic;
    addr_b : in  std_logic_vector(11 downto 0);
    we_b   : in  std_logic;
    din_b  : in  std_logic_vector(7 downto 0);
    dout_b : out std_logic_vector(7 downto 0)
  );
end trk_ram;

architecture rtl of trk_ram is
begin
  ram : altsyncram
    generic map (
      operation_mode                     => "BIDIR_DUAL_PORT",
      width_a                            => 8,
      widthad_a                          => 12,
      numwords_a                         => 4096,
      width_b                            => 8,
      widthad_b                          => 12,
      numwords_b                         => 4096,
      address_reg_b                      => "CLOCK1",
      indata_reg_b                       => "CLOCK1",
      wrcontrol_wraddress_reg_b          => "CLOCK1",
      outdata_reg_a                      => "UNREGISTERED",
      outdata_reg_b                      => "UNREGISTERED",
      clock_enable_input_a               => "BYPASS",
      clock_enable_input_b               => "BYPASS",
      clock_enable_output_a              => "BYPASS",
      clock_enable_output_b              => "BYPASS",
      read_during_write_mode_port_a      => "NEW_DATA_NO_NBE_READ",
      read_during_write_mode_port_b      => "NEW_DATA_NO_NBE_READ",
      read_during_write_mode_mixed_ports => "DONT_CARE",
      ram_block_type                     => "M10K",
      power_up_uninitialized             => "FALSE",
      intended_device_family             => "Cyclone V",
      lpm_type                           => "altsyncram"
    )
    port map (
      clock0    => clk_a,
      clock1    => clk_b,
      address_a => addr_a,
      address_b => addr_b,
      data_a    => din_a,
      data_b    => din_b,
      wren_a    => we_a,
      wren_b    => we_b,
      q_a       => dout_a,
      q_b       => dout_b
    );
end rtl;
