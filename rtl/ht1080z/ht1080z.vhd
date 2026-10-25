--
-- HT 1080Z (TSR-80 clone) top level
--
--
-- Copyright (c) 2016-2017 Jozsef Laszlo (rbendr@gmail.com)
--
-- All rights reserved
--
-- Redistribution and use in source and synthezised forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- Redistributions of source code must retain the above copyright notice,
-- this list of conditions and the following disclaimer.
--
-- Redistributions in synthesized form must reproduce the above copyright
-- notice, this list of conditions and the following disclaimer in the
-- documentation and/or other materials provided with the distribution.
--
-- Neither the name of the author nor the names of other contributors may
-- be used to endorse or promote products derived from this software without
-- specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
-- THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.
--
-- Please report bugs to the author, but before you do so, please
-- make sure that this is not a derivative work and that
-- you have the latest version of this file.
--


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;
-- synthesis translate_off
use std.textio.all;
use work.sim_trace_cfg.all;
-- synthesis translate_on

entity ht1080z is
    generic ( EXT_RAM : boolean := false );  -- true: Z80 RAM is outside (ext_ram_*), no SDRAM controller
    Port ( clk42m : in  STD_LOGIC;
        pllLocked : in  STD_LOGIC;
            reset : in  STD_LOGIC;
              led : out STD_LOGIC;
             ntsc : in  STD_LOGIC;
        ext_keys : in  std_logic_vector(63 downto 0);   -- original keyboard matrix, 8 * row + column
            turbo : in  STD_LOGIC;
          cass_in : in  STD_LOGIC;
         cass_out : out std_logic_vector(1 downto 0);

         -- floppy controller: images are served by the IO controller
        fdc_svc_rd : out std_logic;
        fdc_svc_wr : out std_logic;
        fdc_svc_ra : out std_logic;
     fdc_svc_track : out std_logic_vector(7 downto 0);
    fdc_svc_trkreg : out std_logic_vector(7 downto 0);
    fdc_svc_sector : out std_logic_vector(7 downto 0);
       fdc_svc_dam : out std_logic;
       fdc_svc_ack : in  std_logic;
     fdc_res_found : in  std_logic;
       fdc_res_crc : in  std_logic;
       fdc_res_dam : in  std_logic;
     fdc_buff_addr : in  std_logic_vector(8 downto 0);
     fdc_buff_dout : in  std_logic_vector(7 downto 0);
      fdc_buff_din : out std_logic_vector(7 downto 0);
       fdc_buff_wr : in  std_logic;
         fdc_drive : out std_logic_vector(1 downto 0);
          fdc_side : out std_logic;
         drv_ready : in  std_logic_vector(3 downto 0);
            drv_wp : in  std_logic_vector(3 downto 0);

           ps2clk : in  STD_LOGIC;
           ps2dat : in  STD_LOGIC;

           ht_rgb : out std_logic_vector(17 downto 0);
               hs : out STD_LOGIC;
               vs : out STD_LOGIC;
               hb : out STD_LOGIC;
               vb : out STD_LOGIC;
         audiomix : out std_logic_vector(8 downto 0); 

            dn_go : in  std_logic;
            dn_wr : in  std_logic;
          dn_addr : in  std_logic_vector(24 downto 0);
          dn_data : in  std_logic_vector(7 downto 0);
           dn_idx : in  std_logic_vector(4 downto 0);

         exp_addr : out std_logic_vector(15 downto 0);
           exp_in : out std_logic;
          exp_out : out std_logic;
         exp_dout : out std_logic_vector(7 downto 0);
          exp_din : in  std_logic_vector(7 downto 0);
           exp_oe : in  std_logic;

         -- external RAM (EXT_RAM = true): the owner of the RAM raises ext_ram_wait
         -- until the access of the current Z80 cycle is done
      ext_ram_addr : out std_logic_vector(15 downto 0);
        ext_ram_rd : out std_logic;
        ext_ram_wr : out std_logic;
       ext_ram_din : out std_logic_vector(7 downto 0);
      ext_ram_dout : in  std_logic_vector(7 downto 0) := x"ff";
      ext_ram_wait : in  std_logic := '0';

		 -- SDRAM
		  SDRAM_nCS : out std_logic;                     -- Chip Select
		   SDRAM_DQ : inout std_logic_vector(15 downto 0); -- SDRAM Data bus 16 Bits
		    SDRAM_A : out std_logic_vector(12 downto 0);  -- SDRAM Address bus 13 Bits
		 SDRAM_DQMH : out std_logic; -- SDRAM High Data Mask
		 SDRAM_DQML : out std_logic; -- SDRAM Low-byte Data Mask
		  SDRAM_nWE : out std_logic;  -- SDRAM Write Enable
		 SDRAM_nCAS : out std_logic; -- SDRAM Column Address Strobe
		 SDRAM_nRAS : out std_logic; -- SDRAM Row Address Strobe
		   SDRAM_BA : out std_logic_vector(1 downto 0); -- SDRAM Bank Address
		  SDRAM_CKE : out std_logic  -- SDRAM Clock Enable			 
  			  			  
    ); 
