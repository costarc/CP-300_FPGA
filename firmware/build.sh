#!/bin/sh
# Build the IO controller firmware with SDCC and regenerate rtl/io/io_fw_pkg.vhd.
#   firmware/build.sh
# SDCC 4.6.0 in C:/Apps/SDCC. SDCC 4.0.0 miscompiled `e->name[k] = p[k]` (wrong register in
# `add iy,bc`) and `return a - b` of uint16_t arguments. Pass SDCC_BIN=... to override.
set -e
cd "$(dirname "$0")"
SDCC_BIN=${SDCC_BIN:-/c/Apps/SDCC/bin}
export PATH="$SDCC_BIN:$PATH"
mkdir -p out
cd out
sdasz80 -plosgff crt0.rel ../crt0.s
for f in main sd fat; do
  sdcc -mz80 --std-sdcc99 -c ../$f.c -o $f.rel
done
sdcc -mz80 --no-std-crt0 --code-loc 0x0100 --data-loc 0x4000 \
  crt0.rel main.rel sd.rel fat.rel -o io_fw.ihx
python ../../tools/mkfw.py io_fw.ihx
cat io_fw.map | grep -E "^ +(_CODE|_DATA|_INITIALIZED|_HEADER) " || true
