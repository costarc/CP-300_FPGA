# Handover: Model III I/O, SD card, OSD, disk and cassette

Written 2026-10-24. Next work on the CP-300 FPGA: make the machine load software from an SD card (floppy images and cassette files), with an on-screen menu to choose and swap them.

## Where the project stands

Repo `C:\Users\roniv\dev\github\CP-300_FPGA`, branch `main`, last commits:

- `9ab4330` DE0: also generate a .pof for the EPCS4 configuration flash
- `51ef545` Complete CP-300 ROM set: boots to "Cass?" in simulation
- `786ba6a` CP-300 ROMs: four 2732 EPROMs and the 2716 character generator
- `beb9adf` Phase 1: HT1080Z (TRS-80 Model I) core on the Terasic DE0

Working:

- HT1080Z core (mist-devel/ht1080z) running stand-alone on the Terasic DE0 (Cyclone III EP3C16F484C6): 50 -> 42 MHz PLL, SDRAM remapped for the DE0 chip, PS/2 keyboard, 31 kHz VGA via the MiST scandoubler, RS-232 at E8-EA, sigma-delta audio on GPIO0_D[0].
- CP-300 system ROM as four on-chip 2732 images (decoder CI-44: A13:A12 pick the chip, 0000-37FF) and the 2716 character generator (8-dot cells, 512 active pixels, 2x3 graphic blocks).
- GHDL simulation boots the ROM to "Cass?" at 1.38 s (turbo).
- Quartus II 13.0sp1 builds `.sof` and `.pof` (EPCS4); 27% LEs, 35% memory bits, timing met.

Not done or not verified:

- Never run on a real DE0.
- Model III I/O is missing: the core is still Model I underneath (INT_n and NMI_n tied high, no port E0/E4/EC logic, 1.75 MHz CPU).
- F0-F7 read 00 so the ROM sees "no disk" (see design-notes.md).
- No SD card, no disk controller, no cassette input to the CPU. HT1080Z's tape loading used the MiST ARM (port 04 reads from SDRAM), which the DE0 does not have.

Read first: `README.md`, `docs/design-notes.md`, `roms/README.md`.

## Design decided

The user agreed on an OSD menu. The plan is below; the IO-controller CPU choice (T80 + SDCC vs Nios II/e) was proposed as T80 + SDCC and not yet confirmed. Ask if unsure.

