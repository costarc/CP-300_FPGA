-- CP-300 FPGA, Analogue Pocket: data slot access for the IO controller.
--
-- Disk images are APF data slots (deferload, so the framework does not copy them anywhere). The IO
-- controller reads and writes them one 512 byte block at a time with the target commands
-- "data slot read" and "data slot write" of core_bridge_cmd:
--
--   read   the framework writes the block to the bridge at 20000000h..200001FFh (rx buffer)
--   write  the framework reads the block from the bridge at 30000000h..300001FFh (tx buffer)
--
-- The bridge is big endian here (bridge_endian_little = 0): the first byte of a word is bits 31:24.
--
-- This block also watches the data slot size table (a RAM of core_bridge_cmd, filled by the framework
-- for every slot) and the "data slot update" event, so the IO controller knows which of the four
-- drive slots hold a file and when a file was replaced.
--
-- Two clocks: clk_74a (bridge) and clk (the core, 42 MHz). Everything that crosses is a toggle or a
-- static value.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity apf_dataslot is
  port (
    clk_74a     : in  std_logic;
    reset_n_74  : in  std_logic;                      -- host reset_n, 74 MHz domain, low = reset
    clk         : in  std_logic;
    reset       : in  std_logic;                      -- clk domain, high = reset

    -- bridge (clk_74a)
    bridge_wr       : in  std_logic;
    bridge_addr     : in  std_logic_vector(31 downto 0);
    bridge_wr_data  : in  std_logic_vector(31 downto 0);
    tx_rd_data      : out std_logic_vector(31 downto 0);    -- the tx buffer word at bridge_addr, one clock late

    dataslot_update      : in std_logic;
    dataslot_update_id   : in std_logic_vector(15 downto 0);

    target_dataslot_read       : out std_logic;
    target_dataslot_write      : out std_logic;
    target_dataslot_ack        : in  std_logic;
    target_dataslot_done       : in  std_logic;
    target_dataslot_err        : in  std_logic_vector(2 downto 0);
    target_dataslot_id         : out std_logic_vector(15 downto 0);
    target_dataslot_slotoffset : out std_logic_vector(31 downto 0);
    target_dataslot_bridgeaddr : out std_logic_vector(31 downto 0);
    target_dataslot_length     : out std_logic_vector(31 downto 0);

    datatable_addr : out std_logic_vector(9 downto 0);
    datatable_q    : in  std_logic_vector(31 downto 0);

    -- IO controller (clk), see io_ctrl_pocket
    req_tog     : in  std_logic;
    req_wr      : in  std_logic;
    req_slot    : in  std_logic_vector(1 downto 0);
    req_offset  : in  std_logic_vector(31 downto 0);
    busy        : out std_logic;
    err         : out std_logic;
    rx_addr     : in  std_logic_vector(8 downto 0);
    rx_data     : out std_logic_vector(7 downto 0);
    tx_we       : in  std_logic;
    tx_addr     : in  std_logic_vector(8 downto 0);
    tx_data     : in  std_logic_vector(7 downto 0);
    present     : out std_logic_vector(3 downto 0);
    changed     : out std_logic_vector(3 downto 0);
    chg_clr     : in  std_logic_vector(3 downto 0);
    scan_valid  : out std_logic
  );
end apf_dataslot;

