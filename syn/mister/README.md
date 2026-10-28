# CP-300 on the MiSTer

The CP-300 core for the MiSTer (Terasic DE10-Nano). The same CP-300 / HT1080Z core and the same helper Z80 (`firmware/pocket`) as the [Analogue Pocket port](../analogue/README.md); only the shell around it is new: `CP300.sv` (the `emu` module), `mister_slots.sv` (disk images through `hps_io`) and the `sys/` framework from [Template_MiSTer](https://github.com/MiSTer-devel/Template_MiSTer) (GPL).

**No ROM is part of the core.** The system ROM and the character generator are read from the SD card.

## SD card

Copy the `.rbf` to `/media/fat/_Computer/` (or `_Other/`), and make the folder `/media/fat/games/CP-300/`.

| File | What | Loaded |
|---|---|---|
| `boot0.rom` | system ROM, 16 KB (`27C128cp300.BIN` of the CP-300; a 14 KB Model III ROM also works) | automatically when the core starts |
| `boot1.rom` | character generator, 2 KB (`2716cp300.BIN`, or `900-65.BIN`) | automatically when the core starts |
| `*.DMK`, `*.DSK` | disk images (DMK format, see the main README) | from the OSD: Drive 0..3 |
| `*.HDV` | FreeHD hard disk images (xtrs / TRS32 / FreHD format, see the main README) | from the OSD: Hard disk 0, Hard disk 1 |

The two ROM files are copyrighted and are not part of this repository or of the core. Without them the CP-300 shows nothing. To try another machine (the CP-500 ROMs, for example) use **Load System ROM** / **Load Char Gen** in the OSD: the CP-300 resets and starts with the new files. The MiSTer remembers the mounted disks, and the core waits about 1.5 s after starting so that they are mounted before the CP-300 boots.

`tools/mkmisterrom.py` makes the two files from the dumps in `roms/` (or from a single 27C128 dump):

```
python tools/mkmisterrom.py [outdir]
python tools/mkmisterrom.py outdir --27c128 27C128cp300.BIN 900-65.BIN
```

## Using it

| | |
|---|---|
| Keyboard | USB keyboard, the same layout as the PS/2 keyboard of the DE0 |
| OSD | F12 (MiSTer): disks, ROMs, write protect, display colour, turbo, aspect ratio, reset |
| Disks | DMK images, read and write; a whole track is read in one request |
| Video | 512 x 192, white / green / amber |
| Sound | the tape port speaker bit |

## Building

Quartus Prime Lite with Cyclone V support. The MiSTer project is normally built with 17.0; `sys/sys.qip` is pointed at the 17.0 PLL files (`pll_q17.qip`) so that other versions do not fail to find `pll_q<version>.qip`.

```
cd syn/mister
quartus_sh --flow compile CP300
```

Result: `output_files/CP300.rbf`. The helper firmware (`core/io_fw_pkg.vhd`) is shared with the Pocket: rebuild it with `sh firmware/pocket/build.sh` after changing `firmware/pocket`.

## State

Compiles and **tested on a real MiSTer** (the FreeHD hard disks added in 0.3.0 are new and have not been tried on one yet). Points to keep an eye on: the DMK write path and the 1.6 s mount delay, video timing on the scaler, USB keyboard through the HPS PS/2 emulation, audio level. Not done: cassette, joystick, the on-screen keyboard of the Pocket.
