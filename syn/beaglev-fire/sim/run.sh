#!/bin/sh
# BeagleV-Fire host side simulation (Icarus Verilog): sh run.sh
set -e
cd "$(dirname "$0")"
export PATH="/c/apps/msys64/mingw64/bin:$PATH"
iverilog -g2012 -o /tmp/tb_bvf.vvp tb_bvf.v ../rtl/axil_regbus.v ../rtl/bvf_regs.v ../rtl/bvf_fb.v \
	../rtl/bvf_dataslot.v ../rtl/bvf_trk_ram.v ../rtl/bvf_audio.v
vvp /tmp/tb_bvf.vvp | tail -60