end ht1080z;

architecture Behavioral of ht1080z is

component sdram is
      port( sd_data : inout std_logic_vector(15 downto 0);
            sd_addr : out std_logic_vector(12 downto 0);
             sd_dqm : out std_logic_vector(1 downto 0);
              sd_ba : out std_logic_vector(1 downto 0);
              sd_cs : out std_logic;
              sd_we : out std_logic;
             sd_ras : out std_logic;
             sd_cas : out std_logic;
               init : in std_logic;
                clk : in std_logic;
                din : in std_logic_vector(7 downto 0);
               dout : out std_logic_vector(7 downto 0);
               addr : in std_logic_vector(24 downto 0);
                 oe : in std_logic;
                 we : in std_logic
      );
end component;

signal sdram_dqm  : std_logic_vector(1 downto 0);
signal ram_addr : std_logic_vector(24 downto 0);
signal  ram_din : STD_LOGIC_VECTOR(7 downto 0);
signal ram_dout : STD_LOGIC_VECTOR(7 downto 0);
signal ram_dout_sdram : STD_LOGIC_VECTOR(7 downto 0);
signal ram_we: std_logic;
signal ram_oe: std_logic; 

signal   dn_wr_r : std_logic;
signal dn_wr_new : std_logic;
signal dn_addr_r : std_logic_vector(24 downto 0);
signal dn_data_r : std_logic_vector(7 downto 0);

signal res_cnt : std_logic_vector(5 downto 0) := "111111";
signal autores : std_logic; 

signal cpua     : std_logic_vector(15 downto 0); 
signal cpudo    : std_logic_vector(7 downto 0);
signal cpudi    : std_logic_vector(7 downto 0);
signal cpuwr,cpurd,cpumreq,cpuiorq,cpunmi,cpuint,cpum1,cpuClkEn,clkref : std_logic;

signal rgbi : std_logic_vector(3 downto 0);
signal romdo,vramdo,ramdo,ramHdo,kbdout : std_logic_vector(7 downto 0);
signal vramcs : std_logic;

signal page,swres : std_logic;

signal romrd,ramrd,ramwr,vramsel,kbdsel : std_logic;
signal ior,iow,memr,memw : std_logic;
signal vdata : std_logic_vector(7 downto 0);

signal clk42div : std_logic_vector(4 downto 0) := (others => '0');

signal dacout : std_logic;
signal oaudio,snddo : std_logic_vector(7 downto 0) := (others => '0'); 

signal p_hs,p_vs,vgahs,vgavs : std_logic; 
signal pclk : std_logic; 


signal tapebits : std_logic_vector(2 downto 0); 
signal  speaker : std_logic_vector(7 downto 0); 
signal vga : std_logic := '0';
signal oddline : std_logic;

signal inkpulse, paperpulse, borderpulse : std_logic;

-- Model III I/O
signal ec      : std_logic_vector(7 downto 0) := (others => '0'); -- port EC write latch
signal intmask : std_logic_vector(7 downto 0) := (others => '0'); -- port E0 write
signal intstat : std_logic_vector(7 downto 0) := (others => '0'); -- active-high latches; bit 2 = 30 Hz RTC
signal nmimask : std_logic_vector(7 downto 0) := (others => '0'); -- port E4 write
signal fdc_intrq, fdc_motoff : std_logic := '0'; -- WD1793 INTRQ, motor timeout (not modelled)
signal rtc_cnt : integer range 0 to 1399999 := 0; -- 42 MHz / 30 Hz
signal e0sel, e4sel, ecsel, ffsel : std_logic;

