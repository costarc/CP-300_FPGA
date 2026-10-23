#!/usr/bin/env python3
"""Build roms/boot.hex, the ROM image synthesized into the DE0 M9K ROM.

    python tools/rom2hex.py            -> built-in test ROM (no Tandy code)
    python tools/rom2hex.py LEVEL2.ROM -> that ROM image

The image is padded with FFh (or cut) to 14 KB (0000-37FF).
Quartus reads boot.hex at synthesis, so recompile after changing it.
"""
import os
import sys

ROM_SIZE = 0x3800
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "roms", "boot.hex")

MSG = b"CP-300 FPGA - NO SYSTEM ROM. RUN TOOLS/ROM2HEX.PY"
MSG_POS = 0x3C00 + 7 * 64 + (64 - len(MSG)) // 2


def test_rom():
    """Clear the screen, print MSG in the middle and loop."""
    code = bytes([
        0xF3,                         # di
        0x31, 0x00, 0x00,             # ld sp,0000h
        0x21, 0x00, 0x3C,             # ld hl,3C00h
        0x11, 0x01, 0x3C,             # ld de,3C01h
        0x01, 0xFF, 0x03,             # ld bc,03FFh
        0x36, 0x20,                   # ld (hl),' '
        0xED, 0xB0,                   # ldir
        0x21, 0x22, 0x00,             # ld hl,msg
        0x11, MSG_POS & 0xFF, MSG_POS >> 8,  # ld de,MSG_POS
        0x7E,                         # loop: ld a,(hl)
        0xB7,                         # or a
        0x28, 0x05,                   # jr z,done
        0x12,                         # ld (de),a
        0x23,                         # inc hl
        0x13,                         # inc de
        0x18, 0xF7,                   # jr loop
        0x18, 0xFE,                   # done: jr done
    ])
    assert len(code) == 0x22
    return code + MSG + b"\x00"


def main():
    if len(sys.argv) > 1:
        with open(sys.argv[1], "rb") as f:
            data = f.read()
        if len(data) > ROM_SIZE:
            print(f"warning: {len(data)} bytes, only the first {ROM_SIZE} are used")
    else:
        data = test_rom()
    data = data[:ROM_SIZE].ljust(ROM_SIZE, b"\xFF")
    with open(OUT, "w") as f:
        f.writelines(f"{b:02X}\n" for b in data)
    print(f"wrote {os.path.normpath(OUT)} ({ROM_SIZE} bytes)")


if __name__ == "__main__":
    main()
