# CP-300 FPGA

An FPGA recreation of the **Prológica CP-300**, the Brazilian TRS-80 Model III compatible computer (1983).

It runs the original CP-300 ROM and boots TRS-80 Model III disk operating systems (TRSDOS 1.3, LDOS, NEWDOS/80, DOS-500 and others)
from **DMK** disk images. The same core runs on the Terasic DE0, the Analogue Pocket, the BeagleV-Fire (in a web browser), the MiSTer
and the Sipeed Tang Nano 9K / 20K.

## Ports

One core, several boards. Each port folder has its own README with the wiring, the build and the status.

| Board | Folder | Screen, keyboard, disks | Status |
|---|---|---|---|
| **Terasic DE0** (Cyclone III) | [`syn/de0`](syn/de0/README.md) | VGA, PS/2 and the original CP-300 keyboard, SD card, on-screen menu | **Works** (tested on a board) |
| **Analogue Pocket** (Cyclone V) | [`syn/analogue`](syn/analogue/README.md) | the Pocket's screen, on-screen keyboard, audio, disks from the Core Settings menu | **Works** on a Pocket. The newest SD-card speed changes are not yet re-tested on hardware |
| **BeagleV-Fire** (PolarFire SoC, RISC-V Linux) | [`syn/beaglev-fire`](syn/beaglev-fire/README.md) | **in a web browser**: screen, keyboard, sound, four disk drives | **Works** on the author's board. Installable [package](syn/beaglev-fire/releases) with an installer |
| **MiSTer** (DE10-Nano) | [`syn/mister`](syn/mister/README.md) | the MiSTer framework (HDMI/VGA), USB keyboard, SD card, OSD | Compiles. Tested on a MiSTer |
| **Sipeed Tang Nano 9K** and **20K** (Gowin) | [`syn/tangnano9k`](syn/tangnano9k/README.md), [`syn/tangnano20k`](syn/tangnano20k/README.md) | HDMI (640x480), SD card, on-screen menu; the 20K build is limited to what a 9K has | Synthesises and meets timing in the Gowin tools, the frame buffer path passes its simulation. Not tried on a board |

"Works" means the ROM boots and a DOS boots from a disk image on the real board, checked by the author. The other ports are
code that has not met its hardware yet: expect to find problems.

### BeagleV-Fire in short

The design is written up as a technical paper: [docs/beaglev-fire-technical-paper.md](docs/beaglev-fire-technical-paper.md).

The BeagleV-Fire has no video output, so the **browser is the monitor, keyboard, speaker and disk drive**: the CP-300 runs in the
FPGA fabric, a small Python daemon on the board's Linux serves a web page. `syn/beaglev-fire/releases/` holds the installable
package (`cp300-beaglev-fire-<version>.tar.gz`): `sudo ./install.sh` installs the software, adds the CP-300 to the board's web
server and to Cockpit, and flashes the gateware. **Flashing rewrites the board's bootloader and can leave the board unable to
start: read the disclaimer in the package and in the [port README](syn/beaglev-fire/README.md) first.**

## The machine

The figures are those of the DE0 build; the other ports differ in video, input and disks.

| | |
|---|---|
| CPU | Z80 at 2.0 MHz (T80), Model III memory map and I/O |
| ROM | the four CP-300 2732 EPROMs and the 900-65 character generator (you supply the dumps, see [roms/README.md](roms/README.md)) |
| Video | 64 x 16 text, 32-column mode, graphic blocks, kana set; 31 kHz VGA through the MiST scandoubler |
| Disks | WD1793 floppy controller, 4 drives, **DMK** images on the SD card, read and write; **FreeHD** hard disk interface (ports C0-CF), 2 drives, **HDV** images |
| Interface | on-screen menu (F12), SD card (FAT16/FAT32, SPI), PS/2 keyboard and the original CP-300 keyboard matrix, RS-232 |

