-- Scanner for the original CP-300 keyboard, a passive 8 x 8 switch matrix (schematic: row lines
-- A0-A7 driven by inverters from the CPU address, column lines C0-C7 pulled up and read by a
-- buffer onto D0-D7). Here the FPGA does what those parts did, at 3.3 V:
--
--   row_n(r)  output, idle high, driven low while row r is being read (like an inverter output)
--   col_n(c)  input with a pull-up to 3.3 V; a key on the selected row pulls its column low
--   keys      the debounced matrix, keys(8 * r + c) = 1 while the key at row r, column c is down
--
-- The rows are read one after the other all the time, so the CPU reads the matrix register and
-- does not have to wait for the cable. A key change is accepted after DEBOUNCE identical scans.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity matrix_kbd is
  generic (
    SETTLE   : natural := 1050;   -- clocks from driving a row to reading the columns (25 us at 42 MHz)
    DEBOUNCE : natural := 24      -- identical scans in a row before a change is accepted (about 5 ms)
  );
  port (
    clk   : in  std_logic;
    row_n : out std_logic_vector(7 downto 0);
    col_n : in  std_logic_vector(7 downto 0);
    keys  : out std_logic_vector(63 downto 0)
  );
end matrix_kbd;

architecture rtl of matrix_kbd is
  type byte_arr is array (0 to 7) of std_logic_vector(7 downto 0);
  type cnt_arr  is array (0 to 7) of integer range 0 to 255;

  signal row    : integer range 0 to 7 := 0;
  signal timer  : integer range 0 to 65535 := 0;
  signal c1, c2 : std_logic_vector(7 downto 0) := (others => '1');   -- synchronizer
  signal last   : byte_arr := (others => (others => '0'));
  signal cnt    : cnt_arr := (others => 0);
  signal stable : byte_arr := (others => (others => '0'));
  signal rows   : std_logic_vector(7 downto 0) := (others => '1');
begin

  process(clk)
    variable raw : std_logic_vector(7 downto 0);
  begin
    if rising_edge(clk) then
      c1 <= col_n;
      c2 <= c1;
      if timer = SETTLE then
        timer <= 0;
        raw := not c2;                              -- 1 = key down
        if raw = last(row) then
          if cnt(row) < DEBOUNCE then
            cnt(row) <= cnt(row) + 1;
          else
            stable(row) <= raw;
          end if;
        else
          last(row) <= raw;
          cnt(row) <= 0;
        end if;
        if row = 7 then row <= 0; else row <= row + 1; end if;
      else
        timer <= timer + 1;
      end if;
    end if;
  end process;

  -- the row being read is low, the others high
  gen : for r in 0 to 7 generate
    rows(r) <= '0' when row = r else '1';
  end generate;
  row_n <= rows;

  out_gen : for r in 0 to 7 generate
    keys(8 * r + 7 downto 8 * r) <= stable(r);
  end generate;

end rtl;
