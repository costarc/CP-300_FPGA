# CP-300 FPGA

An FPGA recreation of the **Prológica CP-300**, the Brazilian TRS-80 Model III compatible computer (1983), for the **Terasic DE0** board (Cyclone III EP3C16F484C6).

It runs the original CP-300 ROM and boots TRS-80 Model III disk operating systems (TRSDOS 1.3, LDOS, NEWDOS/80, DOS-500 and others) from disk images on an **SD card**, with an on-screen menu to mount and swap the images. VGA output, PS/2 keyboard.

Other boards: Sipeed Tang Nano 9K / 20K (`syn/tangnano9k`, `syn/tangnano20k`, HDMI) and the **Analogue Pocket** (`syn/analogue`, on-screen keyboard and audio, [not yet compiled](syn/analogue/README.md)).

| | |
|---|---|
| CPU | Z80 at 2.0 MHz (T80), Model III memory map and I/O |
| ROM | the four CP-300 2732 EPROMs and the 900-65 character generator (you supply the dumps, see [roms/README.md](roms/README.md)) |
| Video | 64 x 16 text, 32-column mode, graphic blocks, kana set; 31 kHz VGA through the MiST scandoubler |
| Disks | WD1793 floppy controller, 4 drives, **DMK** images on the SD card, read and write |
| Interface | on-screen menu (F12), SD card (FAT16/FAT32, SPI), PS/2 keyboard and the original CP-300 keyboard matrix, RS-232 |

