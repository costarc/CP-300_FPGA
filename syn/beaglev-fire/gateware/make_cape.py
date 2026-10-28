#!/usr/bin/env python3
"""Adds the CP-300 as a cape option (CAPE_OPTION:CP300) to a checkout of the BeagleV-Fire gateware repo.

    python make_cape.py <gateware repo dir>

It copies the framework's VERILOG_TEMPLATE cape, replaces its register block by the CP-300 (bvf_core_apb) plus a
42 MHz PF_CCC fed from PCLK, stages the HDL of this repository next to it and writes ADD_CAPE.tcl and the overlay.
Then:   libero SCRIPT:BUILD_BVF_GATEWARE.tcl "SCRIPT_ARGS:CAPE_OPTION:CP300 ..."   (from sources/FPGA-design)
"""
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
CAPES = os.path.join("sources", "FPGA-design", "script_support", "components", "CAPE")

# (path relative to REPO, VHDL or Verilog)
SOURCES = [
    "syn/beaglev-fire/rtl/bvf_core_apb.v", "syn/beaglev-fire/rtl/bvf_core_bus.v", "syn/beaglev-fire/rtl/apb_regbus.v",
    "syn/beaglev-fire/rtl/bvf_regs.v", "syn/beaglev-fire/rtl/bvf_fb.v", "syn/beaglev-fire/rtl/bvf_dataslot.v",
    "syn/beaglev-fire/rtl/bvf_trk_ram.v", "syn/beaglev-fire/rtl/bvf_audio.v",
    "syn/analogue/src/fpga/core/ht1080z_ext.vhd", "syn/analogue/src/fpga/core/io_ctrl_pocket.vhd",
    "syn/analogue/src/fpga/core/io_fw_pkg.vhd", "syn/analogue/src/fpga/core/cp300_roms_stub.vhd",
    "rtl/cp300/cp300_rom.vhd", "rtl/fdc/wd1793.vhd", "rtl/hdc/wd1010.vhd",
    "rtl/ht1080z/ht1080z.vhd", "rtl/ht1080z/videoctrl.vhd", "rtl/ht1080z/ps2kbd.vhd", "rtl/ht1080z/ps2reader.vhd",
]
T80 = ["T80_Pack", "T80_MCode", "T80_ALU", "T80_Reg", "T80", "T80s", "T80se", "T80a"]   # in compile order

CCC = """create_and_configure_core -core_vlnv {Actel:SgCore:PF_CCC:*} -component_name {PF_CCC_CP300} -params {\\
"GL0_0_IS_USED:true" \\
"GL0_0_OUT_FREQ:42" \\
"GL0_0_FABCLK_USED:true" \\
"PLL_IN_FREQ_0:50" \\
"PLL_REF_CLK_SEL_0:false" \\
"GL0_0_FREQ_SEL:false" }
"""

INSTANCE = """//--------CP-300 core (42 MHz from PCLK)
wire        clk42, pll_lock;
PF_CCC_CP300 pll42 (
        .REF_CLK_0        ( PCLK ),
        .PLL_POWERDOWN_N_0( 1'b1 ),
        .OUT0_FABCLK_0    ( clk42 ),
        .PLL_LOCK_0       ( pll_lock )
        );
wire        cp300_irq;
bvf_core_apb cp300 (
        .pclk   ( PCLK ),
        .presetn( PRESETN ),
        .paddr  ( APB_SLAVE_SLAVE_PADDR ),
        .psel   ( APB_SLAVE_SLAVE_PSEL ),
        .penable( APB_SLAVE_SLAVE_PENABLE ),
        .pwrite ( APB_SLAVE_SLAVE_PWRITE ),
        .pwdata ( APB_SLAVE_SLAVE_PWDATA ),
        .prdata ( APB_SLAVE_PRDATA ),
        .pready ( APB_SLAVE_SLAVE_PREADY ),
        .pslverr( APB_SLAVE_SLAVE_PSLVERR ),
        .clk    ( clk42 ),
        .pll_locked( pll_lock ),
        .irq    ( cp300_irq )
        );
"""


def sub_once(pattern, repl, text, what):
    """re.sub that must match exactly once: a template that changed shape stops the script instead of being skipped."""
    text, n = re.subn(pattern, repl, text, count=1, flags=re.S | re.M)
    if n != 1:
        raise SystemExit("%s not found in the template CAPE.v" % what)
    return text


def patch_cape(text):
    # ports PREADY / PSLVERR
    text = sub_once(r"^([ \t]*)APB_SLAVE_SLAVE_PRDATA,\n", r"\g<0>\1APB_SLAVE_SLAVE_PREADY,\n\1APB_SLAVE_SLAVE_PSLVERR,\n", text,
                    "APB_SLAVE_SLAVE_PRDATA port")
    text = sub_once(r"^output \[31:0\] APB_SLAVE_SLAVE_PRDATA;\n",
                    "\\g<0>output        APB_SLAVE_SLAVE_PREADY;\noutput        APB_SLAVE_SLAVE_PSLVERR;\n", text,
                    "APB_SLAVE_SLAVE_PRDATA declaration")
    # the register block is replaced
    text = sub_once(r"//--------apb_ctrl_status\napb_ctrl_status apb_ctrl_status_0\(.*?\);\n", lambda m: INSTANCE, text,
                    "apb_ctrl_status instance")
    # interrupt: bit 0 of INT (MSS_INT_F2M[8], PLIC 126) follows the disk request level. The template writes the
    # constant as 24'h0; any spelling of it is matched (an exact-text replace missed it in package 0.2.0)
    text = sub_once(r"^assign INT\[23:0\](\s*)=\s*24'h0+;", r"assign INT[23:0]\1= {23'h000000, cp300_irq};", text,
                    "assign INT[23:0]")
    # nothing reads the old control register any more
    text = text.replace("wire   [31:0]  apb_ctrl_status_0_control;\n", "", 1)
    return text


