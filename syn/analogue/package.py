#!/usr/bin/env python3
"""Put the Analogue Pocket core together as the folder tree for the SD card.

    python package.py [rbf] [outdir]

  rbf     the Quartus output, default src/fpga/output_files/ap_core.rbf
  outdir  default ./dist-sd

Writes outdir/Cores/costarc.CP-300/ (the JSON files, info.txt, icon.bin and bitstream.rbf_r, the RBF with the
bits of every byte reversed as the Pocket wants it) and outdir/Platforms/ (cp300.json and its picture).
Copy the Cores and Platforms folders to the root of the Pocket's SD card. Disk images (.dsk / .dmk) go to
Assets/cp300/common/ on the card.
"""
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
AUTHOR_CORE = "costarc.CP-300"
CORE_FILES = ["core.json", "data.json", "video.json", "audio.json", "input.json", "interact.json",
              "variants.json", "info.txt"]


def reverse_bits(data):
    table = bytes(int("{:08b}".format(i)[::-1], 2) for i in range(256))
    return data.translate(table)


def main():
    rbf = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "src", "fpga", "output_files", "ap_core.rbf")
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "dist-sd")
    if not os.path.isfile(rbf):
        sys.exit("error: %s not found (compile src/fpga/ap_core.qpf with Quartus Prime first)" % rbf)
    core = os.path.join(out, "Cores", AUTHOR_CORE)
    plat = os.path.join(out, "Platforms")
    os.makedirs(os.path.join(plat, "_images"), exist_ok=True)
    os.makedirs(core, exist_ok=True)
    for f in CORE_FILES:
        shutil.copy(os.path.join(HERE, f), core)
    shutil.copy(os.path.join(HERE, "dist", "icon.bin"), core)
    with open(rbf, "rb") as f:
        data = f.read()
    with open(os.path.join(core, "bitstream.rbf_r"), "wb") as f:
        f.write(reverse_bits(data))
    shutil.copy(os.path.join(HERE, "dist", "platforms", "cp300.json"), plat)
    shutil.copy(os.path.join(HERE, "dist", "platforms", "_images", "cp300.bin"), os.path.join(plat, "_images"))
    print("wrote", out, "(", len(data), "byte bitstream )")


if __name__ == "__main__":
    main()
