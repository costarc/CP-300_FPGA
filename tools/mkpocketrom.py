#!/usr/bin/env python3
"""Make the two ROM files the Analogue Pocket core loads from the SD card.

    python tools/mkpocketrom.py [outdir]        default: syn/analogue/dist-sd/Assets/cp300/common

  cp300.rom      16 KB system ROM: 900-61.BIN .. 900-64.BIN one after the other (0000-3FFF), from roms/
  cp300chr.rom   2 KB character generator, a copy of 900-65.BIN

Or, with a single-EPROM dump of the later boards (27C128, 16 KB, the same layout):

    python tools/mkpocketrom.py outdir --27c128 27C128cp300.BIN 900-65.BIN

The files are copyrighted and are not part of the repository or of the core: copy them to
Assets/cp300/common/ on the Pocket's SD card (the Pocket asks for them if they are missing).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROMS = os.path.join(HERE, "..", "roms")


def main():
    args = sys.argv[1:]
    single = None
    if "--27c128" in args:
        i = args.index("--27c128")
        single, chargen = args[i + 1], args[i + 2]
        args = args[:i]
    out = args[0] if args else os.path.join(HERE, "..", "syn", "analogue", "dist-sd", "Assets", "cp300", "common")
    os.makedirs(out, exist_ok=True)
    if single:
        sysrom = open(single, "rb").read()
        char = open(chargen, "rb").read()
    else:
        sysrom = b"".join(open(os.path.join(ROMS, "900-6%d.BIN" % n), "rb").read() for n in (1, 2, 3, 4))
        char = open(os.path.join(ROMS, "900-65.BIN"), "rb").read()
    if len(sysrom) != 16384:
        sys.exit("error: the system ROM must be 16384 bytes, got %d (4 x 4 KB 2732 images, or a 27C128 dump)" % len(sysrom))
    if len(char) != 2048:
        sys.exit("error: the character generator must be 2048 bytes, got %d" % len(char))
    open(os.path.join(out, "cp300.rom"), "wb").write(sysrom)
    open(os.path.join(out, "cp300chr.rom"), "wb").write(char)
    print("wrote", os.path.join(out, "cp300.rom"), "and cp300chr.rom")


if __name__ == "__main__":
    main()
