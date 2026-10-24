# ROMs

ROM images are copyrighted and are not part of this repository. Put the dumps from a CP-300 board here:

| File | Chip | Board position | Address |
|---|---|---|---|
| `900-61.BIN` | 2732, 4 KB | CI-28 | 0000-0FFF |
| `900-62.BIN` | 2732, 4 KB | CI-29 | 1000-1FFF |
| `900-63.BIN` | 2732, 4 KB | CI-30 | 2000-2FFF |
| `900-64.BIN` | 2732, 4 KB | CI-31 | 3000-37FF (3800-3FFF is keyboard and video RAM) |
| `900-65.BIN` | 2716, 2 KB | CI-59 | character generator |

These are the boards before schematic revision 2.3 (25-11-83, "eliminado CI's 29-30-31"), which replaced the four EPROMs with one 27128.

Read each EPROM as a 2732 (4 KB, A11 driven). `mkroms.py` warns when a 900-61..63 image has two identical 2 KB halves, the sign of a 2732 read as a 2716. Only 900-64 may look like that, since its upper half (3800-3FFF) is never selected.

**Known issue (October 2026):** the current 900-61 and 900-62 dumps have identical halves, so 0800-0FFF and 1800-1FFF are missing (for example the DE/HL compare routine at 1C90 that RST 18 jumps to). The boot simulation crashes there. Re-dump both chips.

Then run:

```
python tools/mkroms.py
```

It writes `cp300_roms_pkg.vhd` (VHDL constants, also not committed), which Quartus and the GHDL simulation compile. Recompile after changing a dump.

Character generator layout: address = character code x 8 + scan line (0-7), bit 7 is the leftmost dot. 00-1F accented and special characters, 20-7F ASCII with lower case, 80-BF special symbols, C0-FF katakana. The hardware draws 80-BF as 2x3 graphic blocks and, for now, C0-FF with the special symbols (80-BF of the ROM); the kana selection through port EC comes with the Model III I/O.
