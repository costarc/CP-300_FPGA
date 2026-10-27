#!/bin/sh
# GHDL test of the Pocket IO controller firmware against a behavioural APF host.
#   syn/analogue/sim/run_slot.sh [stop-time]
# Needs: firmware/pocket/build.sh run once (io_fw_pkg.vhd), sim/mkdisk.py output (made here).
set -e
GHDL=${GHDL:-ghdl}
STOP=${1:-400ms}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
OUT=$HERE/out
mkdir -p "$OUT"
python "$HERE/mkdisk.py" "$OUT/disk.dmk"
cd "$OUT"
OPTS="--std=08 -fsynopsys -frelaxed --workdir=$OUT"
for f in \
  rtl/T80/T80_Pack.vhd rtl/T80/T80_ALU.vhd rtl/T80/T80_MCode.vhd rtl/T80/T80_Reg.vhd \
  rtl/T80/T80.vhd rtl/T80/T80s.vhd \
  syn/analogue/src/fpga/core/io_fw_pkg.vhd syn/analogue/sim/trk_ram_sim.vhd syn/analogue/src/fpga/core/apf_dataslot.vhd \
  syn/analogue/src/fpga/core/io_ctrl_pocket.vhd syn/analogue/sim/tb_slot.vhd
do
  $GHDL -a $OPTS "$ROOT/$f"
done
$GHDL -e $OPTS tb_slot
$GHDL -r $OPTS tb_slot --stop-time="$STOP" --ieee-asserts=disable
