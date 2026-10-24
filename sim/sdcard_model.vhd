-- Behavioural SD card (SPI mode 0, SDHC) for the simulations. The card content is
-- read from FILE_NAME (a raw image of IMG_SIZE bytes, see tools/mkfat.py); writes go
-- to the in-memory copy only.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdcard_model is
  generic (FILE_NAME : string := "card.img"; IMG_SIZE : natural := 2216960);
  port (sd_cs_n, spi_sck, spi_mosi : in std_logic; sd_miso : out std_logic);
end sdcard_model;

architecture sim of sdcard_model is
  type byte_arr is array (natural range <>) of std_logic_vector(7 downto 0);
  type char_file is file of character;
  type img_t is array (0 to IMG_SIZE - 1) of std_logic_vector(7 downto 0);
  type img_p is access img_t;
begin

  sdcard : process
    variable card : img_p := new img_t'(others => x"FF");
    variable rx   : std_logic_vector(7 downto 0);
    file f : char_file;
    variable st : file_open_status;
    variable ch : character;
    variable nbit : integer;
    variable tx   : std_logic_vector(7 downto 0) := x"FF";
    variable q    : byte_arr(0 to 600);
    variable qh, qt : integer := 0;
    variable cmdb : byte_arr(0 to 5);
    variable ncmd : integer := 0;
    variable wr_lba : integer;
    variable wr_state : integer := 0;       -- 0 none, 1 wait token, 2 data
    variable wr_cnt : integer;
    variable wrbuf : byte_arr(0 to 511);
    variable acmd41_n : integer := 0;
    variable app : boolean := false;
    variable lba : integer;
    variable arg : unsigned(31 downto 0);

    procedure push(b : std_logic_vector(7 downto 0)) is
    begin
      q(qt) := b; qt := qt + 1;
    end procedure;

    procedure byte_done is
      variable b : std_logic_vector(7 downto 0);
    begin
      b := rx;
      if wr_state = 1 then
        if b = x"FE" then wr_state := 2; wr_cnt := 0; end if;
      elsif wr_state = 2 then
        if wr_cnt < 512 then wrbuf(wr_cnt) := b; end if;
        wr_cnt := wr_cnt + 1;
        if wr_cnt = 514 then
          for i in 0 to 511 loop card.all(wr_lba * 512 + i) := wrbuf(i); end loop;
          push(x"05"); push(x"00"); push(x"00"); push(x"FF");
          wr_state := 0;
        end if;
      elsif ncmd > 0 or b(7 downto 6) = "01" then
        cmdb(ncmd) := b; ncmd := ncmd + 1;
        if ncmd = 6 then
          ncmd := 0;
          arg := unsigned(std_logic_vector'(cmdb(1) & cmdb(2) & cmdb(3) & cmdb(4)));
          push(x"FF");
          case to_integer(unsigned(cmdb(0)(5 downto 0))) is
            when 0  => push(x"01"); app := false;
            when 8  => push(x"01"); push(x"00"); push(x"00"); push(x"01"); push(x"AA");
            when 55 => push(x"01"); app := true;
            when 41 =>
              if app and acmd41_n < 3 then push(x"01"); acmd41_n := acmd41_n + 1;
              else push(x"00"); end if;
              app := false;
            when 58 => push(x"00"); push(x"C0"); push(x"FF"); push(x"80"); push(x"00");
            when 16 => push(x"00");
            when 17 =>
              lba := to_integer(arg);
              push(x"00"); push(x"FF"); push(x"FF"); push(x"FE");
              for i in 0 to 511 loop push(card.all(lba * 512 + i)); end loop;
              push(x"AA"); push(x"AA");
            when 24 =>
              wr_lba := to_integer(arg);
              push(x"00");
              wr_state := 1;
            when others => push(x"04");
          end case;
        end if;
      end if;
      -- next byte the card shifts out
      if qh < qt then tx := q(qh); qh := qh + 1; else tx := x"FF"; qh := 0; qt := 0; end if;
    end procedure;
  begin
    file_open(st, f, FILE_NAME, read_mode);
    assert st = open_ok report "card.img not found (python tools/mkfat.py card.img --clusters 4200 --spc 1)" severity failure;
    for i in 0 to IMG_SIZE - 1 loop
      exit when endfile(f);
      read(f, ch);
      card.all(i) := std_logic_vector(to_unsigned(character'pos(ch), 8));
    end loop;
    file_close(f);
    sd_miso <= '1';
    loop
      if sd_cs_n = '1' then
        nbit := 0; ncmd := 0; qh := 0; qt := 0; tx := x"FF"; wr_state := 0;
        sd_miso <= '1';
        wait on sd_cs_n;
      else
        if nbit = 0 then sd_miso <= tx(7); end if;
        wait on spi_sck, sd_cs_n;
        if sd_cs_n = '0' then
          if spi_sck'event and spi_sck = '1' then
            rx := rx(6 downto 0) & spi_mosi;
            nbit := nbit + 1;
            if nbit = 8 then
              byte_done;
              nbit := 0;
              -- first bit of the next byte is on MISO right after the last rising edge
              sd_miso <= tx(7);
            end if;
          elsif spi_sck'event and spi_sck = '0' and nbit > 0 then
            sd_miso <= tx(7 - nbit);
          end if;
        end if;
      end if;
    end loop;
  end process;

end sim;
