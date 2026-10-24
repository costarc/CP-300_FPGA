--
-- CP-300 system ROM: four 2732 EPROMs (CI-28..31, board revision before 2.3)
--
-- Decoder CI-44 selects one EPROM per 4 KB with A13:A12. Its second half
-- maps 3800-3BFF to the keyboard and 3C00-3FFF to video RAM, so the fourth
-- EPROM (900-64) is only reachable at 3000-37FF. The caller decodes
-- 0000-37FF; this block only picks the chip.
--
-- Contents come from roms/cp300_roms_pkg.vhd (tools/mkroms.py).
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.cp300_roms_pkg.all;

entity cp300_rom is
  port (
    clk  : in  std_logic;
    a    : in  std_logic_vector(13 downto 0);
    dout : out std_logic_vector(7 downto 0)
  );
end cp300_rom;

architecture rtl of cp300_rom is

  signal q61, q62, q63, q64 : std_logic_vector(7 downto 0);
  signal sel : std_logic_vector(1 downto 0);

begin

  -- one process per EPROM so each infers its own M9K ROM
  process(clk) begin
    if rising_edge(clk) then q61 <= EPROM_900_61(to_integer(unsigned(a(11 downto 0)))); end if;
  end process;
  process(clk) begin
    if rising_edge(clk) then q62 <= EPROM_900_62(to_integer(unsigned(a(11 downto 0)))); end if;
  end process;
  process(clk) begin
    if rising_edge(clk) then q63 <= EPROM_900_63(to_integer(unsigned(a(11 downto 0)))); end if;
  end process;
  process(clk) begin
    if rising_edge(clk) then q64 <= EPROM_900_64(to_integer(unsigned(a(11 downto 0)))); end if;
  end process;

  process(clk) begin
    if rising_edge(clk) then sel <= a(13 downto 12); end if;
  end process;

  with sel select dout <=
    q61 when "00",   -- CI-28 900-61 0000-0FFF
    q62 when "01",   -- CI-29 900-62 1000-1FFF
    q63 when "10",   -- CI-30 900-63 2000-2FFF
    q64 when others; -- CI-31 900-64 3000-37FF

end rtl;
