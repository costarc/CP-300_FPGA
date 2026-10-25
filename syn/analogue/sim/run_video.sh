#!/bin/sh
# iverilog test of pocket_video.v against the timing of videoctrl.vhd.
#   syn/analogue/sim/run_video.sh
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
IVERILOG=${IVERILOG:-/c/apps/msys64/mingw64/bin/iverilog}
VVP=${VVP:-/c/apps/msys64/mingw64/bin/vvp}
mkdir -p "$HERE/out"
cd "$HERE/out"
"$IVERILOG" -g2012 -o tb_video.vvp "$HERE/tb_video.v" "$HERE/../src/fpga/core/pocket_video.v"
"$VVP" tb_video.vvp