-- floppy controller (ports F0-F3) and drive select latch (F4)
signal f4      : std_logic_vector(7 downto 0) := (others => '0');
signal fdcsel, f3sel : std_logic;
signal fdc_dout : std_logic_vector(7 downto 0);
signal fdc_drq, fdc_busy : std_logic;
signal fdc_rdy, fdc_wp_i : std_logic;
signal fdc_drv : std_logic_vector(1 downto 0);
signal fdc_drv_on : std_logic;
signal fdc_reset : std_logic;
signal wait_cnt : std_logic_vector(21 downto 0) := (others => '0');
signal cpuwait : std_logic;
signal cpuwait_c : std_logic;   -- WAIT_n before the register stage used with EXT_RAM
signal wait_r : std_logic := '1';
signal waiting : std_logic;

begin

  led <= not dn_go;--swres;
  
  process(clk42m)
  begin
    if rising_edge(clk42m) then
	    clk42div <= clk42div + 1;
		 -- 42 MHz/21 = 2.0 MHz (CP-300)
		 if clk42div = 20 then clk42div <= (others => '0'); end if;
	 end if;
  end process;
  
  ior <= cpurd or cpuiorq or (not cpum1);
  iow <= cpuwr or cpuiorq;
  memr <= cpurd or cpumreq;
  memw <= cpuwr or cpumreq;
  
  -- CP-300 decoder CI-44: ROM 0000-37FF, keyboard 3800, video RAM 3C00
  romrd <= '1' when memr='0' and cpua<x"3800" else '0';
  ramrd <= '1' when cpua(15 downto 14)/="00" and memr='0' else '0';
  ramwr <= '1' when cpua(15 downto 14)/="00" and memw='0' else '0';
  vramsel <= '1' when cpua(15 downto 10)="001111" and cpumreq='0' else '0';
  kbdsel  <= '1' when cpua(15 downto 10)="001110" and memr='0' else '0';
  e0sel <= '1' when cpua(7 downto 0)=x"e0" else '0';
  e4sel <= '1' when cpua(7 downto 0)=x"e4" else '0';
  ecsel <= '1' when cpua(7 downto 0)=x"ec" else '0';
  ffsel <= '1' when cpua(7 downto 0)=x"ff" else '0';
  fdcsel <= '1' when cpua(7 downto 2)="111100" else '0';
  f3sel  <= '1' when cpua(7 downto 0)=x"f3" else '0';

  -- F4 bits 0-3 select a drive (lowest set bit wins), bit 4 side, bit 6 wait enable
  fdc_drv_on <= f4(0) or f4(1) or f4(2) or f4(3);
  fdc_drv    <= "00" when f4(0)='1' else "01" when f4(1)='1' else "10" when f4(2)='1' else "11";
  fdc_rdy    <= fdc_drv_on and drv_ready(conv_integer(fdc_drv));
  fdc_wp_i   <= drv_wp(conv_integer(fdc_drv));
  fdc_drive  <= fdc_drv;
  fdc_side   <= f4(4);
  fdc_reset  <= '1' when autores='0' or dn_go='1' else '0';

  fdc : entity work.wd1793
    port map (
      clk_sys => clk42m, ce => cpuClkEn, reset => fdc_reset,
      io_en => fdcsel, rd => not ior, wr => not iow, addr => cpua(1 downto 0),
      din => cpudo, dout => fdc_dout, drq => fdc_drq, intrq => fdc_intrq, busy => fdc_busy,
      drive => fdc_drv, side => f4(4), ready => fdc_rdy, wp => fdc_wp_i,
      svc_rd => fdc_svc_rd, svc_wr => fdc_svc_wr, svc_ra => fdc_svc_ra,
      svc_track => fdc_svc_track, svc_trkreg => fdc_svc_trkreg, svc_sector => fdc_svc_sector,
      svc_dam => fdc_svc_dam, svc_ack => fdc_svc_ack,
      res_found => fdc_res_found, res_crc => fdc_res_crc, res_dam => fdc_res_dam,
      svc_buff_addr => fdc_buff_addr, svc_buff_dout => fdc_buff_dout, svc_buff_din => fdc_buff_din,
      svc_buff_wr => fdc_buff_wr
    );

  -- wait states: a data register access (F3) holds the CPU until DRQ or INTRQ when F4 bit 6 is set.
  -- A 100 ms timeout releases a stuck CPU.
  waiting <= '1' when f4(6)='1' and f3sel='1' and (ior='0' or iow='0') and fdc_drq='0' and fdc_intrq='0' else '0';
  cpuwait_c <= '0' when (waiting='1' and wait_cnt(21)='0') or ext_ram_wait='1' else '1';

  -- EXT_RAM (slower FPGAs): WAIT_n comes from a register that only changes late in the CPU's
  -- enable period (clk42div 6 and 16, the Z80 samples it on the enables at 0 and, in turbo, 10).
  -- Its long paths into the T80 then have several clocks to settle.
  process(clk42m)
  begin
    if rising_edge(clk42m) then
      if clk42div = 6 or clk42div = 16 then wait_r <= cpuwait_c; end if;
    end if;
  end process;
  cpuwait <= wait_r when EXT_RAM else cpuwait_c;

  -- IM 1 timer interrupt and NMI: masked latches, active low
  cpuint <= '0' when (intstat and intmask) /= x"00" else '1';
  cpunmi <= '0' when (fdc_intrq = '1' and nmimask(7) = '1') or (fdc_motoff = '1' and nmimask(6) = '1') else '1';
  cass_out <= tapebits(1 downto 0);

  exp_addr <= cpua;
  exp_out <= not iow;
  exp_in <= not ior;
  exp_dout <= cpudo;

  cpu : entity work.T80s
   port map (  
	   RESET_n => autores, --swres,
		CLK     => clk42m, 
		CEN     => cpuClkEn and not dn_go, -- 2.0 MHz
		WAIT_n  => cpuwait,
		INT_n   => cpuint,
		NMI_n   => cpunmi,
		BUSRQ_n => '1',
		M1_n    => cpum1,
		MREQ_n  => cpumreq,
		IORQ_n  => cpuiorq,
		RD_n    => cpurd,
		WR_n    => cpuwr,
		RFSH_n  => open,
		HALT_n  => open,
		BUSAK_n => open,
		A       => cpua, 
		DI      => cpudi,
		DO      => cpudo
  );

  cpudi <= --romdo when romrd='1' else
	        --ramdo when ramrd='1' else
           exp_din when exp_oe = '1' else
			  romdo when romrd='1' else
			  ram_dout when ramrd='1' else
			  vramdo when vramsel='1' else
			  kbdout when kbdsel='1' else
			  x"30" when ior='0' and cpua(7 downto 0)=x"fd" else -- printer io read
			  -- WD1793 at F0-F3; F4-F7 read FF. Without a disk the status reads NOT READY
			  -- and the ROM falls through to "Cass?".
			  -- An empty drive 0 answers like a missing controller (status 00, no Track 0): the ROM then
			  -- goes to "Cass?" instead of printing "Diskette?" forever. Mount a disk and use the
			  -- menu's reset to boot it.
			  x"00" when ior='0' and cpua(7 downto 0)=x"f0" and fdc_drv="00" and fdc_rdy='0' else
			  fdc_dout when ior='0' and fdcsel='1' else
				  -- Model III: E0 interrupt status (active low), E4 NMI status (bit 7 INTRQ,
				  -- bit 6 motor timeout, active low), FF bit 7 cassette input
				  not (intstat and intmask) when ior='0' and e0sel='1' else
				  not (fdc_intrq & fdc_motoff & "000000") when ior='0' and e4sel='1' else
				  cass_in & "1111111" when ior='0' and ffsel='1' else
				  x"ff";

  -- the CP-300 character generator has its own glyphs for 00-1F
  vdata <= cpudo;

  rom : entity work.cp300_rom
    port map (
      clk  => clk42m,
      a    => cpua(13 downto 0),
      dout => romdo
    );

  -- video ram at 0x3C00
  video : entity work.videoctrl 
    port map (   
	  reset => autores, --swres and pllLocked,
	  clk42 => clk42m,
			a => cpua(13 downto 0),
		 din => vdata,--cpudo,
		dout => vramdo,
		mreq => cpumreq,
		iorq => cpuiorq,
		  wr => cpuwr,
		  cs => not vramsel,
		hz60 => ntsc,
		vcut => ec(2),
			kana => ec(3),
		vvga => '0',
		page => page,
		rgbi => rgbi, 
	   pclk => pclk,
		inkp => inkpulse,
	 paperp => paperpulse,
	borderp => borderpulse,
	oddline => oddline,
	  hsync => hs,
	  vsync => vs,
	  hblank=> hb,
	  vblank=> vb
   );  

  kbd : entity work.ps2kbd 
    port  map ( 
	   RESET => not pllLocked,
 	   KBCLK => ps2clk,
	   KBDAT => ps2dat,
		SWRES => swres,
	     CLK => clk42m,
		    A => cpua(7 downto 0),
			 EXT => ext_keys,
		 DOUT => kbdout,
		 PAGE => page,
		 VCUT => open,
		 INKP => inkpulse,
	  PAPERP => paperpulse,
	 BORDERP => borderpulse
		  );
	
  with tapebits select speaker <=
   "00100000" when "001",
	"00010000" when "000"|"011",
   "00000000" when others;
 
  audiomix <= '0' & speaker; 
 	 
	-- fix palette for now
	--with rgbi select rgb <=
	with rgbi select ht_rgb <=
	 "000000000000000000" when "0000",
	 "000000000000100000" when "0001",
	 "000000100000000000" when "0010",
	 "000000100000100000" when "0011",
	 "100000000000000000" when "0100",
	 "100000000000100000" when "0101",
	 "110000011000000000" when "0110",
	 "100000100000100000" when "0111",
	 "110000110000110000" when "1000",
	 "000000000000111100" when "1001",
	 "000000111100000000" when "1010",
	 "000000111100111100" when "1011",
	 "111110000000000000" when "1100",
	 "111100000000111100" when "1101",
	 "111110111110000000" when "1110",
	 "111110111110111110" when others;

  sdram_gen : if not EXT_RAM generate
  sdram_inst : sdram
    port map( sd_data => SDRAM_DQ,
              sd_addr => SDRAM_A,
               sd_dqm => sdram_dqm,
                sd_cs => SDRAM_nCS,
                sd_ba => SDRAM_BA,
                sd_we => SDRAM_nWE,
               sd_ras => SDRAM_nRAS,
               sd_cas => SDRAM_nCAS,
                  clk => clk42m,
                 init => not pllLocked,
                  din => ram_din,
                 addr => ram_addr,
                   we => ram_we,
                   oe => ram_oe,
                 dout => ram_dout_sdram
    ); 	
  end generate;
  sdram_off : if EXT_RAM generate
    SDRAM_nCS <= '1'; SDRAM_A <= (others => '0'); SDRAM_nWE <= '1'; SDRAM_nCAS <= '1';
    SDRAM_nRAS <= '1'; SDRAM_BA <= "00"; SDRAM_DQ <= (others => 'Z'); sdram_dqm <= "11";
    ram_dout_sdram <= x"ff";
  end generate;
  ext_ram_addr <= cpua;
  ext_ram_rd   <= ramrd when EXT_RAM else '0';
  ext_ram_wr   <= ramwr when EXT_RAM else '0';
  ext_ram_din  <= cpudo;
  ram_dout     <= ext_ram_dout when EXT_RAM else ram_dout_sdram;
  --ram_addr <= "000000000" & cpua when dn_go='0' else dn_addr_r; 
  ram_din <= cpudo when dn_go='0' else dn_data_r;
  ram_we <= ((not memw) and (cpua(15) or cpua(14))) when dn_go='0' else dn_wr_r; 
  --ram_oe <= not memr when dn_go='0' else '0';
  
  ram_addr <= "000000000" & cpua when dn_go='0' else dn_addr_r; 
  ram_oe <= not memr when dn_go='0' else '0';
	 
  -- sdram interface
  SDRAM_CKE <= '1';
  SDRAM_DQMH <= sdram_dqm(1);
  SDRAM_DQML <= sdram_dqm(0); 	 

  process(clk42m)
  -- sync wr from data io to sdram clkref
  begin
    if rising_edge(clk42m) then
	   if dn_wr='1' then
		  dn_wr_new <= '1';
		  dn_data_r <= dn_data;
			if dn_idx = x"00" then
				dn_addr_r <= dn_addr;
			else
				dn_addr_r <= dn_addr + x"10000";
			end if;
		end if;
		if clkref = '1' then
			if dn_wr_new = '1' then
				dn_wr_r <= '1';
				dn_wr_new <= '0';
			else
				dn_wr_r <= '0';
			end if;
		end if;
	 end if;
  end process; 
  
 process (clk42m, pllLocked)
 begin
   if pllLocked = '0' then
		  res_cnt <= "000000";
   elsif rising_edge(clk42m) then
		if reset = '1' then
		  res_cnt <= "000000";
		else
		  if (res_cnt/="111111") then
			 res_cnt <= res_cnt+1;
		  end if;
		end if;
   end if;
 end process;
 
 cpuClkEn <= '1' when clk42div = 0 or (turbo = '1' and clk42div = 10) else '0'; -- 42/21 = 2.0 MHz
 clkref <= '1' when clk42div = 0 or clk42div = 10 else '0'; -- ~4 MHz
 autores <= '1' when res_cnt="111111" else '0';   


 -- Model III I/O ports
 process (clk42m)
 begin
   if rising_edge(clk42m) then
     if dn_go='1' or autores='0' then
       tapebits <= "000";
       f4 <= (others => '0');
       ec <= (others => '0');
       intmask <= (others => '0');
       intstat <= (others => '0');
       nmimask <= (others => '0');
       rtc_cnt <= 0;
     else
       if waiting = '1' then
         if wait_cnt(21) = '0' then wait_cnt <= wait_cnt + 1; end if;
       else
         wait_cnt <= (others => '0');
       end if;
       -- 30 Hz real-time clock
       if rtc_cnt = 1399999 then
         rtc_cnt <= 0;
         intstat(2) <= '1';
       else
         rtc_cnt <= rtc_cnt + 1;
       end if;
       if cpuClkEn = '1' then
         if iow='0' then
           if ffsel='1' then tapebits <= cpudo(2 downto 0); end if;
           if e0sel='1' then intmask <= cpudo; end if;
           if e4sel='1' then nmimask <= cpudo; end if;
           if ecsel='1' then ec <= cpudo; end if;
           if cpua(7 downto 0)=x"f4" then f4 <= cpudo; end if;
         end if;
         -- reading EC acknowledges the RTC interrupt
         if ior='0' and ecsel='1' then intstat(2) <= '0'; end if;
       end if;
     end if;
   end if;
 end process;

