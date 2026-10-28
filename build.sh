#!/bin/sh
# Command line build of the CP-300 FPGA.
#
#   ./build.sh [all | roms | firmware | fpga | test ...]      (default: all = firmware fpga)
#
#   roms      python tools/mkroms.py          roms/*.BIN -> roms/cp300_roms_pkg.vhd (simulation only)
#   firmware  firmware/build.sh               IO controller C code -> rtl/io/io_fw_pkg.vhd (SDCC 4.6)
#   fpga      quartus_sh --flow compile       syn/de0/output_files/cp300_de0.sof and cp300_de0.pof
#   test      the PC tests (disk converter, FAT code, keyboard matrix scanner)
#
# Tools: Python 3, SDCC 4.6 (SDCC_BIN=<dir> if it is not in C:/Apps/SDCC/bin), Quartus II 13.0sp1
# (QUARTUS_BIN=<dir> if quartus_sh is not on the PATH), gcc for the host tests.
set -e
ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"

steps=${*:-all}
case " $steps " in *" all "*) steps="firmware fpga" ;; esac

# quartus_sh: on the PATH, QUARTUS_BIN, or the usual Windows install
quartus() {
  if command -v quartus_sh >/dev/null 2>&1; then quartus_sh "$@"
  elif [ -n "$QUARTUS_BIN" ]; then "$QUARTUS_BIN/quartus_sh" "$@"
  elif [ -x /c/altera/13.0sp1/quartus/bin64/quartus_sh.exe ]; then /c/altera/13.0sp1/quartus/bin64/quartus_sh "$@"
  elif [ -x /c/apps/altera/13.0sp1/quartus/bin64/quartus_sh.exe ]; then /c/apps/altera/13.0sp1/quartus/bin64/quartus_sh "$@"
  else echo "error: quartus_sh not found (put it on the PATH or set QUARTUS_BIN)" >&2; exit 1
  fi
}

for step in $steps; do
  case "$step" in
    roms)
      echo "== ROM package"
      python tools/mkroms.py
      ;;
    firmware)
      echo "== IO controller firmware"
      sh firmware/build.sh
      ;;
    fpga)
      echo "== Quartus compile (a few minutes)"
      (cd syn/de0 && quartus --flow compile cp300_de0)
      out=syn/de0/output_files
      grep -E "Fitter Status|Total logic elements|Total memory bits" "$out/cp300_de0.fit.summary" || true
      # every slack in the timing summary must be positive
      worst=$(grep -i "slack" "$out/cp300_de0.sta.summary" | sed 's/.*: *//' | sort -n | head -1)
      echo "Worst slack: $worst ns"
      case "$worst" in -*) echo "error: timing not met" >&2; exit 1 ;; esac
      ls -l "$out/cp300_de0.sof" "$out/cp300_de0.pof"
      ;;
    test)
      echo "== PC tests"
      python tools/test_dsk2dmk.py
      if command -v gcc >/dev/null 2>&1; then
        tmp=$(mktemp -d)
        python tools/mkfat.py "$tmp/card.img" --clusters 4200 --spc 1
        gcc -DHOST_TEST -I firmware -o "$tmp/host_fat" firmware/tests/host_fat.c firmware/fat.c
        "$tmp/host_fat" "$tmp/card.img" | tail -1
        rm -rf "$tmp"
      else
        echo "gcc not found: skipping the FAT test"
      fi
      if command -v ghdl >/dev/null 2>&1; then sh sim/run_kbd.sh 2>&1 | grep "all tests passed"; else echo "ghdl not found: skipping the keyboard matrix test"; fi
      echo "(tools/test_dmk.py checks the DMK reader on real images: python tools/test_dmk.py a.dmk b.dmk)"
      ;;
    *)
      echo "usage: $0 [all | roms | firmware | fpga | test]" >&2
      exit 1
      ;;
  esac
done