There was no existing Model III or CP-300 core, so this starts from the HT1080Z core ([mist-devel/ht1080z](https://github.com/mist-devel/ht1080z), a TRS-80 Model I for MiST) and converts it step by step. [docs/design-notes.md](docs/design-notes.md) has the reasoning and the Model III changes.

## ROMs, machines and disk images

The ROMs and the disk operating systems are copyrighted and **not part of this repository**. Every port loads the ROMs at run time (from the SD card, the Pocket's assets folder, the MiSTer's `games` folder, or the browser page); none is in a bitstream. See [roms/README.md](roms/README.md) for the file names and the dumps.

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

### Hard disks (FreeHD)

Version 0.3.0 adds the hard disk interface the TRS-80 community knows as **FreeHD / FreHD** (a Radio Shack style WD1010 controller at ports `C0`-`CF`, the same one the xtrs emulator and Matthew Reed's emulators provide). Two hard disks, each an **`.HDV`** image: a 256-byte header (`56 CB 10 ...`, the format of xtrs and TRS32) followed by 256-byte sectors, 32 per track. Images made for xtrs, TRS32 or a real FreHD card's SD work as they are; cylinders, heads and the write-protect flag come from the header.

| Port | |
|---|---|
| `C0` | read: write protect, bits 7-4 for drives 0-3 |
| `C1` | control: bit 4 reset, bit 3 enable |
| `C8`-`CF` | WD1010: data, error, sector count, sector number, cylinder low / high, size-drive-head, status / command |

Supported commands: RESTORE, SEEK, VERIFY, READ SECTOR and WRITE SECTOR (one 256-byte sector; no multi-sector, DMA or FORMAT TRACK - FORMAT and INIT just report done, as in xtrs). `python tools/mkhdv.py my.hdv` makes an empty image (default 153 cylinders x 4 heads = 5 MB, the Radio Shack drive; up to 256 x 8 = 16 MB); format it from the operating system (LDOS / LS-DOS `FORMAT`), which only writes the directory. The ports answer only while a hard disk image is mounted; with none, reads return `FF` as an empty bus does, so a machine without a hard disk behaves exactly as before.

The CP-300 ROMs cannot boot from a hard disk: boot a floppy that carries the hard disk driver (LDOS 5.3 / LS-DOS 6, TRSDOS 6 or NEWDOS/80 configured for the FreeHD ports) and use the hard disk from there, as with a real FreHD.

| Port | Where the images come from |
|---|---|
| DE0, Tang Nano | `/CP300/NAME.HDV` on the SD card; OSD menu items **HD0** and **HD1** |
| Analogue Pocket | Core Settings -> **Hard disk 0 / 1 (FreeHD)**, a file from `Assets/cp300/common` |
| MiSTer | OSD **Hard disk 0 / 1**, `.HDV` files in `games/CP-300` |
| BeagleV-Fire | upload in the browser page (daemon API `PUT /api/hd/0` and `/api/hd/1`) |

How it works: `rtl/hdc/wd1010.vhd` is the controller (registers, a 256-byte buffer); like the floppy controller it does not know the image format and asks the IO controller for the sector by (drive, cylinder, head, sector). The request travels over the floppy controller's service path (flag bit 7 of port `10` says whom it is for), so every port needed only two new signals.

### Reset clears the screen

A reset (power-on, the menu's **Reset CP-300**) now clears the video RAM to spaces, as the real machine does; before, the old text stayed under the boot output. `rtl/ht1080z/videoctrl.vhd` fills the 1 KB while the core is held in reset (which now lasts 2047 clocks, 49 us); `sim/tb_vclr.vhd` checks it.

### Version

The core version is in [VERSION](VERSION) (also `syn/analogue/core.json`). 0.3.0: FreeHD hard disk interface, reset clears the screen, data slot change reports made reliable on the Pocket. 0.2.0: BeagleV-Fire package. 0.1.0: first Pocket release.

## Simulation and tests

All simulations use GHDL and write their results to `sim/out/` (not committed). GHDL is about 1000 times slower than the real machine: a simulated second takes 15 to 20 minutes.

| Command | What it does |
|---|---|
| `sh sim/run.sh 1500ms` | the core alone: the ROM boots to `Cass?` (the screen of the last frame is printed) |
| `sh sim/run_io.sh` | the IO controller with its real firmware, an SD card model and PS/2 keys; writes the menu as `sim/out/osd_<n>.pbm` pictures |
| `sh sim/run_sys.sh 600ms` | the whole machine boots a DMK disk from the SD card model; the boot sector prints `BOOT OK`, then `FDC OK` after a seek, read, write and read-back test |
| `python tools/mkfat.py sim/out/card.img --clusters 4200 --spc 1 --boot HDBOOT`, then `sh sim/run_sys.sh` | the same with a boot sector that tests the FreeHD ports on a `.HDV` image (even and odd sectors, read, write, read back); prints `HD OK` |
| `sh sim/run_kbd.sh` | the original keyboard matrix scanner against a model of the switch matrix: scanning, two and three keys at once, debounce, and what the CPU reads at 3800h with the PS/2 keyboard merged |
| `sh sim/run_hdc.sh` | the FreeHD controller alone with a behavioural IO controller: READ and WRITE SECTOR with multi-clock Z80 I/O cycles, status and error codes, write protect, missing drive (seconds) |
| `./build.sh test` | PC tests: the DMK converter and the FAT code |
| `python tools/test_dmk.py a.dmk b.dmk` | checks the firmware's DMK reader against the converter's own decoder on real images (needs gcc) |

`sim/run_io.sh` and `sim/run_sys.sh` need a card image: `python tools/mkfat.py sim/out/card.img --clusters 4200 --spc 1`. `sim/run_sys.sh` can also type on the simulated keyboard from a script, `sim/out/keys.txt` (the commands are described in `sim/tb_sys.vhd`).

## Repository layout

```
build.sh         command line build of the DE0 (roms, firmware, fpga, test)
rtl/de0/         DE0 top level, 50 -> 42 MHz PLL
rtl/tang/        shared board layer of the Tang Nano 9K and 20K (frame buffer in RAM, HDMI)
rtl/cp300/       the system ROM (four 2732 EPROM images)
rtl/ht1080z/     the core: Z80 system, video, keyboard (vendored from mist-devel/ht1080z, modified)
rtl/fdc/         WD1793 floppy controller (VHDL)
rtl/hdc/         WD1010 / FreeHD hard disk controller (VHDL)
rtl/kbd/         scanner for the original CP-300 keyboard matrix
rtl/io/          IO controller of the SD card ports: a second Z80 with SD card, OSD menu, PS/2 and the floppy sector service
rtl/T80/         submodule: mist-devel/T80 (Z80 core)
rtl/mist-modules submodule: mist-devel/mist-modules (scandoubler, OSD)
firmware/        C firmware of the IO controller (SDCC): SD card, FAT, DMK images, menu; firmware/pocket: the variant for the
                 Pocket, MiSTer and BeagleV-Fire (disks come as data slots, not from a FAT card)
syn/de0/         Terasic DE0: Quartus II 13.0sp1 project
syn/analogue/    Analogue Pocket (openFPGA): Quartus Prime project, JSON definition files
syn/mister/      MiSTer: Quartus Prime project, the emu shell
syn/tangnano9k/  Sipeed Tang Nano 9K: Gowin project and constraints
syn/tangnano20k/ Sipeed Tang Nano 20K
syn/beaglev-fire/ BeagleV-Fire: gateware around the core (rtl), the CP-300 cape for the BeagleV-Fire gateware framework,
                 the daemon and web page (host), the installer and the package builder (package), the releases
sim/             GHDL testbenches and scripts (sim/tang: the Tang frame buffer path)
roms/            ROM dumps go here (not committed)
tools/           mkroms, mkfw, mkfat, mkhdv, dsk2dmk, mkpocketrom, mkmisterrom and their tests
docs/            design notes
```

How the pieces fit: the Z80 core and the video run at the CP-300's own speed. On the SD-card ports a second Z80, the IO controller,
runs a small C program from an on-chip ROM: it reads the SD card over SPI, draws the menu through the MiST OSD, reads the PS/2
keyboard while the menu is open, and answers the floppy controller's requests for sectors by looking them up in the mounted DMK
file. On the Pocket, MiSTer and BeagleV-Fire the same IO controller serves the requests from disk images that the host side
provides (the Pocket's data slots, the MiSTer's HPS, the browser through the daemon).

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
- The ports differ: see each port's README for what it has and what it lacks.

## Licence and credits

GPL-3.0 (see [LICENSE](LICENSE)). The vendored files keep their own headers:

- `ht1080z.vhd` and the HT1080Z core: Jozsef Laszlo (BSD-style).
- `sdram.v`: Till Harbaum (GPL-3.0).
- T80 and mist-modules: their own licences (MiST project).
- `rtl/fdc/wd1793.vhd`: VHDL port of the WD1793 replica by Viacheslav Slavinsky and Sorgelig, with the 18 x 256 modification by Stan Hodge (GPL-2.0-or-later).
- DMK format: David Keil. JV1/JV3: Jeff Vavasour.
- The BeagleV-Fire gateware is built with the [BeagleV-Fire gateware framework](https://git.beagleboard.org/beaglev-fire/gateware)
  (MIT, Microchip and BeagleBoard.org) and the Microchip [Hart Software Services](https://github.com/polarfire-soc/hart-software-services)
  bootloader (Microchip licence, MIT-style); the package contains the built bitstream, its source and versions are in the package's `SOURCE.txt`.

The CP-300 ROMs and the disk operating systems are copyrighted and are not included. Prológica, TRS-80, Tandy and the other
names belong to their owners; this is an independent hobby project, not made or endorsed by any of them.

## Disclaimer

This is a hobby project, provided **as is**, without warranty of any kind. Programming an FPGA board can damage it, and flashing the
BeagleV-Fire rewrites its bootloader and can leave the board unable to start. **You use everything here at your own risk; the
author and contributors accept no responsibility or liability for any damage or loss.** The GPL-3.0 warranty disclaimer applies as
well. The BeagleV-Fire package carries the full text and asks for an explicit acceptance before it flashes.
