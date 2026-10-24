#!/usr/bin/env python3
"""Self-test for dsk2dmk.py: builds synthetic JV1 and JV3 images, converts them to DMK, reads the DMK
back and compares every sector (data, density, data mark, CRC error flag).

    python tools/test_dsk2dmk.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsk2dmk as d  # noqa: E402


def pattern(t, s, sid, n=256):
    return bytes((t * 31 + s * 17 + sid * 7 + i) & 255 for i in range(n))


def jv3(entries):
    """entries: (track, side, id, data, dd, flags_extra)"""
    hdr, data = bytearray(), bytearray()
    for t, s, sid, dat, dd, extra in entries:
        code = {128: 1, 256: 0, 512: 3, 1024: 2}[len(dat)]
        hdr += bytes([t, sid, (0x80 if dd else 0) | (s << 4) | extra | code])
        data += dat
    hdr += bytes([0xFF, 0xFF, 0xFF]) * (d.JV3_ENTRIES - len(hdr) // 3)
    return bytes(hdr) + b"\xFF" + bytes(data)


def same(a, b):
    assert a.sectors.keys() == b.sectors.keys(), (sorted(a.sectors), sorted(b.sectors))
    for k in a.sectors:
        x, y = a.sectors[k], b.sectors[k]
        assert (x.data, x.dd, x.dam, x.bad_crc) == (y.data, y.dd, y.dam, y.bad_crc), k


def main():
    # JV3: double density from 0, two sides, a deleted mark, a bad CRC, a 512-byte sector
    ent = [(t, s, sid, pattern(t, s, sid), True, 0) for t in range(4) for s in range(2) for sid in range(18)]
    ent[5] = (0, 0, 5, pattern(0, 0, 5), True, 0x20)             # deleted data mark (F8)
    ent[40] = (1, 0, 4, pattern(1, 0, 4), True, 0x08)            # CRC error
    ent.append((4, 0, 30, pattern(4, 0, 30, 512), True, 0))      # alone on its track
    src = d.read_jv3(jv3(ent))
    blob, info = d.convert(jv3(ent))
    assert info["format"] == "jv3" and info["sides"] == 2 and info["tracks"] == 5, info
    out = d.read_dmk(blob)
    same(src, out)
    assert out.sectors[(0, 0, 5)].dam == 0xF8 and out.sectors[(1, 0, 4)].bad_crc and not out.warnings
    assert len(blob) == 16 + 5 * 2 * d.TLEN and blob[4] == 0
    # JV3 single density from 1: single sided, user data mark FA
    ent = [(t, 0, sid, pattern(t, 0, sid), False, 0) for t in range(3) for sid in range(1, 11)]
    ent[3] = (0, 0, 4, pattern(0, 0, 4), False, 0x20)
    blob, info = d.convert(jv3(ent))
    out = d.read_dmk(blob)
    same(d.read_jv3(jv3(ent)), out)
    assert out.sectors[(0, 0, 4)].dam == 0xFA and not out.sectors[(0, 0, 4)].dd and blob[4] == 0x10
    # JV1
    jv1 = b"".join(pattern(t, 0, sid) for t in range(5) for sid in range(10))
    blob, info = d.convert(jv1)
    assert info["format"] == "jv1" and info["sectors"] == 50, info
    out = d.read_dmk(blob)
    same(d.read_jv1(jv1), out)
    # a DMK is copied unchanged
    again, info = d.convert(blob)
    assert again == blob and info["format"] == "dmk"
    print("dsk2dmk: all tests passed")


if __name__ == "__main__":
    main()
