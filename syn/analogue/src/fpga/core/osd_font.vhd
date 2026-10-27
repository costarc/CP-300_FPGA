-- Font of the on-screen keyboard: the CP-300 character generator (900-65), 8 scan lines per glyph,
-- bit 7 = leftmost dot. One clock of latency.
--
-- A copy of the character generator that the SD card image fills (the same words the core's own
-- character generator gets: rl_waddr(12) = 1, 512 words, first byte = bits 31:24), so no ROM content
-- is in the bitstream.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity osd_font is
  port (
    clk  : in  std_logic;
    addr : in  std_logic_vector(10 downto 0);     -- {character code, scan line}
    dout : out std_logic_vector(7 downto 0);

    rl_clk   : in  std_logic;
    rl_we    : in  std_logic;
    rl_waddr : in  std_logic_vector(12 downto 0);
    rl_wdata : in  std_logic_vector(31 downto 0)
  );
end osd_font;

architecture rtl of osd_font is
  type lane_t is array (0 to 511) of std_logic_vector(7 downto 0);
  signal c0, c1, c2, c3 : lane_t := (others => (others => '0'));
  signal q0, q1, q2, q3 : std_logic_vector(7 downto 0) := (others => '0');
  signal lane : std_logic_vector(1 downto 0) := "00";
begin
  process(rl_clk)
  begin
    if rising_edge(rl_clk) then
      if rl_we = '1' and rl_waddr(12) = '1' then
        c0(to_integer(unsigned(rl_waddr(8 downto 0)))) <= rl_wdata(31 downto 24);
        c1(to_integer(unsigned(rl_waddr(8 downto 0)))) <= rl_wdata(23 downto 16);
        c2(to_integer(unsigned(rl_waddr(8 downto 0)))) <= rl_wdata(15 downto 8);
        c3(to_integer(unsigned(rl_waddr(8 downto 0)))) <= rl_wdata(7 downto 0);
      end if;
    end if;
  end process;

  process(clk)
  begin
    if rising_edge(clk) then
      q0 <= c0(to_integer(unsigned(addr(10 downto 2))));
      q1 <= c1(to_integer(unsigned(addr(10 downto 2))));
      q2 <= c2(to_integer(unsigned(addr(10 downto 2))));
      q3 <= c3(to_integer(unsigned(addr(10 downto 2))));
      lane <= addr(1 downto 0);
    end if;
  end process;

  with lane select dout <=
    q0 when "00",
    q1 when "01",
    q2 when "10",
    q3 when others;
end rtl;
