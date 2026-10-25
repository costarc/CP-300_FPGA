# CP-300 on the Sipeed Tang Nano 20K

The same design as the [Tang Nano 9K port](../tangnano9k/README.md) (`rtl/tang/`), for the Tang Nano 20K
(Gowin GW2AR-LV18QN88C8/I7), **built so that it uses no more than a Tang Nano 9K has**: if it works on the 20K board, the
logic, block RAM, PLL and timing budget of the 9K design is proven on hardware (everything except the 9K's HyperRAM
controller and pins, see below). `check_9k_limits.py` runs after a build and fails if a limit of the 9K is exceeded.

**Status: synthesises, places and meets timing in the Gowin tools; the frame buffer path passes its simulation with the real
SDRAM controller against an SDRAM model ([sim/tang](../../sim/tang/run.sh) `sdram`). Not tried on a board yet.**

## Differences from the 9K

| | 9K | 20K |
|---|---|---|
| RAM | on-chip 8 MB HyperRAM (`psram_controller.v`) | on-chip 64 Mbit (8 MB) **SDR SDRAM** (`sdram_ctrl.v`, `sdram.v`: nand2mario's controller from [WonderTANG](https://github.com/lfantoniosi/WonderTANG), BSD 2-Clause) |
| RAM clock phase | 90 degrees | 180 degrees (the SDRAM clock) |
| Buttons | S1 / S2 read low when pressed | read high when pressed (`BOARD_TN20K` flips them) |
| Pins | `cp300_tn9k.cst` | `cp300_tn20k.cst` |

`board_tn20k.v` only defines `BOARD_TN20K`; it is compiled before `rtl/tang/cp300_tang.v` (the Gowin tools keep macros across
files) and selects the SDRAM ports, controller, PLL phase and button polarity in the shared top level.

Everything else is shared: the frame buffer, the arbiter, the 640x480 HDMI output with the menu, the core.

## Tools

All paths are the ones on the development machine; the versions are the ones the results below were produced with.

| Step | Tool |
|---|---|
| Synthesis, place and route, timing | Gowin EDA V1.9.8.11 Education, command line `gw_sh.exe` (`C:\Apps\TangFPGA\Gowin_V1.9.8.11_Education\IDE\bin\`) |
| Programming | Gowin Programmer V1.9.8.11 Education, `programmer_cli.exe` or `programmer.exe` (`C:\Apps\TangFPGA\Gowin_V1.9.8.11_Education\Programmer\bin\`); USB driver from `C:\Apps\TangFPGA\GWU2X` |
| Frame buffer simulation | Icarus Verilog 13.0 (`iverilog`, `vvp`; MSYS2: `pacman -S mingw-w64-x86_64-iverilog`) |
| Core simulation (DE0 regression) | GHDL (MSYS2 mingw64), see `sim/run.sh` |
| Helper scripts | Python 3 |

## Build

Needs the ROM package `roms/cp300_roms_pkg.vhd` ([roms/README.md](../../roms/README.md)) and the git submodules
(`git submodule update --init`).

```
cd syn/tangnano20k
C:\Apps\TangFPGA\Gowin_V1.9.8.11_Education\IDE\bin\gw_sh.exe build.tcl
python check_9k_limits.py     # fails if the 9K's resources are exceeded
```

Takes about two minutes. Results in `impl/pnr/`: `cp300_tn20k.fs` (bitstream), `cp300_tn20k.rpt.txt` (resources) and `cp300_tn20k.tr` (timing).
The ROMs and the IO controller firmware are inside the bitstream.

Last build: 6814 logic cells (the 9K has 8640), 2063 registers (6771), 26 block RAMs (26), 2 PLLs (2); clk42 77 MHz (42 needed).

## Programming

Connect the board's USB-C port. Check that the programmer sees it (this lists the cable and the device):

```
C:\Apps\TangFPGA\Gowin_V1.9.8.11_Education\Programmer\bin\programmer_cli.exe --scan
```

Load for a test (SRAM, lost at power-off):

```
C:\Apps\TangFPGA\Gowin_V1.9.8.11_Education\Programmer\bin\programmer_cli.exe --device GW2AR-18C --run 2 --fsFile impl\pnr\cp300_tn20k.fs
```

To keep it across power cycles use the board's external flash (`--run 8`, or `--run 9` to verify) (same command with `--run N`). The Gowin Programmer GUI (`programmer.exe`) does the
same: choose the device, the operation and the `.fs` file. Nothing has been programmed from here yet: only `--scan` was run, and it found the cable and a GW2AR-18C family device.

## Tests

* Frame buffer path (arbiter, Z80 RAM bridge, frame writer, scan-out against a RAM model), Icarus Verilog:
  `sim/tang/run.sh sdram`. It prints `PASS` when no frame is torn, no pixel is wrong and the Z80 reads back what it wrote.
* The shared VHDL still elaborates for the DE0: `sim/run.sh` (GHDL).
* Hardware: nothing has been run on a board yet.

## Pins

| Signal | FPGA pin | Note |
|---|---|---|
| `clk27` | 4 | board crystal |
| `btn_s1_n` / `btn_s2_n` | 88 / 87 | S1 reset, S2 turbo (despite the `_n`: high when pressed on this board) |
| `led_n[5:0]` | 15 16 17 18 19 20 | LED0 running, LED1 PLLs locked, LED2 RAM ready, LED3 turbo, LED5:4 IO controller |
| HDMI | 33/34 clk, 35/36 d0, 37/38 d1, 39/40 d2 | board connector |
| SD (TF slot) | 83 clk, 82 mosi (CMD), 81 cs (DAT3), 84 miso (DAT0) | board, SPI mode |
| `uart_tx` / `uart_rx` | 69 / 70 | board USB serial |
| `ps2_clk` / `ps2_dat` | 25 / 26 | PS/2 keyboard, 3.3 V: level-shift or use a keyboard that tolerates it |
| `audio_out` | 27 | sigma-delta, needs an RC filter |
| `cass_in` | 28 | cassette input (reserved) |
| `kbd_row[7:0]` | 29 30 31 41 42 48 49 51 | original CP-300 keyboard row lines |
| `kbd_col[7:0]` | 52 53 54 55 56 71 72 73 | column lines, internal pull-ups |
| `kbd_reset_n` | 74 | the keyboard's reset keys |

The header pins are taken from the pins that the WonderTANG board uses on the same headers; **check them against the 20K
schematic before wiring** (the LED pins 15-20 and the buttons are on the board itself). The SDRAM pins are inferred from the port
names (`O_sdram_*`, `IO_sdram_dq`), no location needed.

## Not verified

* Everything on a real board. The SDRAM controller runs at 42 MHz here (WonderTANG runs it at 108 MHz with the same timing parameters).
* The 20K test says nothing about the 9K's HyperRAM controller, the 9K pins and the 9K's own timing; the logic is the same.
