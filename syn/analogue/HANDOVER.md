# Handover: CP-300 on the Analogue Pocket

Written 2026-10-25, updated 2026-10-26. Branch `analogue-pocket` of `CP-300_FPGA`, port in `syn/analogue` (README there has the user side).

## State

Compiles and packages: Quartus Prime Lite 25.1 at `C:\altera_lite\25.1std` (`quartus_sh --flow compile ap_core` in `src/fpga`, about 5 minutes; fitter OK, all slack positive, worst +0.14 ns). **Never run on a real Pocket.** Quartus II 13.0sp1 (`C:\apps\altera\13.0sp1`) is the DE0 tool and has no Cyclone V. The framework files come from `github.com/open-fpga/core-template` (cloned to a temp folder; re-clone if needed). Pocket Sync is at `C:\apps\intelFPGA\pocket-sync.exe`.

## What exists

| Part | Where |
|---|---|
| Framework glue, bridge map, settings, PLL, audio | `src/fpga/core/core_top.v`, `mf_pllbase_0002.v` (hand-edited: 42 / 10.5 / 10.5+90 MHz from 74.25) |
| Disks as APF data slots | `apf_dataslot.vhd` (target read/write of up to 16 KB, slot size table scan, the 16 KB track RAM built from four `trk_ram.vhd` lanes), `io_ctrl_pocket.vhd` (helper Z80, port map in its header; the track RAM is at 8000h-BFFFh), `firmware/pocket` (reuses `firmware/dmk.c`, built with `DMK_SPAN`) |
| `ht1080z_ext.vhd` | wrapper: Verilog cannot drive the boolean generic `EXT_RAM`, so this fixes it to true |
| Video | `pocket_video.v`: native 10.5 MHz picture, VS/HS pulses, DE over 512x192 |
| OSD keyboard | `osd_kbd.v`, layout from `tools/mkoskbd.py` (`osd_kbd_*.hex`), font via `osd_font.vhd` from the CP-300 chargen |
| Audio | `sound_i2s.sv` (agg23, MIT); port FF speaker bit, centred, scaled |
| Definition files, packaging | `core.json data.json interact.json video.json input.json`, `package.py` (bit-reverses the rbf) |

## Tests (all pass)

`sim/run_slot.sh` (GHDL, ~30 min), `sim/run_osd.sh`, `sim/run_video.sh`, `sim/lint.sh` (iverilog). GHDL is at `C:\apps\msys64\mingw64\bin`; SDCC 4.6 at `C:\Apps\SDCC`.

## SD access (2026-10-26)

`firmware/dmk.c` is shared by every board (options at the top of `dmk.h`). It has a block cache of `DMK_WIN` 512-byte slots, sector data is copied a slot at a time, and writes do no read first. SD-card boards: 3 slots and `DMK_GUESS` (look for a sector where it probably is before scanning every ID field; differs from a scan only with duplicate IDs on a track). Pocket: `DMK_SPAN` with 32 slots in the track RAM; the first access to a track loads the whole track with one data slot request, and a sector write goes back as one request of the changed blocks. Request lengths are clamped to the file size (read through ports 30h-33h). Host test: `DMK_CFLAGS="-DDMK_WIN=32 -DDMK_SPAN=1" python tools/test_dmk.py file.dmk`.

Not done: the helper CPU still runs at half clock where `CPU_HALF` is set (timing slack is tight); there is no per-request timer on the debug byte yet, so the real data slot latency is still unknown.

## Decisions and facts worth keeping

- Bridge is big endian (`bridge_endian_little = 0`): first byte of a word is bits 31:24. Bridge map: `2x` rx buffer, `3x` tx buffer, `40000000+` settings, `F8` framework.
- Slots 0-3 are `deferload`, user-reloadable, bit 9 (persist filename). Interact defaults must match the register reset values in `core_top.v`.
- The IO controller holds the CP-300 in reset until the firmware has scanned the slot table and mounted; the firmware takes ~12 ms (sim) before releasing.
- Keyboard keys use the same 8x8 `ext_keys` matrix as the DE0 (bit = 8*row+col; BREAK = 50, SHIFTs 56/57).
- Never commit ROMs; the font comes from `roms/cp300_roms_pkg.vhd` at synthesis, and `run_osd.sh` makes `sim/out/font.hex` locally. The bitstream embeds the ROM: do not publish it.
- Only Quartus II 13.0sp1 on the machine: the Cyclone III/DE0 flow is unaffected (`firmware/dmk.h` only gained an `#ifdef POCKET`).

## Next steps

1. Done: compiles in Quartus Prime Lite 25.1.
2. On a real Pocket: video scaling/aspect, VS/HS acceptance, audio level, data-slot read/write latency against the WD1793 100 ms wait timeout (fix: cache a whole DMK track in `dmk.c`).
3. Real `icon.bin` and `Platforms/_images/cp300.bin` (template placeholders now; Pocket Sync can convert PNGs).
4. Optional: decode the docked USB keyboard (HID codes in `cont3_*`) into the matrix; cassette; grayscale display modes.