def strip_sim_only(path):
    """Libero's HDL parser does not honour `-- synthesis translate_off`; the staged copy loses those blocks."""
    with open(path) as f:
        text = f.read()
    pat = (r"^[ \t]*--\s*(?:synthesis|pragma)\s+translate_off.*?"
           r"^[ \t]*--\s*(?:synthesis|pragma)\s+translate_on[^\n]*\n")
    text = re.sub(pat, "", text, flags=re.S | re.M | re.I)
    with open(path, "w") as f:
        f.write(text)


def keep_in_registers(path, signal):
    """Synplify turns a small array with a reset into a RAM and then refuses its initial value: keep it in registers."""
    with open(path) as f:
        text = f.read()
    decl = re.search(r"^[ \t]*signal\s+%s\s*:[^;]*;[^\n]*\n" % signal, text, flags=re.M | re.I)
    if not decl:
        raise SystemExit("signal %s not found in %s" % (signal, path))
    init = re.sub(r"\s*:=\s*\(others\s*=>\s*\(others\s*=>\s*'0'\)\)\s*;", ";", decl.group(0), count=1)
    attr = ("  attribute syn_ramstyle : string;\n"
            "  attribute syn_ramstyle of %s : signal is \"registers\";\n" % signal)
    with open(path, "w") as f:
        f.write(text[:decl.start()] + init + attr + text[decl.end():])


def main():
    gw = os.path.abspath(sys.argv[1])
    cape_dir = os.path.join(gw, CAPES, "CP300")
    tmpl = os.path.join(gw, CAPES, "VERILOG_TEMPLATE")
    if os.path.isdir(cape_dir):
        shutil.rmtree(cape_dir)
    shutil.copytree(tmpl, cape_dir)
    hdl = os.path.join(cape_dir, "HDL")
    os.remove(os.path.join(hdl, "apb_ctrl_status.v"))
    with open(os.path.join(hdl, "CAPE.v")) as f:
        cape = f.read()
    with open(os.path.join(hdl, "CAPE.v"), "w") as f:
        f.write(patch_cape(cape))

    files = []
    for rel in SOURCES:
        src = os.path.join(REPO, rel)
        dst = os.path.join(hdl, os.path.basename(rel))
        shutil.copy(src, dst)
        if rel.endswith(".vhd"):
            strip_sim_only(dst)
        files.append(os.path.basename(rel))
    keep_in_registers(os.path.join(hdl, "wd1793.vhd"), "head_pos")
    t80 = []
    for n in T80:
        shutil.copy(os.path.join(REPO, "rtl", "T80", n + ".vhd"), os.path.join(hdl, n + ".vhd"))
        t80.append(n + ".vhd")

    # the framework imports the *.v files of the cape's HDL folder itself (MSS/scripts/hdl_source.tcl); the VHDL of
    # the core and the PLL are added here
    base = "script_support/components/CAPE/CP300/HDL/"
    with open(os.path.join(tmpl, "ADD_CAPE.tcl")) as f:
        add = f.read()
    add = add.replace("VERILOG_TEMPLATE", "CP300")
    vhdl = [n for n in t80 + files if n.endswith(".vhd")]
    imports = CCC + "".join("import_files -hdl_source {%s%s}\n" % (base, n) for n in vhdl) + "build_design_hierarchy\n\n"
    marker = "create_hdl_core -file $project_dir/hdl/CAPE.v"
    if marker not in add:
        raise SystemExit("create_hdl_core line not found in the template ADD_CAPE.tcl")
    add = add.replace(marker, imports + marker, 1)
    # PREADY and PSLVERR on the APB bus interface
    add = add.replace("hdl_core_add_bif -hdl_core_name {CAPE} -bif_definition {APB:AMBA:AMBA2:slave} -bif_name {BIF_1} -signal_map {} \n",
                      "hdl_core_add_bif -hdl_core_name {CAPE} -bif_definition {APB:AMBA:AMBA2:slave} -bif_name {BIF_1} -signal_map {} \n"
                      "hdl_core_assign_bif_signal -hdl_core_name {CAPE} -bif_name {BIF_1} -bif_signal_name {PREADY} -core_signal_name {APB_SLAVE_SLAVE_PREADY} \n"
                      "hdl_core_assign_bif_signal -hdl_core_name {CAPE} -bif_name {BIF_1} -bif_signal_name {PSLVERR} -core_signal_name {APB_SLAVE_SLAVE_PSLVERR} \n", 1)
    with open(os.path.join(cape_dir, "ADD_CAPE.tcl"), "w") as f:
        f.write(add)

    # the template's leds.dtso stays (the stock gateware has it too); its cape overlay is replaced
    dts = os.path.join(cape_dir, "device-tree-overlays")
    os.remove(os.path.join(dts, "verilog-cape.dtso"))
    shutil.copy(os.path.join(HERE, "CAPE", "CP300", "cp300.dtso"), os.path.join(dts, "cp300.dtso"))
    print("CP300 cape written to", cape_dir)


if __name__ == "__main__":
    main()
