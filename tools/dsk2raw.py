#!/usr/bin/env python3
"""Convert TRS-80 disk images (JV1, JV3, DMK) to the raw layout the CP-300 FPGA reads.

    python tools/dsk2raw.py in.dsk out.dsk [--format auto|jv1|jv3|dmk|hfe] [--first N]
                            [--tracks N] [--sides N]
    python tools/dsk2raw.py indir outdir          convert every image in a folder (8.3 names + INDEX.TXT)

Raw layout (see rtl/fdc/wd1793.vhd): 18 sectors of 256 bytes per track, tracks in order;
a double sided disk interleaves the sides (track 0 side 0, track 0 side 1, track 1 ...).
The sector ID decides the slot: slot = ID - first, where `first` is the lowest 256-byte sector
ID on the disk (0 or 1, or --first). The controller accepts sector IDs 1..18, so disks that
number their sectors from 0 convert, but the DOS on them will ask for sector 0, which the
controller refuses; a warning says so. Density is not kept: a single density track (10 sectors)
just fills the first slots of its track.

Only 256-byte sectors are converted. Sectors with other sizes or with IDs outside the 18 slots
are skipped and counted. The firmware treats a file larger than 80 x 18 x 256 bytes as double
sided, so a double sided result that would be smaller than that is padded by one track pair.

Formats:
  JV1  no header, 256-byte sectors, 10 per track, single sided, single density
  JV3  Jeff Vavasour's, https://www.tim-mann.org/trs80/dskspec.html
  DMK  David Keil's, header 16 bytes + per track a 128-byte IDAM table (offsets with bit 15 = DD)
  HFE  HxC Floppy Emulator v1 ("HXCPICFE"): the bit cells of every track, decoded here (FM and MFM)
"""
import argparse
import os
import re
import struct
import sys

SECTORS = 18
SECSIZE = 256
TRACK_BYTES = SECTORS * SECSIZE
SINGLE_SIDED_MAX = 80 * TRACK_BYTES      # the firmware: larger files are two sided


class Disk:
    """What the readers collect: sectors[(track, side, id)] = 256 bytes."""

    def __init__(self):
        self.sectors = {}
        self.sides = 1
        self.tracks = 0
        self.skipped_size = 0
        self.crc_errors = 0
        self.warnings = []

    def add(self, track, side, sid, data, crc_error=False):
        if len(data) != SECSIZE:
            self.skipped_size += 1
            return
        if crc_error:
            self.crc_errors += 1
        self.sectors[(track, side, sid)] = data
        self.sides = max(self.sides, side + 1)
        self.tracks = max(self.tracks, track + 1)


# ---- JV1 ----------------------------------------------------------------