-- synthesis translate_off
-- Simulation only: log opcode fetches and memory writes to trace.txt
-- between TRACE_FROM and TRACE_TO (sim/run.sh generates sim_trace_cfg).
process(clk42m)
  file f : text;
  variable l : line;
  variable opened : boolean := false;
  variable fetch, wrcyc, fetch_old, wrcyc_old : boolean := false;
  variable op : std_logic_vector(7 downto 0);
  variable pc : std_logic_vector(15 downto 0);
begin
  if rising_edge(clk42m) and now >= TRACE_FROM and now < TRACE_TO then
    if not opened then
      file_open(f, "trace.txt", write_mode);
      opened := true;
    end if;
    fetch := cpum1 = '0' and cpumreq = '0' and cpurd = '0';
    wrcyc := cpumreq = '0' and cpuwr = '0';
    if fetch then
      pc := cpua; op := cpudi;
    end if;
    if fetch_old and not fetch then
      write(l, string'("PC ")); hwrite(l, pc); write(l, string'(" ")); hwrite(l, op);
      writeline(f, l);
    end if;
    if wrcyc and not wrcyc_old then
      write(l, string'("WR ")); hwrite(l, cpua); write(l, string'(" ")); hwrite(l, cpudo);
      writeline(f, l);
    end if;
    fetch_old := fetch;
    wrcyc_old := wrcyc;
  end if;
end process;
-- synthesis translate_on

end Behavioral;
