# Design notes

## Why HT1080Z

No public FPGA core exists for the TRS-80 Model III, Model 4, CP-300 or CP-500. The available Model I cores were compared:

| Core | Machine | FPGA / tools | Storage | Notes |
|---|---|---|---|---|
| [mist-devel/ht1080z](https://github.com/mist-devel/ht1080z) | Model I / HT-1080Z | Cyclone III, Quartus | Via MiST ARM (ROM, CAS) | T80, SDRAM controller, PS/2 matrix, video, RS-232. Chosen. |
| [HT1080Z_MiSTer](https://github.com/MiSTer-devel/HT1080Z_MiSTer) | Model I | Cyclone V, HPS | JV1 floppies through the HPS, no Write Track | Reference for disk and keyboard mapping |
| [Big-80](https://github.com/toptensoftware/big80) | Model I | Spartan-6, ISE | FAT on SD via a firmware CPU (CAS only) | MIT/Apache; reference for an on-chip SD/menu controller |
| [maboytim adapter](https://github.com/maboytim/TRS-80_Model3-4_Keyboard-Display-Adapter) | Model III/4 keyboard + video | Tang Nano 9K | - | Public domain; reference for Model III video and keyboard |

The MiST board uses the same FPGA family as the DE0, so the PLL, SDRAM controller and video pipeline carry over. What MiST's ARM controller did (loading the ROM, the OSD, SD card access) has to be replaced on the DE0.

## DE0 resources

- EP3C16: 15,408 LEs, 56 M9K blocks (about 56 KB as 8-bit memory).
- On-chip: ROM image (14 KB, copied to SDRAM at power-up), video RAM (1 KB), character generator (2 KB).
- 8 MB SDRAM (1M x 16 x 4 banks): Z80 RAM and ROM copy.
- SD socket (SPI mode), PS/2, 4-bit VGA, RS-232, two 40-pin GPIO headers. No audio: audio goes out of a GPIO pin through a sigma-delta DAC.

## Phase 2: Model I -> Model III / CP-300

Reference: TRS-80 Model III Technical Reference Manual; xtrs / sdltrs source.

| Item | Model I (HT1080Z today) | Model III / CP-300 |
|---|---|---|
| CPU clock | 1.77 MHz | 2.03 MHz (CP-300: 2.0 MHz) |
| ROM | 0000-2FFF (12 KB) | 0000-37FF (14 KB) |
| Keyboard | 3800-3BFF | 3800-3BFF (same matrix layout, check CP-300) |
| Video RAM | 3C00-3FFF | 3C00-3FFF, 32/64 columns selected by port EC |
| RAM | 4000-FFFF | 4000-FFFF (CP-300 states 64 KB: check for RAM under the ROM) |
| Timer interrupt | 40 Hz, memory-mapped at 37E0 | 30 Hz, IM 1, mask/status on port E0 |
| NMI | - | Port E4 (FDC interrupts) |
| Misc control | - | Port EC: cassette motor, 32-column mode, alternate character set |
| Floppy controller | Memory-mapped 37E0-37EF (WD1771) | Ports F0-F4 (WD1793) |
| Printer | 37E8 | Port F8 |
| Cassette | Port FF, 500 baud | Port FF, 500/1500 baud (1500 uses edge interrupts) |

### CP-300 ROMs (done)

From the board schematic ("Esquema elétrico da placa Prológica 10", rev 2.3) and the dumps of the user's board:

- The board predates revision 2.3 (25-11-83, "eliminado CI's 29-30-31"), so the system ROM is four 2732 EPROMs, CI-28..31: 900-61 (0000), 900-62 (1000), 900-63 (2000), 900-64 (3000). Later boards use one 27128. The contents are a TRS-80 Model III ROM (starts F3 AF C3 15 30).
- Decoder CI-44 (74139): the 2Y outputs pick the EPROM with A13:A12. 2Y3 enables the second half, whose outputs are ROM (3000-37FF), keyboard 3800 ("TECLADO") and video RAM 3C00. So only the lower 2 KB of 900-64 is reachable (3000-37FF).
- Port F0-F7 (floppy controller) read 00 until the FDC exists. The ROM sends Restore and waits for the Track-0 status bit with a 64K-loop timeout (about 2.7 s at 1.77 MHz), then prints "Cass?". With FF it sees Track 0 at once and waits forever for a boot sector. A CP-300 without the SM-300 disk unit reaches "Cass?", so its F0 must read with bit 2 clear.
- This ROM is Prológica's: "PROLOGICA 1981 BASIC", "Mem. usada", and "Cass?" takes A/B (not L/H).

### Boot simulation

`sim/run.sh` (GHDL) runs the core with the ROMs and prints the screen; `TRACE_FROM_MS` / `TRACE_MS` log every opcode fetch and memory write to `sim/out/trace.txt`. With the current dumps the ROM initialises the Model III I/O, times out on the disk check, and at 1.39 s (turbo) goes to the "Cass?" path. There it executes RST 18 → 4006 → JP 1C90, but 1C90 holds a copy of 1490 (floating-point constants) because 900-62 was dumped with A11 stuck. The CPU then runs data and the stack overwrites video RAM. 900-61 has the same problem. Re-dump both as 2732s.
- In the FPGA (`rtl/cp300/cp300_rom.vhd`) each EPROM is its own M9K ROM, selected the same way. The CPU reads them directly; MiST's ROM download into SDRAM is gone.
- Character generator CI-59 (2716, 900-65): A0-A2 = scan line, A3-A10 = character code. Its outputs load the 74166 shift register CI-57 (bit 7 first), so cells are 8 dots wide: 64 x 8 = 512 dots per line. Glyphs use scan lines 0-7 of the 12-line row. 80-BF come from the graphics mux CI-58 as 2x3 blocks of 4 dots x 4 lines.
- Codes C0-FF: the ROM holds special symbols at 80-BF and katakana at C0-FF. On the Model III the choice is made through port EC. Until that port exists, C0-FF show the special symbols.

Still to confirm:

- "64 KB RAM, 16 KB ROM" in the specs: 14 KB system ROM + 2 KB character generator matches; 16 KB of RAM under the ROM for CP/M (SO-08) is not confirmed.
- The expansion connector: Prológica removed the parallel, serial and disk circuits but kept the signals (Fabio Belavenuto's analysis in the cp-500 Google group).

## Phases 3-4: storage on SD

1. **Floppy controller** at F0-F4 with disk images (JV1/JV3 or DMK) on the SD card. The unmodified ROM then boots DOS-500, TRSDOS 1.3, LDOS or NEWDOS/80 as from an SM-300 disk unit.
2. **Hard disk**: the WD1010 register set at C8-CF, the interface FreHD emulates, so existing hard-disk drivers work (FreHD reports TRSDOS 6, LS-DOS 6.3.1 and LDOS 5 on Model III/4). Target: LDOS 5.3.1 on a hard-disk image.
3. **SD access**: a small helper CPU inside the FPGA (a second T80 with its own firmware in M9K) handles FAT, image selection and an on-screen menu, replacing the MiST ARM. A first step without the helper CPU can map hard-disk sectors to raw SD blocks in HDL.

Booting from the hard disk needs either a floppy image to boot from or a ROM boot hook (the FreHD auto-boot approach). To be decided in phase 4.

## Phase 5: keyboards

- Original keyboard on a GPIO header: 8 rows + 8 columns + the two red reset keys, with series resistors. The DE0 pins are 3.3 V; a passive matrix works at that level. Check the CP-300 schematic for matrix diodes and the row/column map first.
- Scan the physical matrix continuously with debounce into an 8 x 8 register, and AND it (active low) with the PS/2 matrix. The CPU reads the merged matrix at 3800h, so the physical keyboard timing is decoupled from the Z80 bus.
- Both red keys together drive reset.
- PS/2 keeps HT1080Z's mapping; add a "PC" mode that fakes the shift state for symbols that differ from the TRS-80 layout, as the MiSTer core does.

## Sources

- [CP-300 (Wikipedia)](https://en.wikipedia.org/wiki/CP-300)
- [CP-300 expansion port thread (cp-500 group)](https://groups.google.com/g/cp-500/c/KCyNUfypTg8/m/uTT8C5FJ_OUJ)
- [FreHD](https://vecoven.com/trs80/trs80.html), [trs-80.com hard drive page](https://trs-80.com/sub-repairs-parts-hard-drive.htm), [FreHDDisk](https://github.com/TJBChris/FreHDDisk)
- [xtrs trs_hard.c](https://sources.debian.org/src/xtrs/4.9-5/trs_hard.c)
- DE0 User Manual (Terasic)
