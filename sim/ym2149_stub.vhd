--
-- Silent stand-in for rtl/ht1080z/YM2149.vhd (simulation only): GHDL rejects
-- its "u_vol_table : work.vol_table" instantiation, and sound is not needed
-- for the boot test.
--

library ieee;
use ieee.std_logic_1164.all;

entity YM2149 is
  generic (
    MIXER_VOLTABLE      : std_logic := '0';
    IO_OUT_READ_IN      : std_logic := '1'
  );
  port (
  I_DA                : in  std_logic_vector(7 downto 0);
  O_DA                : out std_logic_vector(7 downto 0);
  O_DA_OE_L           : out std_logic;
  I_A9_L              : in  std_logic := '0';
  I_A8                : in  std_logic := '1';
  I_BDIR              : in  std_logic;
  I_BC2               : in  std_logic := '1';
  I_BC1               : in  std_logic;
  I_SEL_L             : in  std_logic := '1';
  I_STEREO            : in  std_logic := '0';
  O_AUDIO             : out std_logic_vector(7 downto 0);
  O_CHAN              : out std_logic_vector(1 downto 0);
  O_AUDIO_L           : out std_logic_vector(9 downto 0);
  O_AUDIO_R           : out std_logic_vector(9 downto 0);
  I_IOA               : in  std_logic_vector(7 downto 0);
  O_IOA               : out std_logic_vector(7 downto 0);
  O_IOA_OE_L          : out std_logic;
  I_IOB               : in  std_logic_vector(7 downto 0);
  O_IOB               : out std_logic_vector(7 downto 0);
  O_IOB_OE_L          : out std_logic;
  ENA                 : in  std_logic;
  RESET_L             : in  std_logic;
  CLK                 : in  std_logic
  );
end;

architecture sim of YM2149 is
begin
  O_DA <= (others => '1');  O_DA_OE_L <= '1';
  O_AUDIO <= (others => '0');  O_CHAN <= "00";
  O_AUDIO_L <= (others => '0');  O_AUDIO_R <= (others => '0');
  O_IOA <= (others => '1');  O_IOA_OE_L <= '1';
  O_IOB <= (others => '1');  O_IOB_OE_L <= '1';
end sim;
