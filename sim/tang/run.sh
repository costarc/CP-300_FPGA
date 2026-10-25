#!/bin/sh
# Icarus Verilog simulation of the Tang frame buffer path (arbiter, Z80 RAM bridge, frame writer, scan-out)
# against a behavioural HyperRAM (9K) or SDRAM (20K) model. About a minute each.
#   sim/tang/run.sh          HyperRAM (Tang Nano 9K)
#   sim/tang/run.sh sdram    SDRAM    (Tang Nano 20K, with the real sdram_ctrl / sdram.v)
set -e
IVERILOG=${IVERILOG:-iverilog}
VVP=${VVP:-vvp}
cd "$(dirname "$0")"
T=../../rtl/tang
COMMON="tb_fb.v $T/psram_arb.v $T/ram_bridge.v $T/fb_writer.v $T/fb_scanout.v $T/sync_stable.v $T/osd.v"
if [ "$1" = sdram ]; then
  $IVERILOG -g2012 -DUSE_SDRAM -o tb_fb_sd.vvp $COMMON sdram_model.v $T/sdram_ctrl.v $T/sdram.v
  $VVP tb_fb_sd.vvp
else
  $IVERILOG -g2012 -o tb_fb.vvp $COMMON psram_model.v
  $VVP tb_fb.vvp
fi