architecture rtl of apf_dataslot is

  type rx_t is array (0 to 127) of std_logic_vector(31 downto 0);
  type lane_t is array (0 to 127) of std_logic_vector(7 downto 0);
  type sz_t is array (0 to 3) of std_logic_vector(31 downto 0);
  type st_t is (S_IDLE, S_ISSUE, S_TAKEN, S_WAIT, S_FIN);
  type sc_t is (C_A0, C_A1, C_A2, C_A3, C_B0, C_B1, C_B2, C_B3);

  signal rx_ram : rx_t := (others => (others => '0'));
  signal tx0, tx1, tx2, tx3 : lane_t := (others => (others => '0'));
  signal rx_w   : std_logic_vector(31 downto 0) := (others => '0');
  signal rx_lane: std_logic_vector(1 downto 0) := "00";

  -- clk_74a domain
  signal rq1, rq2, rq3 : std_logic := '0';
  signal st     : st_t := S_IDLE;
  signal rd_r, wr_r : std_logic := '0';
  signal done_tog : std_logic := '0';
  signal err_74 : std_logic := '0';
  signal slot_74 : std_logic_vector(15 downto 0) := (others => '0');

  signal sc     : sc_t := C_A0;
  signal ent    : unsigned(4 downto 0) := (others => '0');
  signal dt_addr: std_logic_vector(9 downto 0) := (others => '0');
  signal id_tmp : std_logic_vector(15 downto 0) := (others => '0');
  signal new_sz, cur_sz : sz_t := (others => (others => '0'));
  signal present_74 : std_logic_vector(3 downto 0) := (others => '0');
  signal chg_tog : std_logic_vector(3 downto 0) := (others => '0');
  signal scan_ok : std_logic := '0';

  -- clk domain
  signal ds1, ds2 : std_logic := '0';
  signal pr1, pr2 : std_logic_vector(3 downto 0) := (others => '0');
  signal cg1, cg2 : std_logic_vector(3 downto 0) := (others => '0');
  signal seen     : std_logic_vector(3 downto 0) := (others => '0');
  signal sv1, sv2 : std_logic := '0';
  signal eb1, eb2 : std_logic := '0';
  signal er1, er2 : std_logic := '0';

