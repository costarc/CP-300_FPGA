#!/usr/bin/env python3
"""Make an empty HDV hard disk image for the FreeHD interface (the format of xtrs and TRS32).

    python tools/mkhdv.py out.hdv [--cylinders 153] [--heads 4] [--label NAME]

Layout (Matthew Reed's): a 256-byte header, then cylinders x heads x 32 sectors of 256 bytes, in that
order. The header holds 56 CB 10 at the start, the number of cylinders at byte 28 (0 = 256) and the
sectors per cylinder (heads x 32, 0 = 256) at byte 29. The image is all zeros: format it in the
operating system (LDOS / LS-DOS FORMAT, NEWDOS/80), the controller accepts the format command and does
nothing, as xtrs does. The default, 153 cylinders and 4 heads, is the 5 MB drive of the Radio Shack
hard disk; the most the header allows is 256 cylinders and 8 heads (16 MB).
"""
import argparse
import sys


def make_header(cylinders, heads, label=""):
    hdr = bytearray(256)
    hdr[0], hdr[1], hdr[2] = 0x56, 0xCB, 0x10      # identifiers and format version 1.0
    hdr[4] = 1                                     # blocks of 256 bytes in the header
    hdr[5] = 4                                     # not used, HDFORMAT sets it to 4
    hdr[28] = cylinders & 255                      # 256 is stored as 0
    hdr[29] = (heads * 32) & 255
    hdr[30] = hdr[28]
    hdr[31] = cylinders // 2 if cylinders < 256 else 128   # directory cylinder, the middle of the disk
    hdr[32:64] = label.encode("ascii", "replace")[:31].ljust(32, b"\0")
    hdr[3] = (-sum(hdr[:3])) & 255                 # a simple checksum, xtrs and this core do not check it
    return bytes(hdr)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("out")
    ap.add_argument("--cylinders", type=int, default=153)
    ap.add_argument("--heads", type=int, default=4)
    ap.add_argument("--label", default="")
    a = ap.parse_args()
    if not 1 <= a.cylinders <= 256 or not 1 <= a.heads <= 8:
        sys.exit("cylinders 1-256 and heads 1-8")
    with open(a.out, "wb") as f:
        f.write(make_header(a.cylinders, a.heads, a.label))
        chunk = bytes(256 * 32 * a.heads)
        for _ in range(a.cylinders):
            f.write(chunk)
    print("%s: %d cylinders x %d heads x 32 sectors = %.1f MB" % (a.out, a.cylinders, a.heads,
          a.cylinders * a.heads * 32 * 256 / 1048576))


if __name__ == "__main__":
    main()
