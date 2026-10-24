# CP-300 FPGA

An FPGA recreation of the **Prológica CP-300** (a Brazilian TRS-80 Model III compatible, 1983) for the **Terasic DE0** (Cyclone III EP3C16F484C6).

Goals:

- Behave like a real CP-300: Model III memory map and I/O, 2.0 MHz Z80, CP-300 ROM and character set.
- Run TRS-80 Model III operating systems (DOS-500, TRSDOS 1.3, LDOS 5.3.1, NEWDOS/80) from an **SD card**.
- Accept both the **original CP-300 keyboard** (on a GPIO header) and a **PS/2 keyboard**.

There was no existing Model III or CP-300 core, so this starts from the HT1080Z core ([mist-devel/ht1080z](https://github.com/mist-devel/ht1080z), a TRS-80 Model I / HT-1080Z for MiST, also Cyclone III) and converts it step by step. See [docs/design-notes.md](docs/design-notes.md) for the reasoning and the Model III changes.

## Status

| Phase | Work | Status |
|---|---|---|
| 1 | HT1080Z (Model I) running stand-alone on the DE0 | Compiles, not tested on hardware |
| 2a | CP-300 ROMs: four 2732 EPROMs + character generator, CP-300 video | Done; boots to "Cass?" in simulation, not tested on hardware |
| 2 | Model III / CP-300 I/O (ports E0/E4/EC, 30 Hz interrupt, 2.0 MHz) | Not started |
| 3 | Floppy controller (WD1793, ports F0-F4) with disk images on SD | Not started |
| 4 | Hard disk (WD1010, ports C8-CF, FreHD-compatible drivers) on SD | Not started |
| 5 | Original CP-300 keyboard on GPIO, merged with PS/2 | Not started |

## Layout

```
rtl/de0/         DE0 top level, 50->42 MHz PLL
rtl/cp300/       CP-300 specific blocks (system ROM: four 2732 EPROMs)
rtl/ht1080z/     core files vendored from mist-devel/ht1080z @ ba57e3c (modified here)
rtl/T80/         submodule: mist-devel/T80 (Z80 core)
rtl/mist-modules submodule: mist-devel/mist-modules (scandoubler / video only)
syn/de0/         Quartus II 13.0sp1 project
sim/             GHDL boot simulation
roms/            CP-300 ROM dumps (not committed)
tools/           mkroms.py
docs/            design notes
```

Changes to vendored files:

- `sdram.v`: rows/columns for the DE0's 4096 x 256 SDRAM (MiST has 512 columns).
- `ht1080z.vhd`: system ROM read from the four on-chip EPROM images at 0000-37FF (CP-300 decoder CI-44) instead of SDRAM; video RAM codes 00-1F stored as written.
- `videoctrl.vhd`: CP-300 character generator (900-65), 8-dot cells, 512 active pixels, 2x3 graphic blocks generated in logic.

## Build

The ROM dumps from a CP-300 board (see [roms/README.md](roms/README.md)) go in `roms/`, then:

```
git clone --recurse-submodules <this repo>
python tools/mkroms.py
quartus_sh --flow compile syn/de0/cp300_de0
```

The build writes two files in `syn/de0/output_files/`:

- `cp300_de0.sof`: load into the FPGA (JTAG, lost at power-off). DE0 RUN/PROG switch on RUN, Quartus Programmer mode "JTAG".
- `cp300_de0.pof`: write to the DE0's EPCS4 configuration flash so the design loads at every power-on. RUN/PROG switch on PROG, Programmer mode "Active Serial Programming", tick Program/Configure, Start; then set the switch back to RUN and power-cycle.

Boot simulation (GHDL 6, prints the screen of the last frame):

```
sh sim/run.sh 1500ms
```

## SD card and on-screen menu (IO controller)

A second Z80 inside the FPGA (`rtl/io/io_ctrl.vhd`, firmware in `firmware/`) reads the SD
card, draws the menu through the MiST OSD and reads the PS/2 keyboard while the menu is open.
Format the card FAT16 or FAT32 and create `/CP300` with the `*.DSK` and `*.CAS` files.
Optionally put a 512-byte `CP300.CFG` there; the selected files are saved in it.

- **F12** opens or closes the menu; Up/Down, Enter, Esc, PgUp/PgDn move around. The CP-300
  does not see the keys while the menu is open.
- The menu lists Drive 0-3, the cassette file and a CP-300 reset. Choosing a file for a drive
  mounts it at once (a floppy swap); the cassette player is the next step. The CP-300 is held in
  reset while the card is read, so the disks in `CP300.CFG` are mounted before the ROM boots.

## Floppy controller

`rtl/fdc/wd1793.vhd` is a WD1793 replica (VHDL port of the Slavinsky / Sorgelig core, GPL) at
ports F0-F3; F4 is the drive select latch (bits 0-3 drive, 4 side, 6 wait enable). INTRQ goes to
NMI through port E4 and a data register access (F3) waits for DRQ or INTRQ when F4 bit 6 is set.
The IO controller serves 512-byte blocks of the disk image from the SD card.

- Disk images are **DMK** files (David Keil's format, the usual one for Model III / 4 emulators): put
  them in `/CP300` with an 8.3 name and the extension `.DSK`. The IO controller finds the sector inside
  the DMK file, checks its CRC and writes changes back with a correct CRC, so sector IDs, single and
  double density tracks, deleted data marks and CRC errors are kept as they are on the disk.
  A file with the read-only attribute (or the write protect byte of the DMK header) is write protected.
  Only 256-byte sectors are read; one DMK track holds 6400 bytes.
- `tools/dsk2dmk.py` converts JV1, JV3 and HFE images to DMK (a DMK is copied as it is), one file or a
  whole folder at once, with 8.3 names and an `INDEX.TXT`: `python tools/dsk2dmk.py D:\DiskImages D:\CP300`.
  `tools/test_dsk2dmk.py` is its self-test and `tools/test_dmk.py` checks the firmware's DMK reader
  against the converter's decoder on real images.
- Supported: RESTORE, SEEK, STEP, READ/WRITE SECTOR (also multiple), READ ADDRESS, FORCE
  INTERRUPT. Not supported: READ TRACK and WRITE TRACK (formatting a disk), the 3 s motor timeout.
- `sim/run_sys.sh` boots the whole machine in GHDL from a card image (`tools/mkfat.py` builds one
  with a DMK disk, single density track 0 and double density sectors counted from 0, whose boot
  sector tests SEEK, READ and WRITE and prints "BOOT OK" / "FDC OK" on the screen).
- Firmware: `firmware/build.sh` (SDCC 4.6.0) rebuilds `rtl/io/io_fw_pkg.vhd`; commit both.
- Tests: `firmware/tests/host_fat.c` (FAT code on the PC against `tools/mkfat.py` images) and
  `sim/run_io.sh` (the real firmware in GHDL with an SD card model, writes `sim/out/osd_*.pbm`).

## DE0 controls

| Control | Function |
|---|---|
| BUTTON0 | Reset |
| SW0 | Up = 50 Hz, down = 60 Hz (the CP-300 is PAL-M, 60 Hz) |
| SW1 | CPU turbo |
| SW3:2 | Scanlines |
| SW4 | Tape sounds |
| LEDG0 / LEDG9 | CPU running (out of reset) / PLL locked |
| VGA | 31 kHz through the MiST scandoubler |
| PS/2 | Keyboard |
| RS-232 | TRS-80 RS-232 at ports E8-EA, 9600 8N1 |
| GPIO0_D[0] (AUDIO_OUT) | Audio out (sigma-delta, add an RC filter) |
| GPIO0_D[1] (CASS_IN) | Cassette in (reserved) |

## Licence

GPL-3.0 (see [LICENSE](LICENSE)). The vendored files keep their own headers: `ht1080z.vhd` is BSD-style (Jozsef Laszlo), `sdram.v` is GPL-3.0 (Till Harbaum), T80 and mist-modules carry their own licences.
