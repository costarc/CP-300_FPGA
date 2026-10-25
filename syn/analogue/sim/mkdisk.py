#!/usr/bin/env python3
"""Test disk for tb_slot: a 35 track JV1 image whose sector bytes are (track*31 + sector*7 + i) & 255,
converted to DMK with tools/dsk2dmk.py.

    python mkdisk.py out/disk.dmk
"""
import os
import subprocess
import sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..")
out = sys.argv[1]
os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
jv1 = out + ".jv1"
with open(jv1, "wb") as f:
    for t in range(35):
        for s in range(10):
            f.write(bytes((t * 31 + s * 7 + i) & 255 for i in range(256)))
subprocess.check_call([sys.executable, os.path.join(root, "tools", "dsk2dmk.py"), jv1, out, "--format", "jv1"])
os.remove(jv1)
print(out, os.path.getsize(out), "bytes")
