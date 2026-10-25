#!/bin/sh
# Build the Analogue Pocket IO controller firmware with SDCC 4.6 and regenerate
# syn/analogue/src/fpga/core/io_fw_pkg.vhd.
#   firmware/pocket/build.sh
# Same compiler rules as firmware/build.sh (SDCC 4.6, --sdcccall 1).
set -e
cd "$(dirname "$0")"
SDCC_BIN=${SDCC_BIN:-/c/Apps/SDCC/bin}
export PATH="$SDCC_BIN:$PATH"
case "$(sdcc --version)" in
  *" 4.6."*) ;;
  *) echo "error: firmware/pocket/build.sh needs SDCC 4.6 (found: $(sdcc --version | head -1))" >&2; exit 1 ;;
esac
mkdir -p out
cd out
sdasz80 -plosgff crt0.rel ../../crt0.s
for f in main slotfile; do
  sdcc -mz80 --sdcccall 1 --std-sdcc99 -DPOCKET -I.. -I../.. -c ../$f.c -o $f.rel
done
sdcc -mz80 --sdcccall 1 --std-sdcc99 -DPOCKET -I.. -I../.. -c ../../dmk.c -o dmk.rel
sdcc -mz80 --sdcccall 1 --no-std-crt0 --code-loc 0x0100 --data-loc 0x4000 \
  crt0.rel main.rel slotfile.rel dmk.rel -o io_fw.ihx
python ../../../tools/mkfw.py io_fw.ihx ../../../syn/analogue/src/fpga/core/io_fw_pkg.vhd
cat io_fw.map | grep -E "^ +(_CODE|_DATA|_INITIALIZED|_HEADER) " || true
