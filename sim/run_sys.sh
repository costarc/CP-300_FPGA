#!/bin/sh
# Whole-machine GHDL run: CP-300 core + IO controller (real firmware) + SD card model.
# Needs roms/cp300_roms_pkg.vhd, rtl/io/io_fw_pkg.vhd and sim/out/card.img:
#   python tools/mkfat.py sim/out/card.img --clusters 4200 --spc 1
#   sim/run_sys.sh [stop-time]       the screen is in sim/out/screen.txt (rewritten every frame)
set -e
GHDL=${GHDL:-ghdl}
STOP=${1:-600ms}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/sim/out
mkdir -p "$OUT"
cd "$OUT"
OPTS="--std=08 -fsynopsys -frelaxed --workdir=$OUT"
cat > "$OUT/sim_trace_cfg.vhd" <<EOT
package sim_trace_cfg is
  constant TRACE_FROM : time := ${TRACE_FROM_MS:-0} ms;
  constant TRACE_TO   : time := $(( ${TRACE_FROM_MS:-0} + ${TRACE_MS:-0} )) ms;
end package;
EOT
$GHDL -a $OPTS "$OUT/sim_trace_cfg.vhd"
for f in \
  rtl/T80/T80_Pack.vhd rtl/T80/T80_ALU.vhd rtl/T80/T80_MCode.vhd rtl/T80/T80_Reg.vhd \
  rtl/T80/T80.vhd rtl/T80/T80s.vhd \
  roms/cp300_roms_pkg.vhd rtl/cp300/cp300_rom.vhd \
  rtl/ht1080z/videoctrl.vhd rtl/ht1080z/ps2reader.vhd rtl/ht1080z/ps2kbd.vhd \
  rtl/fdc/wd1793.vhd rtl/io/io_fw_pkg.vhd rtl/io/io_ctrl.vhd \
  sim/sdram_sim.vhd sim/sdcard_model.vhd rtl/ht1080z/ht1080z.vhd sim/tb_sys.vhd
do
  $GHDL -a $OPTS "$ROOT/$f"
done
$GHDL -e $OPTS tb_sys
$GHDL -r $OPTS tb_sys --stop-time="$STOP" --ieee-asserts=disable
cat screen.txt
