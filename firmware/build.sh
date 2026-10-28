#!/bin/sh
# Build the IO controller firmware with SDCC and regenerate rtl/io/io_fw_pkg.vhd.
#   firmware/build.sh
# SDCC 4.6 only, with its native calling convention (--sdcccall 1, the default of 4.6's z80.lib).
# Do not mix versions or conventions across the project: the build stops on any other SDCC.
# Pass SDCC_BIN=... to use another install of 4.6.
set -e
cd "$(dirname "$0")"
SDCC_BIN=${SDCC_BIN:-/c/Apps/SDCC/bin}
export PATH="$SDCC_BIN:$PATH"
case "$(sdcc --version)" in
  *" 4.6."*) ;;
  *) echo "error: firmware/build.sh needs SDCC 4.6 (found: $(sdcc --version | head -1))" >&2; exit 1 ;;
esac
mkdir -p out
cd out
sdasz80 -plosgff crt0.rel ../crt0.s
for f in main sd fat dmk; do
  sdcc -mz80 --sdcccall 1 --std-sdcc99 --max-allocs-per-node 30000 -c ../$f.c -o $f.rel
done
sdcc -mz80 --sdcccall 1 --no-std-crt0 --code-loc 0x0100 --data-loc 0x4000 \
  crt0.rel main.rel sd.rel fat.rel dmk.rel -o io_fw.ihx
python ../../tools/mkfw.py io_fw.ihx
cat io_fw.map | grep -E "^ +(_CODE|_DATA|_INITIALIZED|_HEADER) " || true
