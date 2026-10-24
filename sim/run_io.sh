#!/bin/sh
# GHDL test of the IO controller firmware: SD card model + OSD snapshots + PS/2 keys.
# Needs rtl/io/io_fw_pkg.vhd (firmware/build.sh), roms/cp300_roms_pkg.vhd and a card image:
#   python tools/mkfat.py sim/out/card.img --clusters 4200 --spc 1
#   sim/run_io.sh [stop-time]        osd_<n>.pbm snapshots end up in sim/out/
set -e
GHDL=${GHDL:-ghdl}
STOP=${1:-400ms}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/sim/out
mkdir -p "$OUT"
cd "$OUT"
OPTS="--std=08 -fsynopsys -frelaxed --workdir=$OUT"
for f in \
  rtl/T80/T80_Pack.vhd rtl/T80/T80_ALU.vhd rtl/T80/T80_MCode.vhd rtl/T80/T80_Reg.vhd \
  rtl/T80/T80.vhd rtl/T80/T80s.vhd \
  roms/cp300_roms_pkg.vhd rtl/io/io_fw_pkg.vhd rtl/ht1080z/ps2reader.vhd \
  rtl/io/io_ctrl.vhd sim/sdcard_model.vhd sim/tb_io.vhd
do
  $GHDL -a $OPTS "$ROOT/$f"
done
$GHDL -e $OPTS tb_io
$GHDL -r $OPTS tb_io --stop-time="$STOP" --ieee-asserts=disable
