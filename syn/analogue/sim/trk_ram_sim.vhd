-- Simulation model of src/fpga/core/trk_ram.vhd: true dual port RAM, 4096 x 8, two clocks, one clock
-- of read latency on both ports (the address is registered, as in the M10K).

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

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

architecture sim of trk_ram is
  type ram_t is array (0 to 4095) of std_logic_vector(7 downto 0);
  shared variable ram : ram_t := (others => x"00");
  signal ra, rb : integer range 0 to 4095 := 0;
begin
  process(clk_a)
  begin
    if rising_edge(clk_a) then
      if we_a = '1' then ram(to_integer(unsigned(addr_a))) := din_a; end if;
      ra <= to_integer(unsigned(addr_a));
    end if;
  end process;
  process(clk_b)
  begin
    if rising_edge(clk_b) then
      if we_b = '1' then ram(to_integer(unsigned(addr_b))) := din_b; end if;
      rb <= to_integer(unsigned(addr_b));
    end if;
  end process;
  dout_a <= ram(ra);
  dout_b <= ram(rb);
end sim;
