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

Read each EPROM as a 2732 (4 KB, A11 driven). `mkroms.py` warns when a 900-61..63 image has two identical 2 KB halves, the sign of a 2732 read as a 2716.

The older archive `cp-300_roms_4x2732_gc.zip` holds only the first 2 KB of each 2732, stored twice (read as 2716s): 0800-0FFF, 1800-1FFF and 2800-2FFF are missing, and its 900-63 lower half has bit 7 dropped in 164 bytes. The complete set `cp-300_roms_4x2732_full.zip` was cut in 4 KB pieces from `27C128cp300.BIN`, a 16 KB dump of the same ROM from a later single-EPROM board. Every byte the old dumps do have matches it.

| File | MD5 |
|---|---|
| `900-61.BIN` | fcba30c4749e693a1cfa2c6acfd5bfa4 |
| `900-62.BIN` | 0b68f7d7069a6e85aba5f9db70088144 |
| `900-63.BIN` | cb6487d9eb4d40c05ba04840cf9881d6 |
| `900-64.BIN` | 733031292423cf327cf719f696255715 |
| `900-65.BIN` | 8ccef559eaa98ba050f42f838d292ce2 |

900-64's upper half (3800-3FFF of the chip) holds "MONITOR VERSAO 1.1 1982 PROLOGICA". The CPU cannot select it at 3800 (keyboard); how the CP-300 reaches it is still open.

Then run:

```
python tools/mkroms.py
```

It writes `cp300_roms_pkg.vhd` (VHDL constants, also not committed), which Quartus and the GHDL simulation compile. Recompile after changing a dump.

Character generator layout: address = character code x 8 + scan line (0-7), bit 7 is the leftmost dot. 00-1F accented and special characters, 20-7F ASCII with lower case, 80-BF special symbols, C0-FF katakana. The hardware draws 80-BF as 2x3 graphic blocks and, for now, C0-FF with the special symbols (80-BF of the ROM); the kana selection through port EC comes with the Model III I/O.
