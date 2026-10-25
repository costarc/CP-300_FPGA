# CP-300 on the Sipeed Tang Nano 9K

Port of the CP-300 core (see the top-level [README](../../README.md)) to the Tang Nano 9K (Gowin GW1NR-LV9QN88PC6/I5).
Same Z80 / Model III core, WD1793 floppy controller, SD card menu and original keyboard as the DE0 build;
only the board layer is different.

**Status: synthesises, places and meets timing at 42 MHz with the Gowin tools. Not tried on a board yet.**

## What differs from the DE0

| | DE0 | Tang Nano 9K |
|---|---|---|
| Clock | 50 MHz, altpll -> 42 MHz | 27 MHz, rPLL -> 42 MHz (core), 42 MHz 90 degrees later (HyperRAM clock) |
| Z80 RAM (48 KB) | SDRAM | the on-chip 8 MB HyperRAM (PSRAM) through [zf3's controller](https://github.com/zf3/psram-tang-nano-9k), [ram_bridge.v](ram_bridge.v) |
| Video | 4-bit VGA from a resistor DAC | HDMI (DVI) on the board's connector. No VGA on the GPIOs |
| SD card | DE0 socket | the board's TF slot (SPI mode) |
| ROM / video RAM / disk buffers | M9K | BSRAM (25 of 26 blocks used) |
| IO controller CPU | 42 MHz | 21 MHz (`CPU_HALF`): the GW1NR-9 cannot run a T80 at 42 MHz |
| Switches | SW0-SW4 | S1 = reset, S2 = turbo on/off. 60 Hz mode fixed, no scanlines |

The Z80 RAM bridge raises WAIT while a HyperRAM access is going on. An access takes about 15 clocks, less than one T state,
so in normal (2 MHz) mode the CPU does not wait; in turbo mode it waits one T state per RAM access.

## Build

Needs the Gowin tools (V1.9.8.11 Education is enough; it is installed in `C:\Apps\TangFPGA`), the ROM package
`roms/cp300_roms_pkg.vhd` ([roms/README.md](../../roms/README.md)) and the git submodules (`git submodule update --init`).

```
cd syn/tangnano9k
C:\Apps\TangFPGA\Gowin_V1.9.8.11_Education\IDE\bin\gw_sh.exe build.tcl
```

Result: `impl/pnr/cp300_tn9k.fs` (bitstream), `impl/pnr/cp300_tn9k.rpt.txt` and `.tr` (resources and timing).
Load it with the Gowin Programmer (SRAM for a test, embedded flash to keep it) or `openFPGALoader -b tangnano9k cp300_tn9k.fs`.

Last build: 75% of the logic, 97% of the block RAM, clk42 meets 42 MHz.

## Files

| File | |
|---|---|
| `cp300_tn9k.v` | top level |
| `pll_tn9k.v` | 27 -> 42 MHz (+ phase shifted copy) and 42 -> 210 MHz, 210/5 = 42 MHz pixel clock |
| `psram_controller.v` | HyperRAM controller by Feng Zhou, Apache 2.0 ([license](LICENSE.psram_controller.txt)); one fix to the power-up counter width |
| `ram_bridge.v` | one Z80 RAM cycle = one HyperRAM access, produces the WAIT |
| `dvi_tx.v`, `video_cdc.v` | TMDS encoders, OSER10 serialisers, and the FIFO from the core clock to the pixel clock |
| `osd.v` | copy of `rtl/mist-modules/osd.v` with a block-RAM friendly OSD buffer (the submodule is not touched) |
| `cp300_tn9k.cst`, `cp300_tn9k.sdc` | pins and timing |
| `build.tcl` | command line build |

Changes in the shared sources: `rtl/ht1080z/ht1080z.vhd` has a generic `EXT_RAM` (default false, the DE0 is unchanged)
with the `ext_ram_*` ports, and `rtl/io/io_ctrl.vhd` a generic `CPU_HALF` (default false).

## Video

The core's picture goes through the MiST scandoubler (31 kHz, 21 MHz pixel rate, 1344 x ~524 total), and every pixel is sent twice
so the DVI pixel clock is 42 MHz. That is not a standard mode (about 1024 x 480 active, 31 kHz, 60 Hz): most monitors and capture
cards accept it, a few TVs may not. DE comes from the blanking signals, hsync/vsync polarity is what the scandoubler outputs.
The F12 / SHIFT+BREAK menu is drawn into the picture as on the DE0.

## Pins

3.3 V pins of the 2x24 headers (J5/J6 of the board schematic). The 1.8 V header pins (79-88) are not used.

| Signal | FPGA pin | Note |
|---|---|---|
| `clk27` | 52 | board crystal |
| `btn_s1_n` / `btn_s2_n` | 3 / 4 | S1 reset, S2 turbo |
| `led_n[5:0]` | 10 11 13 14 15 16 | LED0 running, LED1 PLLs locked, LED2 HyperRAM ready, LED3 turbo, LED5:4 IO controller |
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
  SD card, PS/2.
* The PLL chain: the 210 MHz TMDS PLL takes the 42 MHz core clock as its input (the tools accept it). If the HDMI picture
  is unstable look here first.
* Timing is met with multicycle constraints for the two T80 CPUs (see the comments in `cp300_tn9k.sdc`), which rely on
  their clock enables; the Gowin timing report is clean with them.
