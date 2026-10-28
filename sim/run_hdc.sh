#!/bin/sh
# GHDL test of the FreeHD controller (rtl/hdc/wd1010.vhd) alone: READ and WRITE SECTOR with multi-clock Z80
# I/O cycles, status and error codes, write protect, missing drive. Seconds, no ROMs needed.
#   sim/run_hdc.sh
set -e
GHDL=${GHDL:-ghdl}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/sim/out
mkdir -p "$OUT"
cd "$OUT"
OPTS="--std=08 -fsynopsys -frelaxed --workdir=$OUT"
$GHDL -a $OPTS "$ROOT/rtl/hdc/wd1010.vhd" "$ROOT/sim/tb_hdc.vhd"
$GHDL -e $OPTS tb_hdc
$GHDL -r $OPTS tb_hdc --stop-time=20ms --ieee-asserts=disable 2>&1 | grep -E "FAIL|PASS"
