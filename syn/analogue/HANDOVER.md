# Handover: CP-300 on the Analogue Pocket

Written 2026-10-25. Branch `analogue-pocket` of `CP-300_FPGA`, port in `syn/analogue` (README there has the user side).

## State

Written and simulated, **never compiled**: the only Quartus here is II 13.0sp1 (`C:\apps\altera\13.0sp1`), which has no Cyclone V support; `C:\apps\altera\Qua25.1std` holds only the programmer and drivers. Quartus Prime Lite 18.1+ is needed. The framework files come from `github.com/open-fpga/core-template` (cloned to a temp folder; re-clone if needed). Pocket Sync is at `C:\apps\intelFPGA\pocket-sync.exe`.

## What exists

| Part | Where |
|---|---|
| Framework glue, bridge map, settings, PLL, audio | `src/fpga/core/core_top.v`, `mf_pllbase_0002.v` (hand-edited: 42 / 10.5 / 10.5+90 MHz from 74.25) |
| Disks as APF data slots | `apf_dataslot.vhd` (target read/write, slot size table scan), `io_ctrl_pocket.vhd` (helper Z80, port map in its header), `firmware/pocket` (reuses `firmware/dmk.c` with `-DPOCKET`) |
| Video | `pocket_video.v`: native 10.5 MHz picture, VS/HS pulses, DE over 512x192 |
| OSD keyboard | `osd_kbd.v`, layout from `tools/mkoskbd.py` (`osd_kbd_*.hex`), font via `osd_font.vhd` from the CP-300 chargen |
| Audio | `sound_i2s.sv` (agg23, MIT); port FF speaker bit, centred, scaled |
| Definition files, packaging | `core.json data.json interact.json video.json input.json`, `package.py` (bit-reverses the rbf) |

## Tests (all pass)

`sim/run_slot.sh` (GHDL, ~30 min), `sim/run_osd.sh`, `sim/run_video.sh`, `sim/lint.sh` (iverilog). GHDL is at `C:\apps\msys64\mingw64\bin`; SDCC 4.6 at `C:\Apps\SDCC`.

## Decisions and facts worth keeping

- Bridge is big endian (`bridge_endian_little = 0`): first byte of a word is bits 31:24. Bridge map: `2x` rx buffer, `3x` tx buffer, `40000000+` settings, `F8` framework.
- Slots 0-3 are `deferload`, user-reloadable, bit 9 (persist filename). Interact defaults must match the register reset values in `core_top.v`.
- The IO controller holds the CP-300 in reset until the firmware has scanned the slot table and mounted; the firmware takes ~12 ms (sim) before releasing.
- Keyboard keys use the same 8x8 `ext_keys` matrix as the DE0 (bit = 8*row+col; BREAK = 50, SHIFTs 56/57).
- Never commit ROMs; the font comes from `roms/cp300_roms_pkg.vhd` at synthesis, and `run_osd.sh` makes `sim/out/font.hex` locally. The bitstream embeds the ROM: do not publish it.
- Only Quartus II 13.0sp1 on the machine: the Cyclone III/DE0 flow is unaffected (`firmware/dmk.h` only gained an `#ifdef POCKET`).

## Next steps

1. Compile `src/fpga/ap_core.qpf` in Quartus Prime; fix errors; check `Fitter Status` and negative slack. Likely trouble: `$readmemh` paths (relative to `src/fpga`), PLL rounding, VHDL-2008 vs `std_logic_arith` in `ht1080z.vhd`.
2. On a real Pocket: video scaling/aspect, VS/HS acceptance, audio level, data-slot read/write latency against the WD1793 100 ms wait timeout (fix: cache a whole DMK track in `dmk.c`).
3. Real `icon.bin` and `Platforms/_images/cp300.bin` (template placeholders now; Pocket Sync can convert PNGs).
4. Optional: decode the docked USB keyboard (HID codes in `cont3_*`) into the matrix; cassette; grayscale display modes.
