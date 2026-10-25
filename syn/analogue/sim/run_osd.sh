#!/bin/sh
# iverilog test of the on-screen keyboard; writes sim/out/osd_<n>.ppm (and .png when PIL is there).
#   syn/analogue/sim/run_osd.sh
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$HERE/../../..
IVERILOG=${IVERILOG:-/c/apps/msys64/mingw64/bin/iverilog}
VVP=${VVP:-/c/apps/msys64/mingw64/bin/vvp}
mkdir -p "$HERE/out"
python - "$ROOT/roms/900-65.BIN" "$HERE/out/font.hex" <<'PY'
import sys
d = open(sys.argv[1], "rb").read()
open(sys.argv[2], "w").write("".join("%02X\n" % b for b in d))
PY
cd "$HERE/out"
"$IVERILOG" -g2012 -o tb_osd.vvp "$HERE/tb_osd_kbd.v" "$HERE/../src/fpga/core/osd_kbd.v" "$HERE/osd_font_sim.v"
"$VVP" tb_osd.vvp
python - <<'PY'
import glob
try:
    from PIL import Image
except ImportError:
    raise SystemExit
for p in sorted(glob.glob("osd_*.ppm")):
    Image.open(p).save(p[:-4] + ".png")
PY
