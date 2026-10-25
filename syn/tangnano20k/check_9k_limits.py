"""Fails if the Tang Nano 20K build uses more than a Tang Nano 9K (GW1NR-9) has, so that a design that
passes here also fits the 9K.   python check_9k_limits.py [impl/pnr/cp300_tn20k.rpt.txt]"""
import re, sys

LIMITS = {                      # GW1NR-LV9: logic = LUT4 + ALU + ROM16 + SSRAM, flip-flops, 18 Kbit BSRAM, PLL
    "Logic": 8640,
    "Register": 6771,
    "BSRAM": 26,
    "PLL": 2,
    "DSP": 0,
}

path = sys.argv[1] if len(sys.argv) > 1 else "impl/pnr/cp300_tn20k.rpt.txt"
txt = open(path, errors="ignore").read()
sec = txt[txt.index("3. Resource Usage Summary"):txt.index("4. I/O Bank Usage Summary")]

def used(name):
    m = re.search(r"^\s{2}%s\s*\|\s*(\d+)/" % re.escape(name), sec, re.M)
    return int(m.group(1)) if m else None

use = {k: used(k) for k in ("Logic", "Register", "PLL")}
# BSRAM block count: the sub lines (SP, SDPB, DPB, pROM) are blocks
b = 0
for kind in ("SP", "SDPB", "DPB", "pROM"):
    m = re.search(r"^\s+--%s\s*\|\s*(\d+)" % kind, sec, re.M)
    b += int(m.group(1)) if m else 0
use["BSRAM"] = b
m = re.search(r"^\s{2}DSP\s*\|\s*(\d+)%", sec, re.M)
use["DSP"] = 0 if (not m or m.group(1) == "0") else 1

ok = True
for k, lim in LIMITS.items():
    u = use[k]
    flag = "ok" if u is not None and u <= lim else "OVER"
    if flag != "ok": ok = False
    print("%-9s %6s / %-6s  %s" % (k, u, lim, flag))
print("fits a Tang Nano 9K" if ok else "DOES NOT FIT a Tang Nano 9K")
sys.exit(0 if ok else 1)
