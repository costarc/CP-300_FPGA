# Handover: CP-300 on the BeagleV-Fire

Branch `feature/beaglev-fire` of `CP-300_FPGA` (worktree `CP-300_FPGA-bvf`), from `main` 4e2a58d. Started 2026-10-28. Design reasoning is in README.md; this lists what is open.

## Why the Pocket port was the base

Its I/O model (host supplies ROMs, disks, keys; the core only draws pixels and asks for tracks) is the one the BeagleV-Fire needs, and the Pocket build works on hardware. **Caveat:** `main` also carries the latest SD / data-slot speed work (whole-track `DMK_SPAN` reads, changed-block write-back, `DMK_GUESS`), which has *not* run on real hardware yet. The BeagleV firmware is the Pocket firmware (`firmware/pocket`, built with those options). If the first board bring-up shows disk trouble, try the Pocket firmware as it was before commit 1193c05 (per-block access; the mailbox only has to support 512-byte requests).

## Done

- Gateware glue (`rtl/`): AXI4-Lite bridge, register block, frame capture, disk mailbox, audio FIFO, top `bvf_core.v`. Tested in `sim/run.sh` against mocks.
- Daemon and page (`host/`), tested in simulation and in the Browser pane.

## Not done / not verified

1. **No Libero project (2026-10-28 attempt, blocked).** Libero SoC is not installed here (only MPLAB X, XC8/XC16). The framework wants Libero 2022.3 and attaches a component through an APB slave, not a FIC AXI port: see `gateware/README.md` (known / not known, plan) and `rtl/apb_regbus.v` (tested, `sim/run_apb.sh`). The framework's `CAPE.v` / `ADD_CAPE.tcl` could not be read, so the APB window size, base address and clock are unknown. Original wording: Nothing was synthesised for PolarFire. Needs: a project that instantiates `bvf_core` with a 42 MHz clock from a CCC, the AXI4-Lite slave on a fabric interface (FIC0 master port of the MSS, 20 bit address window = 1 MB), the T80 / ht1080z / wd1793 VHDL, `cp300_roms_stub.vhd`, `io_fw_pkg.vhd`, and the sources of `../analogue/src/fpga/core` named in README.md.
2. **Memory budget.** Block RAM in the design: Z80 RAM 64 KB (524 kbit), frame RAM 2 x 12 KB (196 kbit), track RAM 16 KB (131 kbit), ROM RAMs about 147 kbit, IO controller 8 KB, WD1793 buffers, core video RAM. This is about 1.1 Mbit, close to what the MPFS025T has (I did not confirm the LSRAM count; check the datasheet). Savings, in order: `BUFS(1)` in `bvf_fb` (-98 kbit, the daemon retries torn copies), Z80 RAM 64 KB to 48 KB (-131 kbit; needs a check of what `ht1080z` maps below 4000h), track RAM 16 KB to 8 KB (the daemon and `DMK_SPAN` limits in `firmware/dmk.h` must follow).
3. **Device tree overlay and UIO.** The gateware needs a `generic-uio` node for the FIC window (and the `irq` line, which the daemon does not use yet: it polls every 0.5-4 ms). Until then use `--mem` with the FIC base address; the default BeagleV-Fire FIC addresses were not checked.
4. **Disk request latency.** The WD1793 has a 100 ms wait (`ht1080z.vhd`). The daemon answers a request in well under 1 ms of Python time on a PC; on the board's U54 with Python it will be slower. Measure with `stats.requests` and the time from request to DONE, and use the IRQ if polling is too slow.
5. **Frame read cost.** `read_block` does 3072 32 bit AXI reads per frame; each AXI4-Lite read goes through two clock crossings (about 20 aclk cycles). Probably 1-3 ms per frame, OK for 60 Hz but not measured; `cp300d` only sends when the frame counter moved.
6. **Not tried in a real browser beyond the Browser pane:** audio (WebAudio scheduling is untested in practice; sound is the 1-bit speaker port), touch on-screen keyboard.
7. The stock web server of the board was not examined; the page is served by the daemon on port 8300. If the stock server must serve the files, copy `host/web/` there and change the WebSocket URL in `index.html` (`location.host` to `<board>:8300`).
8. Cassette, hard disk and the original keyboard matrix are not part of this (same as the Pocket).

## Decisions

- Track RAM is little endian here (Pocket: big endian) so Linux sees bytes in order. ROM words stay big endian packed (`ht1080z` expects the first byte in bits 31:24); the daemon does the packing.
- Pixel x of a frame word is bit x mod 32, leftmost pixel least significant, so the daemon hands the browser plain LSB-first bytes.
- The core and the IO controller are held in reset (`CTRL.run = 0`) until the daemon has loaded both ROMs and the slot table. The IO controller then scans the table (`SCAN_VALID`) and mounts the drives like on the Pocket.
- Disk uploads are converted to DMK in the daemon with `tools/dsk2dmk.py`; the daemon keeps the images in RAM and saves them on change.