begin

  -- ---------------------------------------------------------------- buffers
  process(clk_74a)
  begin
    if rising_edge(clk_74a) then
      if bridge_wr = '1' and bridge_addr(31 downto 28) = "0010" then
        rx_ram(to_integer(unsigned(bridge_addr(8 downto 2)))) <= bridge_wr_data;
      end if;
      tx_rd_data <= tx0(to_integer(unsigned(bridge_addr(8 downto 2)))) &
                    tx1(to_integer(unsigned(bridge_addr(8 downto 2)))) &
                    tx2(to_integer(unsigned(bridge_addr(8 downto 2)))) &
                    tx3(to_integer(unsigned(bridge_addr(8 downto 2))));
    end if;
  end process;

  process(clk)
  begin
    if rising_edge(clk) then
      rx_w    <= rx_ram(to_integer(unsigned(rx_addr(8 downto 2))));
      rx_lane <= rx_addr(1 downto 0);
      if tx_we = '1' then
        case tx_addr(1 downto 0) is
          when "00"   => tx0(to_integer(unsigned(tx_addr(8 downto 2)))) <= tx_data;
          when "01"   => tx1(to_integer(unsigned(tx_addr(8 downto 2)))) <= tx_data;
          when "10"   => tx2(to_integer(unsigned(tx_addr(8 downto 2)))) <= tx_data;
          when others => tx3(to_integer(unsigned(tx_addr(8 downto 2)))) <= tx_data;
        end case;
      end if;
    end if;
  end process;

  with rx_lane select rx_data <=
    rx_w(31 downto 24) when "00",
    rx_w(23 downto 16) when "01",
    rx_w(15 downto 8)  when "10",
    rx_w(7 downto 0)   when others;

  -- ---------------------------------------------------------------- target commands (clk_74a)
  target_dataslot_read       <= rd_r;
  target_dataslot_write      <= wr_r;
  target_dataslot_id         <= slot_74;
  target_dataslot_slotoffset <= req_offset;        -- static while a command runs
  target_dataslot_bridgeaddr <= x"30000000" when req_wr = '1' else x"20000000";
  target_dataslot_length     <= x"00000200";

  process(clk_74a)
  begin
    if rising_edge(clk_74a) then
      if reset_n_74 = '0' then
        rq1 <= '0'; rq2 <= '0'; rq3 <= '0';
        st <= S_IDLE; rd_r <= '0'; wr_r <= '0'; done_tog <= '0'; err_74 <= '0';
      else
        rq1 <= req_tog; rq2 <= rq1; rq3 <= rq2;
        case st is
          when S_IDLE =>
            if rq2 /= rq3 then
              slot_74 <= x"000" & "00" & req_slot;
              st <= S_ISSUE;
            end if;
          when S_ISSUE =>
            -- raise the request; core_bridge_cmd acts on its rising edge
            rd_r <= not req_wr;
            wr_r <= req_wr;
            st <= S_TAKEN;
          when S_TAKEN =>
            -- the command has started when done drops (it is cleared at the start of each command)
            if target_dataslot_done = '0' then
              rd_r <= '0'; wr_r <= '0';
              st <= S_WAIT;
            end if;
          when S_WAIT =>
            if target_dataslot_done = '1' then
              if target_dataslot_err /= "000" then err_74 <= '1'; else err_74 <= '0'; end if;
              st <= S_FIN;
            end if;
          when S_FIN =>
            done_tog <= not done_tog;
            st <= S_IDLE;
        end case;
      end if;
    end if;
  end process;

  -- ---------------------------------------------------------------- slot table scan (clk_74a)
  -- Walks the 32 entries of the data slot size table over and over: word 0 = slot id, word 1 = size.
  -- A slot counts as present when an entry with its id has a size; a changed size, or a "data slot
  -- update" event, toggles chg_tog.
  datatable_addr <= dt_addr;
  process(clk_74a)
    variable n : integer;
  begin
    if rising_edge(clk_74a) then
      if reset_n_74 = '0' then
        sc <= C_A0; ent <= (others => '0'); scan_ok <= '0';
        present_74 <= (others => '0'); chg_tog <= (others => '0');
        new_sz <= (others => (others => '0')); cur_sz <= (others => (others => '0'));
      else
        if dataslot_update = '1' and dataslot_update_id(15 downto 2) = "00000000000000" then
          n := to_integer(unsigned(dataslot_update_id(1 downto 0)));
          chg_tog(n) <= not chg_tog(n);
        end if;
        case sc is
          when C_A0 => dt_addr <= "0000" & std_logic_vector(ent) & "0"; sc <= C_A1;
          when C_A1 => sc <= C_A2;
          when C_A2 => sc <= C_A3;
          when C_A3 => id_tmp <= datatable_q(15 downto 0); sc <= C_B0;
          when C_B0 => dt_addr <= "0000" & std_logic_vector(ent) & "1"; sc <= C_B1;
          when C_B1 => sc <= C_B2;
          when C_B2 => sc <= C_B3;
          when C_B3 =>
            if datatable_q /= x"00000000" and id_tmp(15 downto 2) = "00000000000000" then
              new_sz(to_integer(unsigned(id_tmp(1 downto 0)))) <= datatable_q;
            end if;
            sc <= C_A0;
            ent <= ent + 1;
            if ent = 31 then
              -- end of a pass
              for i in 0 to 3 loop
                if new_sz(i) /= x"00000000" then present_74(i) <= '1'; else present_74(i) <= '0'; end if;
                if new_sz(i) /= cur_sz(i) then
                  if not (dataslot_update = '1' and to_integer(unsigned(dataslot_update_id(1 downto 0))) = i) then
                    chg_tog(i) <= not chg_tog(i);
                  end if;
                end if;
                cur_sz(i) <= new_sz(i);
                new_sz(i) <= (others => '0');
              end loop;
              scan_ok <= '1';
            end if;
        end case;
      end if;
    end if;
  end process;

  -- ---------------------------------------------------------------- into the core clock domain
  process(clk)
  begin
    if rising_edge(clk) then
      ds1 <= done_tog; ds2 <= ds1;
      pr1 <= present_74; pr2 <= pr1;
      cg1 <= chg_tog;    cg2 <= cg1;
      sv1 <= scan_ok;    sv2 <= sv1;
      er1 <= err_74;     er2 <= er1;
      if reset = '1' then
        seen <= (others => '0');
      else
        for i in 0 to 3 loop
          if chg_clr(i) = '1' then seen(i) <= cg2(i); end if;
        end loop;
      end if;
    end if;
  end process;

  busy       <= req_tog xor ds2;
  err        <= er2;
  present    <= pr2;
  changed    <= cg2 xor seen;
  scan_valid <= sv2;

end rtl;
