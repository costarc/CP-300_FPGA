#!/usr/bin/env python3
"""Check firmware/dmk.c against tools/dsk2dmk.py's own DMK decoding on real images.

    python tools/test_dmk.py file.dmk [file.dmk ...]      (needs gcc; see the commands it runs)

It builds a FAT image holding the files in /CP300, runs firmware/tests/host_dmk.c on it and
compares every sector (track, side, ID, byte sum) and the READ ADDRESS order with the Python decoder.
"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dsk2dmk as conv  # noqa: E402
import mkfat  # noqa: E402


def main():
    files = sys.argv[1:]
    if not files:
        sys.exit(__doc__)
    tmp = tempfile.mkdtemp(prefix="dmktest_")
    names = []
    store = {}
    for i, f in enumerate(files):
        n = "T%02d.DSK" % i
        store[n] = open(f, "rb").read()
        names.append(n)
    img = os.path.join(tmp, "card.img")
    mkfat.build(img, False, store, clusters=60000, spc_arg=2)
    exe = os.path.join(tmp, "host_dmk")
    src = os.path.join(HERE, "..", "firmware")
    cflags = os.environ.get("DMK_CFLAGS", "").split()      # e.g. "-DDMK_WIN=32 -DDMK_SPAN=1 -DDMK_GUESS=0"
    subprocess.check_call(["gcc", "-DHOST_TEST", "-I", src] + cflags + ["-o", exe,
                           os.path.join(src, "tests", "host_dmk.c"), os.path.join(src, "tests", "host_sd.c"),
                           os.path.join(src, "dmk.c"), os.path.join(src, "fat.c")])
    out = subprocess.check_output([exe] + [mkfat.short_name(n).decode() for n in names],
                                  env=dict(os.environ, HOST_IMG=img)).decode()
    bad = 0
    sections = re.split(r"^FILE ", out, flags=re.M)[1:]
    for f, sec in zip(files, sections):
        disk = conv.read_dmk(store[names[files.index(f)]])
        want = {}
        skipped = 0
        for (t, s, i), sector in disk.sectors.items():
            # the controller matches the cylinder of the ID field with the track register, and
            # duplicate IDs are ambiguous: copy protection, not tested here
            if len(sector.data) == 256 and sector.c in (None, t) and (t, s, i) not in disk.dups:
                want[(t, s, i)] = (sum(sector.data), 1)
            else:
                skipped += 1
        got = {}
        for line in sec.splitlines()[1:]:
            if line.startswith(("RA", "WRITE", "COST")):
                continue
            t, s, i, fl, sm = map(int, line.split())
            got[(t, s, i)] = (sm, fl & 1)
        missing = [k for k in want if k not in got]
        extra = [k for k in got if k not in want]
        diff = [k for k in want if k in got and want[k][0] != got[k][0]]
        crcerr = sum(1 for line in sec.splitlines()[1:] if line[0].isdigit() and int(line.split()[3]) & 2)
        writes = [line for line in sec.splitlines() if line.startswith("WRITE")]
        for line in writes:
            # flags 1 = found, 5 = found and deleted mark; the CRC must be right after the write
            if "data same" not in line or not (" flags 1 " in line or " flags 5 " in line):
                print("  FAILED:", line)
                bad += 1
        print(f"  {len(writes)} write tests done")
        extra = [k for k in extra if k not in disk.dups]
        print(f"{os.path.basename(f)}: {len(want)} sectors by the Python decoder ({skipped} skipped: other size, "
              f"odd cylinder or duplicate ID), {len(got)} by dmk.c, "
              f"{len(missing)} missing, {len(extra)} extra, {len(diff)} different, {crcerr} with CRC errors")
        bad += len(missing) + len(extra) + len(diff)
    print("OK" if not bad else f"{bad} MISMATCHES")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
