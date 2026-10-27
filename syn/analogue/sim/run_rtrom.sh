#!/bin/sh
# GHDL equivalence test of the runtime ROM (RAM loaded from the SD card) against the ROM package.
#   syn/analogue/sim/run_rtrom.sh
set -e
GHDL=${GHDL:-ghdl}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
OUT=$HERE/out
mkdir -p "$OUT"
cd "$OUT"
OPTS="--std=08 -fsynopsys -frelaxed --workdir=$OUT"
for f in roms/cp300_roms_pkg.vhd rtl/cp300/cp300_rom.vhd rtl/ht1080z/videoctrl.vhd syn/analogue/sim/tb_rtrom.vhd; do
  $GHDL -a $OPTS "$ROOT/$f"
done
$GHDL -e $OPTS tb_rtrom
$GHDL -r $OPTS tb_rtrom --ieee-asserts=disable
