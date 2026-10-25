# CP-300 on the Sipeed Tang Nano 9K

Port of the CP-300 core (see the top-level [README](../../README.md)) to the Tang Nano 9K (Gowin GW1NR-LV9QN88PC6/I5).
Same Z80 / Model III core, WD1793 floppy controller, SD card menu and original keyboard as the DE0 build;
only the board layer is different. The board layer is shared with the [Tang Nano 20K port](../tangnano20k/README.md)
(`rtl/tang/`); this folder holds the 9K pin file, timing constraints and build script.

**Status: synthesises, places and meets timing in the Gowin tools, and the frame buffer path passes its simulation
([sim/tang](../../sim/tang/run.sh)). Not tried on a board yet.**

## What differs from the DE0

| | DE0 | Tang Nano 9K |
|---|---|---|
| Clock | 50 MHz, altpll -> 42 MHz | 27 MHz, rPLL -> 42 MHz (core), 42 MHz 90 degrees later (HyperRAM clock) |
| Z80 RAM (48 KB) | SDRAM | the on-chip 8 MB HyperRAM through [zf3's controller](https://github.com/zf3/psram-tang-nano-9k) |
| Video | 4-bit VGA from a resistor DAC | HDMI (DVI) on the board's connector, **standard 640x480 @ 60 Hz**. No VGA on the GPIOs |
| SD card | DE0 socket | the board's TF slot (SPI mode) |
| ROM / video RAM / disk buffers | M9K | BSRAM (all 26 blocks used) |
| IO controller CPU | 42 MHz | 21 MHz (`CPU_HALF`): the GW1NR-9 cannot run a T80 at 42 MHz |
| Switches | SW0-SW4 | S1 = reset, S2 = turbo on/off. 60 Hz mode fixed, no scanlines |

### How the video works

The 9K does not have the block RAM for a frame buffer, so the picture lives in the HyperRAM, next to the Z80's RAM:

* `fb_writer` takes the core's raw picture (512 x 192 pixels, 1 bit each: ink or paper) and stores it as 12 KB frames.
  Three frame buffers rotate, so the scan-out never reads a frame that is being written and never shows half of two frames.
* `fb_scanout` runs the 640x480 @ 60 Hz timing (25.2 MHz pixel clock from its own PLL, 126 MHz for the TMDS serialisers) and reads
  each line from the frame buffer one line ahead. The picture is centred as 512 x 384 (every line twice), the border colour fills
  the rest, and the menu OSD is drawn on top (2 x 2 pixels per OSD pixel).
* `psram_arb` shares the one HyperRAM controller between the Z80 (highest priority), the frame writer and the scan-out. The Z80
  RAM bridge raises WAIT while a RAM access is going on; an access takes about 20 clocks, so in normal (2 MHz) mode the CPU rarely
  waits (worst case seen in simulation: one extra T state).
* Ink, paper and border colours are the core's own (they change with the keyboard shortcuts as before).

The HDMI output is plain DVI (no infoframes, no audio), which monitors and most TVs accept.

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
cd syn/tangnano9k
C:\Apps\TangFPGA\Gowin_V1.9.8.11_Education\IDE\bin\gw_sh.exe build.tcl
```

Takes about two minutes. Results in `impl/pnr/`: `cp300_tn9k.fs` (bitstream), `cp300_tn9k.rpt.txt` (resources) and `cp300_tn9k.tr` (timing).
The ROMs and the IO controller firmware are inside the bitstream.

Last build: 79% of the logic, all of the block RAM, clk42 44 MHz (42 needed), pixel clock 52 MHz (25.2 needed).

## Programming

Connect the board's USB-C port. Check that the programmer sees it (this lists the cable and the device):

```
C:\Apps\TangFPGA\Gowin_V1.9.8.11_Education\Programmer\bin\programmer_cli.exe --scan
```

Load for a test (SRAM, lost at power-off):

```
C:\Apps\TangFPGA\Gowin_V1.9.8.11_Education\Programmer\bin\programmer_cli.exe --device GW1NR-9C --run 2 --fsFile impl\pnr\cp300_tn9k.fs
```

To keep it across power cycles use the embedded flash (`--run 5`, or `--run 6` to verify) (same command with `--run N`). The Gowin Programmer GUI (`programmer.exe`) does the
same: choose the device, the operation and the `.fs` file. Nothing has been programmed from here yet.

## Tests

* Frame buffer path (arbiter, Z80 RAM bridge, frame writer, scan-out against a RAM model), Icarus Verilog:
  `sim/tang/run.sh`. It prints `PASS` when no frame is torn, no pixel is wrong and the Z80 reads back what it wrote.
* The shared VHDL still elaborates for the DE0: `sim/run.sh` (GHDL).
* Hardware: nothing has been run on a board yet.

## Files

Board files here: `cp300_tn9k.cst` (pins), `cp300_tn9k.sdc` (timing), `build.tcl`. The design is in `rtl/tang/`:

| File | |
|---|---|
| `cp300_tang.v` | top level (shared with the 20K) |
| `pll_tang.v` | 27 -> 42 MHz (+ phase shifted copy), and 27 -> 126 MHz, /5 = 25.2 MHz |
| `psram_controller.v` | HyperRAM controller by Feng Zhou, Apache 2.0 ([license](../../rtl/tang/LICENSE.psram_controller.txt)); one fix to the power-up counter width |
| `psram_arb.v`, `ram_bridge.v` | three clients on one RAM; one Z80 RAM cycle = one access, produces the WAIT |
| `fb_writer.v`, `fb_scanout.v` | frame buffer in RAM, 640x480 timing, OSD overlay |
| `dvi_tx.v` | TMDS encoders and OSER10 serialisers |
| `sync_stable.v` | takes a slowly changing bus across clock domains |
| `osd.v` | copy of `rtl/mist-modules/osd.v` with a block-RAM friendly OSD buffer (the submodule is not touched) |

Changes in the shared sources: `rtl/ht1080z/ht1080z.vhd` has a generic `EXT_RAM` (default false, the DE0 is unchanged) with the
`ext_ram_*` ports, and new `vid_*` outputs with the raw picture and colours; `videoctrl.vhd` exports them; `rtl/io/io_ctrl.vhd` has
a generic `CPU_HALF` (default false).

## Pins

3.3 V pins of the 2x24 headers (J5/J6 of the board schematic). The 1.8 V header pins (79-88) are not used.

| Signal | FPGA pin | Note |
|---|---|---|
| `clk27` | 52 | board crystal |
| `btn_s1_n` / `btn_s2_n` | 3 / 4 | S1 reset, S2 turbo |
| `led_n[5:0]` | 10 11 13 14 15 16 | LED0 running, LED1 PLLs locked, LED2 RAM ready, LED3 turbo, LED5:4 IO controller |
| HDMI | 69/68 clk, 71/70 d0, 73/72 d1, 75/74 d2 | board connector |
| SD (TF slot) | 36 clk, 37 mosi, 38 cs, 39 miso | board, SPI mode |
| `uart_tx` / `uart_rx` | 17 / 18 | board USB serial (RS-232 ports E8-EA) |
| `ps2_clk` / `ps2_dat` | 25 / 26 | PS/2 keyboard, 3.3 V: **level-shift or use a keyboard that tolerates it**, the pins are pulled up inside the FPGA |
| `audio_out` | 27 | sigma-delta, needs an RC filter |
| `cass_in` | 28 | cassette input (reserved, as on the DE0) |
| `kbd_row[7:0]` | 29 30 33 34 40 35 41 42 | original CP-300 keyboard row lines |
| `kbd_col[7:0]` | 51 53 54 55 56 57 63 48 | column lines, internal pull-ups (53-57 are SSPI configuration pins, set as GPIO in `build.tcl`) |
| `kbd_reset_n` | 49 | the keyboard's reset keys |

The keyboard wiring to the CP-300 keyboard connector is the same as for the DE0, see the top-level README.
Free header pins: 31, 32, 76, 77.

## Not verified

* Everything on a real board: HDMI picture, HyperRAM at 42 MHz (the controller was tested by its author at 81 MHz, LATENCY 3),
  SD card, PS/2. The frame buffer logic is simulated against a behavioural RAM, not the real controller.
* Timing is met with multicycle constraints for the two T80 CPUs (see the comments in `cp300_tn9k.sdc`), which rely on
  their clock enables; the Gowin timing report is clean with them.
* The frame buffer hand-over between the two clock domains uses a stable-sample filter, so a frame can in rare cases be
  shown a frame late or repeated; the simulation shows no torn frames.