def read_jv1(blob):
    d = Disk()
    for n in range(len(blob) // SECSIZE):
        d.add(n // 10, 0, n % 10, blob[n * SECSIZE:(n + 1) * SECSIZE])
    return d


# ---- JV3 ----------------------------------------------------------------

JV3_ENTRIES = 2901
JV3_HEADER = JV3_ENTRIES * 3 + 1


def jv3_size(flags, free):
    code = flags & 3
    return 128 << (code ^ 2 if free else code ^ 1)


def jv3_looks_valid(blob):
    if len(blob) < JV3_HEADER:
        return False
    pos = JV3_HEADER
    used = 0
    for i in range(JV3_ENTRIES):
        t, s, f = blob[i * 3:i * 3 + 3]
        free = (t == 0xFF and s == 0xFF)
        if free:
            break
        pos += jv3_size(f, False)
        used += 1
        if pos > len(blob):
            return False
    return used > 0


def read_jv3(blob):
    d = Disk()
    base = 0
    while base + JV3_HEADER <= len(blob):
        pos = base + JV3_HEADER
        used = 0
        for i in range(JV3_ENTRIES):
            t, s, f = blob[base + i * 3:base + i * 3 + 3]
            free = (t == 0xFF and s == 0xFF)
            size = jv3_size(f, free)
            if pos + size > len(blob):
                pos = len(blob)
                break
            if not free:
                used += 1
                d.add(t, (f >> 4) & 1, s, blob[pos:pos + size], bool(f & 0x08))
            pos += size
        base = pos            # a second header block follows the data of the first one
        if used == 0:
            break
    return d


# ---- DMK ----------------------------------------------------------------

def dmk_looks_valid(blob):
    if len(blob) < 16 + 128:
        return False
    ntracks = blob[1]
    tlen = blob[2] | (blob[3] << 8)
    if blob[0] not in (0x00, 0xFF) or not 1 <= ntracks <= 100 or tlen < 128 + 16 or tlen > 0x2940:
        return False
    if blob[12:16] != b"\0\0\0\0":
        return False
    # the first track must start with a plausible IDAM table
    first = struct.unpack_from("<H", blob, 16)[0] & 0x3FFF
    return 128 <= first < tlen


def read_dmk(blob):
    d = Disk()
    ntracks = blob[1]
    tlen = blob[2] | (blob[3] << 8)
    flags = blob[4]
    sides = 1 if flags & 0x10 else 2
    doubled = not (flags & 0xC0)     # single density bytes are stored twice
    for t in range(ntracks):
        for s in range(sides):
            off = 16 + (t * sides + s) * tlen
            trk = blob[off:off + tlen]
            if len(trk) < tlen:
                if len(trk) >= 128:
                    d.warnings.append(f"track {t} side {s} is truncated")
                    trk = trk + bytes(tlen - len(trk))
                else:
                    d.warnings.append(f"the file ends before track {t} side {s}")
                    return d
            ptrs = [struct.unpack_from("<H", trk, 2 * i)[0] for i in range(64)]
            for i, p in enumerate(ptrs):
                if p == 0:
                    break
                dd = bool(p & 0x8000)
                pos = p & 0x3FFF
                step = 2 if (doubled and not dd) else 1
                nxt = None
                for q in ptrs[i + 1:]:
                    if q:
                        nxt = q & 0x3FFF
                        break
                limit = nxt if nxt else tlen

                def at(n):
                    k = pos + n * step
                    return trk[k] if k < tlen else None

                if at(0) != 0xFE:
                    d.warnings.append(f"track {t} side {s}: IDAM {i} does not start with FE")
                    continue
                c, h, r, n = at(1), at(2), at(3), at(4)
                if None in (c, h, r, n) or n > 3:
                    d.warnings.append(f"track {t} side {s}: bad ID field {i}")
                    continue
                size = 128 << n
                # the data mark follows the ID field after a gap (within 64 bytes)
                dam = None
                for k in range(7, 70):
                    if pos + k * step >= limit:
                        break
                    if at(k) in (0xF8, 0xF9, 0xFA, 0xFB):
                        dam = k
                        break
                if dam is None:
                    d.warnings.append(f"track {t} side {s} sector {r}: no data mark")
                    continue
                data = bytes(at(dam + 1 + j) if at(dam + 1 + j) is not None else 0 for j in range(size))
                if c != t:
                    d.warnings.append(f"track {t} side {s}: sector ID says track {c}")
                d.add(t, s, r, data)
    return d


# ---- HFE (HxC Floppy Emulator, v1) ----------------------------------------

def crc16(data, crc=0xFFFF):
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


_BITS = [format(b, "08b")[::-1] for b in range(256)]       # HFE stores the first cell in bit 0


def fm_word(data, clock=0xC7):
    return "".join(f"{(clock >> i) & 1}{(data >> i) & 1}" for i in range(7, -1, -1))


_FM_ID = fm_word(0xFE)
_FM_DAM = {m: fm_word(m) for m in (0xF8, 0xF9, 0xFA, 0xFB)}
_MFM_SYNC = "0100010010001001" * 3                         # A1 A1 A1 with the missing clock


def decode_cells(cells, start, count, fm):
    """Decode `count` data bytes starting at cell index `start`."""
    out = bytearray()
    for k in range(count):
        o = start + 16 * k
        w = cells[o + 1:o + 16:2]
        if len(w) < 8:
            return None
        out.append(int(w, 2))
    return bytes(out)


def hfe_track_events(cells):
    """[(position, 'id'|'dam', fm, mark, first data cell)] sorted by position."""
    ev = []
    for m in re.finditer("(?=" + _FM_ID + ")", cells):
        ev.append((m.start(), "id", True, 0xFE, m.start() + 16))
    for mark, pat in _FM_DAM.items():
        for m in re.finditer("(?=" + pat + ")", cells):
            ev.append((m.start(), "dam", True, mark, m.start() + 16))
    for m in re.finditer("(?=" + _MFM_SYNC + ")", cells):
        e = m.start() + 48
        mk = decode_cells(cells, e, 1, False)
        if mk and mk[0] == 0xFE:
            ev.append((m.start(), "id", False, 0xFE, e + 16))
        elif mk and mk[0] in (0xF8, 0xF9, 0xFA, 0xFB):
            ev.append((m.start(), "dam", False, mk[0], e + 16))
    ev.sort()
    return ev


def read_hfe(blob):
    d = Disk()
    if blob[:8] != b"HXCPICFE":
        sys.exit("error: not an HFE v1 file (HFE v3 is not supported)")
    ntracks, nsides = blob[9], blob[10]
    lut = struct.unpack_from("<H", blob, 18)[0] * 512
    for t in range(ntracks):
        off, tlen = struct.unpack_from("<HH", blob, lut + 4 * t)
        off *= 512
        raw = blob[off:off + ((tlen + 511) // 512) * 512]
        for s in range(nsides):
            side = b"".join(raw[i + s * 256:i + s * 256 + 256] for i in range(0, len(raw), 512))[:tlen // 2]
            cells = "".join(_BITS[b] for b in side)
            ev = hfe_track_events(cells)
            for i, (pos, kind, fm, mark, data0) in enumerate(ev):
                if kind != "id":
                    continue
                idf = decode_cells(cells, data0, 6, fm)
                if idf is None:
                    continue
                c, h, r, n = idf[:4]
                if n > 3:
                    continue
                size = 128 << n
                nxt = next((e for e in ev[i + 1:] if e[1] == "id"), None)
                limit = nxt[0] if nxt else len(cells)
                dam = next((e for e in ev[i + 1:] if e[1] == "dam" and e[2] == fm and e[0] < limit
                            and e[0] - data0 < 16 * 80), None)
                if dam is None:
                    d.warnings.append(f"track {t} side {s} sector {r}: no data mark")
                    continue
                data = decode_cells(cells, dam[4], size + 2, fm)
                if data is None:
                    d.warnings.append(f"track {t} side {s} sector {r}: data field cut short")
                    continue
                pre = bytes([0xA1] * 3) if not fm else b""
                bad = crc16(pre + bytes([dam[3]]) + data[:size]) != (data[size] << 8 | data[size + 1])
                if c != t:
                    d.warnings.append(f"track {t} side {s}: sector ID says track {c}")
                d.add(t, s, r, data[:size], bad)
    return d


# ---- conversion ---------------------------------------------------------

def detect(blob):
    if blob[:8] == b"HXCPICFE":
        return "hfe"
    if dmk_looks_valid(blob):
        return "dmk"
    if jv3_looks_valid(blob):
        return "jv3"
    if len(blob) % (10 * SECSIZE) == 0 and len(blob) > 0:
        return "jv1"
    sys.exit("error: cannot tell the format (use --format)")


def convert(blob, fmt="auto", first=None, tracks=None, sides=None):
    if fmt == "auto":
        fmt = detect(blob)
    disk = {"jv1": read_jv1, "jv3": read_jv3, "dmk": read_dmk, "hfe": read_hfe}[fmt](blob)
    if not disk.sectors:
        sys.exit("error: no 256-byte sectors found")
    ids = [k[2] for k in disk.sectors]
    if first is None:
        first = min(ids)
        if first > 1:
            first = 1
    notes = []
    if first == 0:
        notes.append("sector IDs start at 0; the controller only accepts 1..18, so a DOS that asks "
                     "for sector 0 will get an error")
    nsides = sides or disk.sides
    ntracks = tracks or disk.tracks
    out = bytearray(ntracks * nsides * TRACK_BYTES)
    placed = skipped = 0
    for (t, s, sid), data in disk.sectors.items():
        slot = sid - first
        if not (0 <= slot < SECTORS) or t >= ntracks or s >= nsides:
            skipped += 1
            continue
        o = ((t * nsides + s) * SECTORS + slot) * SECSIZE
        out[o:o + SECSIZE] = data
        placed += 1
    if nsides == 2 and len(out) <= SINGLE_SIDED_MAX:
        out += bytes(SINGLE_SIDED_MAX + TRACK_BYTES * 2 - len(out))
        notes.append("padded so the firmware sees a double sided disk")
    info = {"format": fmt, "tracks": ntracks, "sides": nsides, "first": first, "placed": placed,
            "skipped": skipped + disk.skipped_size, "crc_errors": disk.crc_errors,
            "warnings": disk.warnings, "notes": notes}
    return bytes(out), info


NL = chr(10)
EXTS = (".dsk", ".dmk", ".hfe", ".jv1", ".jv3")


def short_name(stem, taken):
    """8.3 name that survives on the SD card (the firmware does not read long names)."""
    m = re.match(r"DSKA(\d{4})_(.*)", stem.upper())
    if m:
        body = re.sub(r"[^A-Z0-9]", "", m.group(2)) or "DISK"
        base = body[:5] + m.group(1)[1:]
    else:
        base = (re.sub(r"[^A-Z0-9]", "", stem.upper()) or "DISK")[:8]
    name, n = base, 1
    while name + ".DSK" in taken:
        n += 1
        name = base[:8 - len(str(n))] + str(n)
    return name + ".DSK"


def batch(indir, outdir, force=False):
    os.makedirs(outdir, exist_ok=True)
    files = sorted(f for f in os.listdir(indir) if f.lower().endswith(EXTS))
    # the same disk as DMK/DSK and as HFE: use the DMK
    rank = {".dmk": 0, ".dsk": 0, ".jv3": 0, ".jv1": 0, ".hfe": 1}
    best = {}
    for f in files:
        stem, ext = os.path.splitext(f)
        k = stem.upper()
        if k not in best or rank[ext.lower()] < rank[os.path.splitext(best[k])[1].lower()]:
            best[k] = f
    taken = {n.upper() for n in os.listdir(outdir)}
    lines, seen, ok = [], {}, 0
    for f in files:
        stem = os.path.splitext(f)[0]
        if best[stem.upper()] != f:
            lines.append(f"{f:40s} skipped: the same disk is converted from {best[stem.upper()]}")
            continue
        try:
            raw, info = convert(open(os.path.join(indir, f), "rb").read())
        except SystemExit as e:
            lines.append(f"{f:40s} FAILED: {e}")
            print(f"{f}: FAILED: {e}")
            continue
        out = short_name(stem, taken)
        taken.add(out)
        open(os.path.join(outdir, out), "wb").write(raw)
        ok += 1
        same = seen.setdefault(hash(raw), out)
        extra = []
        if same != out:
            extra.append(f"identical to {same}")
        if info["first"] == 0:
            extra.append("sector IDs start at 0")
        if info["skipped"]:
            extra.append(f"{info['skipped']} sectors skipped")
        if info["crc_errors"]:
            extra.append(f"{info['crc_errors']} CRC errors")
        if info["warnings"]:
            extra.append(f"{len(info['warnings'])} warnings, first: {info['warnings'][0]}")
        line = (f"{out:13s} <- {f:36s} {info['format'].upper()} {info['tracks']:2d} tracks "
                f"{info['sides']} side(s) {info['placed']:4d} sectors  " + "; ".join(extra))
        lines.append(line.rstrip())
        print(line.rstrip())
    with open(os.path.join(outdir, "INDEX.TXT"), "w") as fh:
        fh.write("Converted by tools/dsk2raw.py: 18 x 256 raw images for the CP-300 FPGA."+NL)
        fh.write("Copy the *.DSK files to /CP300 on the SD card."+NL+NL)
        fh.write(NL.join(lines) + NL)
    print(f"{ok} images written to {outdir}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--format", choices=["auto", "jv1", "jv3", "dmk", "hfe"], default="auto")
    ap.add_argument("--first", type=int, help="ID of the first sector (default: the lowest 256-byte ID, at most 1)")
    ap.add_argument("--tracks", type=int, help="number of tracks in the output (default: highest track + 1)")
    ap.add_argument("--sides", type=int, choices=[1, 2], help="force the number of sides")
    a = ap.parse_args()
    if os.path.isdir(a.input):
        batch(a.input, a.output)
        return
    blob = open(a.input, "rb").read()
    out, info = convert(blob, a.format, a.first, a.tracks, a.sides)
    open(a.output, "wb").write(out)
    print(f"{info['format'].upper()}: {info['tracks']} tracks, {info['sides']} side(s), first sector ID {info['first']}: "
          f"{info['placed']} sectors written, {info['skipped']} skipped, {info['crc_errors']} with CRC errors; "
          f"{len(out)} bytes -> {a.output}")
    for n in info["notes"]:
        print("note:", n)
    for w in info["warnings"][:20]:
        print("warning:", w)
    if len(info["warnings"]) > 20:
        print(f"warning: {len(info['warnings']) - 20} more")


if __name__ == "__main__":
    main()
