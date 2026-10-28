#!/bin/sh
# GHDL boot simulation of the CP-300 core. Needs roms/cp300_roms_pkg.vhd
# (python tools/mkroms.py). The last frame's screen is left in sim/out/screen.txt.
#
#   sim/run.sh [stop-time]      e.g. sim/run.sh 3000ms
set -e
GHDL=${GHDL:-ghdl}
STOP=${1:-1500ms}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/sim/out
mkdir -p "$OUT"
cd "$OUT"

OPTS="--std=08 -fsynopsys -frelaxed --workdir=$OUT"

# optional fetch/write trace window into trace.txt:
#   TRACE_FROM_MS=1370 TRACE_MS=30 sim/run.sh 1400ms
cat > "$OUT/sim_trace_cfg.vhd" <<EOF
package sim_trace_cfg is
  constant TRACE_FROM : time := ${TRACE_FROM_MS:-0} ms;
  constant TRACE_TO   : time := $(( ${TRACE_FROM_MS:-0} + ${TRACE_MS:-0} )) ms;
end package;
EOF
$GHDL -a $OPTS "$OUT/sim_trace_cfg.vhd"
for f in \
  rtl/T80/T80_Pack.vhd rtl/T80/T80_ALU.vhd rtl/T80/T80_MCode.vhd rtl/T80/T80_Reg.vhd \
  rtl/T80/T80.vhd rtl/T80/T80s.vhd \
  roms/cp300_roms_pkg.vhd rtl/cp300/cp300_rom.vhd \
  rtl/ht1080z/videoctrl.vhd rtl/ht1080z/ps2reader.vhd rtl/ht1080z/ps2kbd.vhd rtl/fdc/wd1793.vhd rtl/hdc/wd1010.vhd \
  sim/sdram_sim.vhd rtl/ht1080z/ht1080z.vhd sim/tb_cp300.vhd
do
  $GHDL -a $OPTS "$ROOT/$f"
done
$GHDL -e $OPTS tb_cp300
shift $(( $# > 0 ? 1 : 0 ))
$GHDL -r $OPTS tb_cp300 --stop-time="$STOP" --ieee-asserts=disable "$@"
cat screen.txt