There was no existing Model III or CP-300 core, so this starts from the HT1080Z core ([mist-devel/ht1080z](https://github.com/mist-devel/ht1080z), a TRS-80 Model I for MiST) and converts it step by step. [docs/design-notes.md](docs/design-notes.md) has the reasoning and the Model III changes.

## Status

Works on a DE0: the ROM boots, the menu shows on the VGA picture, and TRSDOS 1.3 boots from a disk image on the SD card.

| Part | State |
|---|---|
| CP-300 ROM, video, PS/2 keyboard | done |
| Model III I/O: ports E0/E4/EC/FF, 30 Hz interrupt, NMI, 2.0 MHz | done |
| SD card, on-screen menu, disk mounting | done |
| Floppy controller WD1793, DMK images, read and write | done (no formatting: READ/WRITE TRACK) |
| Cassette (`.CAS` files from the SD card, record) | not started |
| Hard disk (FreHD-compatible WD1010 at C8-CF) | not started |
| Original CP-300 keyboard matrix on the GPIO header (3.3 V) | done in the design and in simulation, SHIFT + BREAK opens the menu; [not yet tested on a real keyboard](#original-cp-300-keyboard) |
| Sound | none (the HT1080Z sound chip was removed; only the tape port speaker bit remains) |

Resources: 7,359 of 15,408 logic elements (48%), 430,208 of 516,096 memory bits (83%), timing met at 42 MHz.

## Quick start

1. **ROMs.** The ROMs are not in the FPGA image: every board loads them from the SD card. Put a system ROM (`CP300.ROM`, `CP500.ROM`, `CP500P24.ROM`, `TRS80M3.ROM`) and `CHARGEN.BIN` in `/CP300` on the card ([Machines](#machines)). They are copyrighted and not part of this repository.
2. **Build** the FPGA image ([Building](#building-from-the-command-line)) or use a prebuilt `cp300_de0.sof` / `cp300_de0.pof`.
3. **Program the DE0:**
   - `cp300_de0.sof`: Quartus Programmer, mode JTAG. Lost at power-off. RUN/PROG switch on RUN.
   - `cp300_de0.pof`: Programmer mode "Active Serial Programming" into the EPCS4 flash, so the design loads at every power-on. RUN/PROG switch on PROG while programming, then back to RUN and power-cycle.
4. **SD card.** Format it FAT16 or FAT32. Create a folder `CP300` and copy disk images into it ([Disk images](#disk-images)). Optionally add a `CP300.CFG` of 512 bytes to remember the mounted disks.
5. **Connect** a VGA monitor and a PS/2 keyboard, put the card in the DE0 slot and power on.

The CP-300 stays in reset while the card is read, so the disks listed in `CP300.CFG` are mounted before the ROM boots. With no disk in Drive 0 the ROM goes to `Cass?` (cassette BASIC). With a bootable disk in Drive 0, the DOS starts.

## Using it

### On-screen menu

Press **F12** on the PS/2 keyboard, or **SHIFT + BREAK** on the original keyboard, to open or close the menu. While it is open both keyboards go to the menu, not to the CP-300. The CP-300 ROM treats SHIFT + BREAK as a plain BREAK, so nothing is lost; the BREAK of that chord is not passed on to the CP-300.

| PS/2 key | Original CP-300 key | Action |
|---|---|---|
| F12 | **SHIFT + BREAK** (either shift) | open or close the menu |
| Up / Down | UP / DOWN | move |
| PgUp / PgDn | LEFT / RIGHT | page through the file list |
| Enter | ENTER | select a menu item, or a file in the file list |
| Esc | BREAK | back / close |

The menu lists **Drive 0-3**, the **cassette** file (selection only, playback is not done yet), the **machine** (ROM file) and **Reset CP-300**. Choosing a drive shows the `*.DSK` files in `/CP300`; picking one mounts it at once, like swapping a floppy, and `(EJECT)` removes the disk. After mounting a boot disk in Drive 0, choose **Reset CP-300**.

To keep the selection across power-offs, create a 512-byte file `/CP300/CP300.CFG` (any content, for example 512 zero bytes). The menu then saves the selected names in it.

### Machines

The machine is the system ROM, a file in `/CP300` with the extension `.ROM` (16 KB, or 14 KB for a plain Model III ROM), plus its character generator (2 KB): the file with the same name and the extension `.CHR` (`CP500.ROM` loads `CP500.CHR`), or `CHARGEN.BIN` when there is none, so machines that share a character set need only one. They are read from the SD card into the core while it is held in reset, at power-on and at **Reset CP-300**. The menu item **MACHINE** lists the `*.ROM` files; picking one is saved in `CP300.CFG` and takes effect at the next reset. `(DEFAULT)` uses `CP300.ROM`, or else the first `.ROM` in the folder. Without a ROM the CP-300 stays in reset and the menu says why.

The file names, per platform (DE0 and Tang: `/CP300` on the SD card; Pocket: `Assets/cp300/common/`, where the two slots are picked in Core Settings and the defaults are `27C128cp300.BIN` and `2716cp300.BIN`):

| Machine | System ROM, source file | Character generator |
|---|---|---|
| CP-300 | `CP300.ROM` = `27C128cp300.BIN` | `CHARGEN.BIN` = `2716cp300.BIN` |
| CP-500 | `CP500.ROM` = `cp500.rom` (also `CP500M80_27128.bin`) | shared `CHARGEN.BIN` |
| CP-500 P24 / Turbo | `CP500P24.ROM` = `27c128.BIN` / `CP-500 Turbo 27128.Bin` (same file) | shared `CHARGEN.BIN` |
| TRS-80 Model III (14 KB, 0000-37FF) | `TRS80M3.ROM` | `TRS80M3.CHR` if its glyphs differ, else the shared one |

The BASIC ROM (0000-37FF) of the CP-300 and the CP-500 is the same code (the CP-500 P24 differs by two bytes at 01E1); the CP-500 differences are in the upper 2 KB, which the CPU cannot reach at 3800-3FFF. A genuine TRS-80 Model III ROM (14 KB, for example one built from [kiwisincebirth/TRS-80-ROMS](https://github.com/kiwisincebirth/TRS-80-ROMS)) uses the same hardware and should run as a `.ROM` file. The CP-500 M80's 80-column video board is not modelled.

### Disk images

Disk images are **DMK** files (David Keil's format, the common one for Model III and 4 emulators): copy them to `/CP300` with an **8.3 name** and the extension `.DSK` (the firmware does not read long file names). The controller finds sectors inside the DMK file, checks CRCs and writes changes back with correct CRCs. A DMK keeps sector IDs, single and double density tracks, deleted data marks and CRC errors as they were on the real disk. A file with the read-only attribute (or the write-protect byte of the DMK header) is write protected.

Only 256-byte sectors are read, which covers the Model III DOSes. Copy-protected disks may not work.

Other formats are converted to DMK with `tools/dsk2dmk.py` (JV1, JV3 and HFE input; a DMK is copied as it is):

```
python tools/dsk2dmk.py game.hfe /path/to/sd/CP300/GAME.DSK        one file
python tools/dsk2dmk.py DiskImages/ /path/to/sd/CP300              a whole folder, 8.3 names + INDEX.TXT
```

To run a BASIC program from a disk with TRSDOS 1.3: at `TRSDOS Ready` type `BASIC`, press Enter at `How many files?` and `Memory size?`, then `RUN"NAME/BAS"` (add `:1` after the name for a file in Drive 1).

### DE0 controls

| Control | Function |
|---|---|
| BUTTON0 | reset |
| SW0 | up = 50 Hz, down = 60 Hz (the CP-300 is PAL-M, 60 Hz) |
| SW1 | CPU turbo |
| SW3:2 | scanlines |
| SW4 | tape sounds |
| LEDG0 | CPU running (out of reset) |
| LEDG8:1 | IO controller: after start-up b0 card found, b1 `/CP300` found, b2 `CP300.CFG` found, b7:3 error code; then the last raw PS/2 byte |
| LEDG9 | PLL locked |
| GPIO0 J4 pins 22-40 | original CP-300 keyboard matrix, 3.3 V (see [Original CP-300 keyboard](#original-cp-300-keyboard)) |
| VGA | 31 kHz through the MiST scandoubler |
| PS/2 | keyboard |
| RS-232 | TRS-80 RS-232 at ports E8-EA, 9600 8N1 |
| GPIO0_D[0] | audio out (sigma-delta, add an RC filter) |
| GPIO0_D[1] | cassette in (reserved) |

The DE0's SD slot is used in SPI mode, 3.3 V (CLK Y21, CMD/MOSI Y22, DAT0/MISO AA22, DAT3/CS W21, WP W20).

### Original CP-300 keyboard

The original keyboard is a passive 8 x 8 switch matrix (no diodes). On the CP-300 board the row lines A0-A7 are driven by inverters from the CPU address lines and the column lines C0-C7 are pulled up to 5 V and read onto the data bus (D0-D7). The FPGA does that job itself, at **3.3 V**: it drives the eight row lines (low = selected, idle high), reads the eight column lines (pulled up to 3.3 V, a key pulls its column low), debounces about 5 ms and merges the keys with the PS/2 keyboard. Both keyboards work at the same time. **Never connect 5 V to these pins.**

Connector: the last nine pin pairs of the DE0 GPIO0 header (J4, pins 23-40, a 2 x 9 block), so one 18-pin ribbon plug is enough. Columns are on the odd pins, rows on the even pins, with 3.3 V and GND in the middle.

| J4 pin | GPIO0 | FPGA pin | Signal | CP-300 keyboard connector CN-5 |
|---|---|---|---|---|
| 22 | D15 | AA4 | reset key (optional, low = pressed) | |
| 23 | D16 | V14 | column C0 | pin 9 |
| 24 | D17 | U14 | row A0 | pin 1 |
| 25 | D18 | Y13 | column C1 | pin 10 |
| 26 | D19 | W13 | row A1 | pin 2 |
| 27 | D20 | U13 | column C2 | pin 11 |
| 28 | D21 | V12 | row A2 | pin 3 |
| 29 | | | **3.3 V** (pull-up supply) | |
| 30 | | | **GND** | |
| 31 | D22 | R10 | column C3 | pin 12 |
| 32 | D23 | V11 | row A3 | pin 4 |
| 33 | D24 | Y10 | column C4 | pin 13 |
| 34 | D25 | W10 | row A4 | pin 5 |
| 35 | D26 | T8 | column C5 | pin 14 |
| 36 | D27 | V8 | row A5 | pin 6 |
| 37 | D28 | W7 | column C6 | pin 15 |
| 38 | D29 | W6 | row A6 | pin 7 |
| 39 | D30 | V5 | column C7 | pin 16 |
| 40 | D31 | U7 | row A7 | pin 8 |

The same, from the keyboard connector side (the CP-300 board's CN-5 has the eight rows on pins 1-8 and the eight columns on pins 9-16; the numbers are read from the schematic, so check them against your keyboard cable with a multimeter before plugging it in):

| CN-5 pin | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Signal | A0 | A1 | A2 | A3 | A4 | A5 | A6 | A7 | C0 | C1 | C2 | C3 | C4 | C5 | C6 | C7 |
| DE0 J4 pin | 24 | 26 | 28 | 32 | 34 | 36 | 38 | 40 | 23 | 25 | 27 | 31 | 33 | 35 | 37 | 39 |

Optional: pin 22 (GPIO0_D15, AA4) is a reset input, low = pressed, with a pull-up. Connect the keyboard's reset key(s) between it and GND (pin 12 or 30); it acts like BUTTON0.

The columns have the FPGA's weak internal pull-ups (about 25 kOhm), which is enough for a short cable. For a longer cable add a 4.7 kOhm to 10 kOhm resistor from each column to the 3.3 V on pin 29. The row and column resistors and inverters on the CP-300 board are not used; wire only the keyboard itself (the key matrix) to the plug.

The keys (row = address line, column = data bit, as printed on the schematic):

| Row | C0 | C1 | C2 | C3 | C4 | C5 | C6 | C7 |
|---|---|---|---|---|---|---|---|---|
| A0 | @ | A | B | C | D | E | F | G |
| A1 | H | I | J | K | L | M | N | O |
| A2 | P | Q | R | S | T | U | V | W |
| A3 | X | Y | Z | | | | | |
| A4 | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
| A5 | 8 | 9 | : | ; | , | - | . | / |
| A6 | ENTER | CLEAR | BREAK | UP | DOWN | LEFT | RIGHT | SPACE |
| A7 | L SHIFT | R SHIFT | | | | | | |

The original keyboard has no F12 key; **SHIFT + BREAK** opens the menu, and UP, DOWN, LEFT, RIGHT, ENTER and BREAK move around in it (table above). A PS/2 keyboard is not needed.

## Building from the command line

### What you need

| Tool | Version | Used for |
|---|---|---|
| Quartus II Web Edition | 13.0sp1 (free, supports Cyclone III) | synthesis, place and route |
| Python | 3 | ROM package, disk tools |
| SDCC | **4.6** (the build stops on any other version) | IO controller firmware (Z80, native `--sdcccall 1`) |
| GHDL | 6 | simulation (optional) |
| gcc | any | PC tests of the firmware (optional) |
| git | | clone with submodules |

On Windows use Git Bash (or MSYS2) for the shell scripts.

### One command

```
git clone --recurse-submodules <this repository>
cd CP-300_FPGA
# put the ROM dumps in roms/ first
./build.sh                 # roms + firmware + fpga
```

`build.sh` takes one or more steps: `roms`, `firmware`, `fpga`, `test` (default: `all` = roms firmware fpga).

| Step | What it runs | Output |
|---|---|---|
| `roms` | `python tools/mkroms.py` | `roms/cp300_roms_pkg.vhd` (not committed) |
| `firmware` | `sh firmware/build.sh` (SDCC) | `rtl/io/io_fw_pkg.vhd`, the 16 KB ROM of the IO controller (commit it together with the C changes) |
| `fpga` | `quartus_sh --flow compile cp300_de0` in `syn/de0` | `syn/de0/output_files/cp300_de0.sof` and `cp300_de0.pof` |
| `test` | disk converter and FAT tests | |

The `fpga` step prints the fitter result and the worst timing slack, and fails if timing is not met. A full compile takes 1 to 3 minutes. The tools are found on the `PATH`; otherwise set `QUARTUS_BIN` (the folder with `quartus_sh`) and `SDCC_BIN` (the folder with `sdcc`).

### The steps by hand

```
python tools/mkroms.py
sh firmware/build.sh
cd syn/de0
quartus_sh --flow compile cp300_de0
```

Load the `.sof` over JTAG from the command line (the `.pof` is easiest with the Quartus Programmer, see Quick start):

```
quartus_pgm -c USB-Blaster -m JTAG -o "p;output_files/cp300_de0.sof"
```

### Simulation and tests

All simulations use GHDL and write their results to `sim/out/` (not committed). GHDL is about 1000 times slower than the real machine: a simulated second takes 15 to 20 minutes.

| Command | What it does |
|---|---|
| `sh sim/run.sh 1500ms` | the core alone: the ROM boots to `Cass?` (the screen of the last frame is printed) |
| `sh sim/run_io.sh` | the IO controller with its real firmware, an SD card model and PS/2 keys; writes the menu as `sim/out/osd_<n>.pbm` pictures |
| `sh sim/run_sys.sh 600ms` | the whole machine boots a DMK disk from the SD card model; the boot sector prints `BOOT OK`, then `FDC OK` after a seek, read, write and read-back test |
| `sh sim/run_kbd.sh` | the original keyboard matrix scanner against a model of the switch matrix: scanning, two and three keys at once, debounce, and what the CPU reads at 3800h with the PS/2 keyboard merged |
| `./build.sh test` | PC tests: the DMK converter and the FAT code |
| `python tools/test_dmk.py a.dmk b.dmk` | checks the firmware's DMK reader against the converter's own decoder on real images (needs gcc) |

`sim/run_io.sh` and `sim/run_sys.sh` need a card image: `python tools/mkfat.py sim/out/card.img --clusters 4200 --spc 1`. `sim/run_sys.sh` can also type on the simulated keyboard from a script, `sim/out/keys.txt` (the commands are described in `sim/tb_sys.vhd`).

## Repository layout

```
build.sh         command line build (roms, firmware, fpga, test)
rtl/de0/         DE0 top level, 50 -> 42 MHz PLL
rtl/cp300/       the system ROM (four 2732 EPROM images)
rtl/ht1080z/     the core: Z80 system, video, keyboard (vendored from mist-devel/ht1080z, modified)
rtl/fdc/         WD1793 floppy controller (VHDL)
rtl/kbd/         scanner for the original CP-300 keyboard matrix
rtl/io/          IO controller: a second Z80 with SD card, OSD menu, PS/2 and the floppy sector service
rtl/T80/         submodule: mist-devel/T80 (Z80 core)
rtl/mist-modules submodule: mist-devel/mist-modules (scandoubler, OSD)
firmware/        C firmware of the IO controller (SDCC): SD card, FAT, DMK images, menu
firmware/tests/  PC tests of the firmware code
syn/de0/         Quartus II 13.0sp1 project
syn/analogue/    Analogue Pocket (openFPGA) core: Quartus Prime project, JSON definition files, firmware port in firmware/pocket
sim/             GHDL testbenches and scripts
roms/            CP-300 ROM dumps (not committed)
tools/           mkroms, mkfw, mkfat, dsk2dmk and their tests
docs/            design notes
```

How the pieces fit: the Z80 core and the video run at the CP-300's own speed. A second Z80, the IO controller, runs a small C program from an on-chip ROM. It reads the SD card over SPI, draws the menu through the MiST OSD, reads the PS/2 keyboard while the menu is open, and answers the floppy controller's requests for sectors by looking them up in the mounted DMK file.

Changes to vendored files:

- `sdram.v`: rows/columns for the DE0's 4096 x 256 SDRAM (MiST has 512 columns).
- `ht1080z.vhd`: Model III ports and interrupts, WD1793 at F0-F3, drive select latch at F4 with wait states, 2.0 MHz clock; system ROM from the on-chip EPROM images (CP-300 decoder CI-44).
- `videoctrl.vhd`: CP-300 character generator (900-65), 8-dot cells, 512 active pixels, 2x3 graphic blocks, kana set (port EC).

## Known limitations

- No formatting of disks (WRITE TRACK / READ TRACK) and no 3 s motor timeout.
- Only 256-byte sectors; copy-protected disks may not work.
- No cassette playback or recording yet.
- No sound chip.
- File names on the SD card are 8.3 only.

## Licence and credits

GPL-3.0 (see [LICENSE](LICENSE)). The vendored files keep their own headers:

- `ht1080z.vhd` and the HT1080Z core: Jozsef Laszlo (BSD-style).
- `sdram.v`: Till Harbaum (GPL-3.0).
- T80 and mist-modules: their own licences (MiST project).
- `rtl/fdc/wd1793.vhd`: VHDL port of the WD1793 replica by Viacheslav Slavinsky and Sorgelig, with the 18 x 256 modification by Stan Hodge (GPL-2.0-or-later).
- DMK format: David Keil. JV1/JV3: Jeff Vavasour.

The CP-300 ROMs and the disk operating systems are copyrighted and are not included.
