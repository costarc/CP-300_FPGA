# Handover: CP-300 on the BeagleV-Fire

State at the first release (package 0.2.0, 2026-10-28). The README is the user documentation, [BUILDING.md](BUILDING.md) the build
procedure; this lists what is open.

## Done and checked on a board

- The gateware (APB bridge, registers, frame capture, disk mailbox, audio FIFO) builds in Libero SoC 2026.1 on the framework commit
  `943f37f`, meets timing and fits the MPFS025T (78% LUT, 88% block RAM). The image boots the board, `/dev/uio0` appears, the ID
  register reads `0x43503001`.
- The daemon runs the CP-300 on the real fabric: TRSDOS 1.3 boots from a disk image, a game plays, the keyboard and the sound work,
  through nginx (`/cp300/`) and from the Cockpit sidebar entry.
- The package (`package/`) with the installer, the load helper and the disclaimer; the installer's software path and the "gateware
  already loaded, do not flash" path ran on the board.

## Not done / not verified

1. **The flash-and-reboot path of the installer** (`--force-flash`) and **another gateware and back** have not been run on a board.
2. **Frame rate:** about 40 fps in the page against the 60 Hz hardware. The daemon's Python (zlib of the XOR frame, WebSocket) is
   the limit; the bulk read of a frame itself takes 1.5 ms.
3. **Saving to a disk image** was not checked end to end after a reset.
4. **Libero SoC 2026.1 is not officially supported** by the framework; the build needs two edits of a scratch copy (BUILDING.md,
   step 5). A build on 2025.2 would remove that doubt.
5. **No fallback when flashing** (the board's own mechanism keeps none). A FlashPro5/6 recovery was not tried.
6. Ideas: embed the page in Cockpit through Cockpit's HTTP and WebSocket channels (the browser refuses an `http` frame inside the
   `https` Cockpit page, so the sidebar entry opens the page in a new tab); use the interrupt line (`irq`) instead of polling;
   a bus timeout in `apb_regbus.v` so a dead clock cannot hang the bus; a prebuilt `regs32.so` for boards without `gcc`.

## Decisions

- Track RAM is little endian (the Pocket's is big endian) so Linux sees bytes in order. ROM words stay big endian packed
  (`ht1080z` expects the first byte in bits 31:24); the daemon does the packing.
- Pixel x of a frame word is bit x mod 32, leftmost pixel least significant, so the daemon hands the browser plain LSB-first bytes.
- All register access goes through `host/regs32.c` (real 32-bit loads and stores): the window has no byte strobes, and Python's
  byte-wise stores corrupt every word.
- The IO controller must be released (`CTRL.run = 1`) **before** the slot table is published: the slot registers are held cleared
  while `run = 0`.
- Disk uploads are converted to DMK in the daemon with `tools/dsk2dmk.py`; the images are kept in RAM and saved on change.
