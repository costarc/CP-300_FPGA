#!/bin/sh
# Elaborate the Verilog side of the Pocket core with iverilog (VHDL entities are stubbed): finds port
# mismatches, undeclared names and width errors that Quartus would only report after a long run.
#   syn/analogue/sim/lint.sh
# (The framework's apf_top.v declares nets after use, which Quartus accepts and iverilog does not;
# it is not part of this check.)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
F=$HERE/../src/fpga
IVERILOG=${IVERILOG:-/c/apps/msys64/mingw64/bin/iverilog}
ALTERA_MF=${ALTERA_MF:-/c/apps/altera/13.0sp1/quartus/eda/sim_lib/altera_mf.v}
cd "$F"
"$IVERILOG" -g2012 -Wno-timescale -o /dev/null -s core_top \
  apf/common.v \
  core/core_top.v core/core_bridge_cmd.v core/mf_pllbase.v core/mf_pllbase/mf_pllbase_0002.v \
  core/osd_kbd.v core/pocket_video.v core/sound_i2s.sv core/sync_fifo.sv "$HERE/lint_stubs.v" "$ALTERA_MF" 2>&1 \
  | grep "core_top.v|osd_kbd.v|lint_stubs" | grep -v "Scope of" || true
echo "lint done"
