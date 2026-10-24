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

Program `syn/de0/output_files/cp300_de0.sof` with the Quartus programmer (USB-Blaster on the DE0).

Boot simulation (GHDL 6, prints the screen of the last frame):

```
sh sim/run.sh 1500ms
```

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
