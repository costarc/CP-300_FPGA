--
-- Behavioural stand-in for rtl/ht1080z/sdram.v (simulation only).
-- Same ports; byte-wide 128 KB memory, reads and writes complete at once.
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram is
  port (
    sd_data : inout std_logic_vector(15 downto 0);
    sd_addr : out std_logic_vector(12 downto 0);
    sd_dqm  : out std_logic_vector(1 downto 0);
    sd_ba   : out std_logic_vector(1 downto 0);
    sd_cs   : out std_logic;
    sd_we   : out std_logic;
    sd_ras  : out std_logic;
    sd_cas  : out std_logic;
    init    : in  std_logic;
    clk     : in  std_logic;
    din     : in  std_logic_vector(7 downto 0);
    dout    : out std_logic_vector(7 downto 0);
    addr    : in  std_logic_vector(24 downto 0);
    oe      : in  std_logic;
    we      : in  std_logic
  );
end sdram;

architecture sim of sdram is
  type mem_t is array(0 to 131071) of std_logic_vector(7 downto 0);
  signal mem : mem_t := (others => x"00");
  signal we_old : std_logic := '0';
begin
  sd_data <= (others => 'Z');
  sd_addr <= (others => '0');
  sd_dqm  <= "11";
  sd_ba   <= "00";
  sd_cs   <= '1';
  sd_we   <= '1';
  sd_ras  <= '1';
  sd_cas  <= '1';

  process(clk)
    variable a : integer;
  begin
    if rising_edge(clk) then
      a := to_integer(unsigned(addr(16 downto 0)));
      we_old <= we;
      if we = '1' and we_old = '0' then
        mem(a) <= din;
      end if;
      if oe = '1' then
        dout <= mem(a);
      end if;
    end if;
  end process;
end sim;
