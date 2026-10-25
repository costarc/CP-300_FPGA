#!/bin/sh
# GHDL test of the original keyboard matrix scanner: sim/run_kbd.sh
set -e
GHDL=${GHDL:-ghdl}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/sim/out
mkdir -p "$OUT"
cd "$OUT"
OPTS="--std=08 -fsynopsys -frelaxed --workdir=$OUT"
for f in rtl/kbd/matrix_kbd.vhd rtl/ht1080z/ps2reader.vhd rtl/ht1080z/ps2kbd.vhd sim/tb_kbd.vhd; do
  $GHDL -a $OPTS "$ROOT/$f"
done
$GHDL -e $OPTS tb_kbd
$GHDL -r $OPTS tb_kbd --stop-time=80ms --ieee-asserts=disable 2>&1 | grep -v "^$"
