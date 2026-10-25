-- Font of the on-screen keyboard: the CP-300 character generator (900-65), 8 scan lines per glyph,
-- bit 7 = leftmost dot. One clock of latency.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.cp300_roms_pkg.CHARGEN_900_65;

entity osd_font is
  port (
    clk  : in  std_logic;
    addr : in  std_logic_vector(10 downto 0);     -- {character code, scan line}
    dout : out std_logic_vector(7 downto 0)
  );
end osd_font;

architecture rtl of osd_font is
begin
  process(clk)
  begin
    if rising_edge(clk) then
      dout <= CHARGEN_900_65(to_integer(unsigned(addr)));
    end if;
  end process;
end rtl;