| Block | What | Source |
|---|---|---|
| IO controller | Second T80 in the FPGA, 16 KB firmware ROM + 8 KB RAM in M9K, C built with SDCC. Replaces the MiST ARM: SD card over SPI, FAT16/32 (Petit FatFs or FatFs), OSD, sector service for the FDC, cassette streaming. | new firmware, `rtl/T80` (already a submodule) |
| FDC | WD1793 at F0-F3, Model III drive-select latch at F4, INTRQ -> NMI via port E4 mask. Asks for 512-byte blocks via the MiSTer `sd_lba` / `sd_rd` / `sd_wr` / `sd_ack` / `sd_buff_*` interface; the IO controller answers from the mounted file. | `C:\Users\roniv\dev\github\CoCo2_FPGA\rtl\wd1793.sv` (Slavinsky / Sorgelig, GPL-2+, with Stan Hodge's 18 x 256 track mod) |
| OSD | Menu over the VGA picture, F12 opens it; PS/2 keys go to the menu while it is open. | `rtl/mist-modules/osd.v` (already instantiated inside `mist_video`, its SPI tied off in `rtl/de0/cp300_de0.sv`); drive its SPI from the IO controller, or replace it with a simpler character buffer |
| Cassette | IO controller streams a `.CAS` file as real 500/1500-baud pulses into the cassette input bit (port FF), so the unmodified ROM loads it; record captures the output bits to `.CAS`. Real tape keeps using GPIO (AUDIO_OUT, CASS_IN pins already in the top). | new |

OSD menu: Drive 0-3 (browse `/CP300/*.DSK`, mount, eject, write protect), Cassette (choose `.CAS`, Play, Stop, Record), Reset. Remember the mounts in `/CP300/CP300.CFG`. Mounting while running behaves like swapping a floppy: "not ready" briefly.

Disk images: start with raw images (40 or 80 tracks x 18 sectors x 256 bytes, 1 or 2 sides). Model III TRSDOS 1.3, DOS-500 and LDOS are double density on every track. Add `tools/dsk2raw.py` to convert JV3/DMK; native JV3 can come later in the firmware.

## Work plan, in order

1. **Model III I/O (phase 2), prerequisite for everything else.** In `rtl/ht1080z/ht1080z.vhd`:
   - Port E0 write = interrupt mask, read = interrupt status (active-low bits per the Model III Technical Reference Manual); 30 Hz timer interrupt (clear on read of status); connect T80 INT_n.
   - Port E4 write = NMI mask (bit 7 FDC INTRQ, bit 6 FDC motor timeout), read = NMI status; connect T80 NMI_n. The ROM's disk boot sets the NMI vector at 4049 (`JP 3502`) and expects INTRQ to end a sector read.
   - Port EC write: bit 1 cassette motor, bit 2 32-column mode (today `vcut` comes from a PS/2 hotkey in `ps2kbd.vhd`), bit 3 alternate character set (kana C0-FF: map to ROM C0-FF instead of 80-BF in `videoctrl.vhd`), bit 4 I/O bus enable, bit 5 video wait. Read EC resets the 30 Hz latch on the Model III.
   - Port FF: cassette out bits 0-1, cassette in bit 7; the 1500-baud cassette uses edge interrupts in E0 (bits 0-1).
   - CPU clock 2.0 MHz (CP-300) instead of 1.75: 42 MHz / 21 = 2.0 MHz in `clk42div`; check `clkref` (SDRAM pacing) still divides evenly.
   - Remove or isolate Model I leftovers: memory-mapped 37E0-37EF (now ROM), port 04 tape RAM, YM2149 at 1E/1F, ink/paper/border ports 00-02 in `videoctrl.vhd`.
   - Verify in GHDL: boot to "Cass?", answer A (needs a PS/2 key in the testbench, see below), "Mem. usada?", ENTER, and see the BASIC banner.
2. **IO controller + SD + OSD.** New `rtl/io/` with the second T80, ROM/RAM, an SPI master for the DE0 SD slot (pins in `FPGA_and_VHDL/DE0/DE0_CD-ROM_v.1.1/Demonstrations/DE0_TOP/DE0_TOP.qsf`: SD_CLK Y21, SD_CMD Y22, SD_DAT0 AA22, SD_DAT3 W21, SD_WP_N W20), registers for the FDC sector buffer, OSD and keyboard. Firmware in `firmware/` (SDCC, `C:\Apps\SDCC\bin`; SDCC 4.0.0 has an `a-b` codegen bug noted in the user's memory, check the version). Note: the DE0 SD slot is 3.3 V and SPI mode only.
3. **WD1793 + drive select.** Bring `wd1793.sv` in (keep its GPL header), RWMODE=1, size_code for 256-byte sectors, 18 sectors per track. Wire `img_mounted` / `img_size` and the `sd_*` interface to the IO controller. Test: boot a DOS from SD.
4. **Cassette.** `.CAS` playback as real pulses (TRS-80 Model III 500 baud and 1500 baud formats), then record. Real-tape path on CASS_IN / AUDIO_OUT (needs an external comparator / RC filter).
5. **On hardware.** Program the DE0 (`syn/de0/output_files/cp300_de0.sof` or `.pof`, see README), check VGA, keyboard, "Cass?", BASIC, then SD.

Phase 4 (FreHD-compatible hard disk, WD1010 at C8-CF) and phase 5 (original CP-300 keyboard on GPIO) are separate; see design-notes.md.

## Tools and how to verify

- ROMs: `python tools/mkroms.py` builds `roms/cp300_roms_pkg.vhd` from `roms/900-61..65.BIN` (not in git; copyrighted). Complete set: `C:\Users\roniv\Desktop\Retro\CP 300\cp-300_roms_4x2732_full.zip`. The older `cp-300_roms_4x2732_gc.zip` is incomplete (only the first 2 KB of each 2732); do not use it.
- Quartus: `/c/apps/altera/13.0sp1/quartus/bin64/quartus_sh --flow compile cp300_de0` in `syn/de0`. Check "Fitter Status : Successful" and that no slack in `output_files/cp300_de0.sta.summary` is negative.
- GHDL 6: `/c/apps/msys64/mingw64/bin` on PATH, then `GHDL=ghdl sh sim/run.sh 1600ms`. About 1000 times slower than the machine: 1 s of CP-300 time takes 15-20 minutes, so run it in the background and watch `sim/out/screen.txt` (rewritten every frame).
  - Trace: `TRACE_FROM_MS=1360 TRACE_MS=40 sh sim/run.sh 1400ms` logs every opcode fetch and memory write to `sim/out/trace.txt`.
  - `sim/tb_cp300.vhd` holds PS/2 idle; to answer prompts, add a PS/2 key sender (scan codes into ps2clk/ps2dat) or force the keyboard matrix.
  - The testbench runs with turbo on (3.5 MHz): the ROM's no-disk timeout is ~4.8M T-states (~2.4 s at 2 MHz on a real CP-300).
  - GHDL pitfalls met so far: signals without initial values stay 'U' (the FPGA powers up to 0), so give counters initial values; GHDL rejects YM2149's `work.vol_table` instantiation (sim uses `sim/ym2149_stub.vhd`); VHDL-2008 external names crashed GHDL 6 here, so sim-only probes live inside the RTL under `-- synthesis translate_off`.

## Facts found that matter for this work

- The ROM's disk boot (3455-3518): OUT E4,0; OUT EC; OUT F4,81 (drive 0); force interrupt D0; OUT E0,4; Restore 0B; then waits for Track 0 (F0 bit 2) with a 64K-loop timeout to 37AF ("Cass?"), checks index pulses (bit 1) five times, sets NMI vector 4049 = JP 3502, OUT E4,80, reads sector 1 of track 0 to 4300 with `INI` from F3 while F4 bit 6 (wait enable) holds the CPU until DRQ. The FDC emulation must support this wait-state mechanism (F4 bit 6 -> Z80 WAIT until DRQ or INTRQ).
- "Cass?" on this ROM takes A/B, not L/H. Banner "PROLOGICA 1981 BASIC", prompt "Mem. usada".
- 900-64's upper half holds "MONITOR VERSAO 1.1 1982 PROLOGICA"; the CPU cannot address it at 3800 (keyboard). How the CP-300 reaches it is open (the later single-27128 board has an OR gate CI-29 on A11).
- Schematics in the repo root (`cp300 original.pdf`, `cp300 limpo v02.tif`) are not committed and belong to another session's cleanup work (`docs/schematic/`). Do not commit or edit them.
