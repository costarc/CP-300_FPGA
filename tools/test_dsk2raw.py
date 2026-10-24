#!/usr/bin/env python3
"""Self-test for dsk2raw.py: builds synthetic JV1, JV3 and DMK images and checks the conversion.

    python tools/test_dsk2raw.py
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsk2raw as d  # noqa: E402


def pattern(t, s, sid, n=256):
    return bytes((t * 31 + s * 17 + sid * 7 + i) & 255 for i in range(n))


def check(raw, tracks, sides, ids, first):
    for t in range(tracks):
        for s in range(sides):
            for sid in ids:
                o = ((t * sides + s) * 18 + (sid - first)) * 256
                assert raw[o:o + 256] == pattern(t, s, sid), (t, s, sid)


def jv3(tracks, sides, ids, dd=True, extra_sizes=False):
    hdr, data = bytearray(), bytearray()
    for t in range(tracks):
        for s in range(sides):
            for sid in ids:
                flags = (0x80 if dd else 0) | (s << 4) | 0x00     # size code 0 = 256 bytes
                hdr += bytes([t, sid, flags])
                data += pattern(t, s, sid)
    if extra_sizes:                                              # a 512-byte sector must be skipped
        hdr += bytes([0, 99, 0x83])
        data += bytes(512)
    hdr += bytes([0xFF, 0xFF, 0xFF]) * (d.JV3_ENTRIES - len(hdr) // 3)
    return bytes(hdr) + b"\xFF" + bytes(data)


def dmk(tracks, sides, ids, dd, tlen=0x1900):
    blob = bytearray(16)
    blob[1], blob[2], blob[3] = tracks, tlen & 255, tlen >> 8
    if sides == 1:
        blob[4] |= 0x10
    if not dd:
        pass                                  # single density bytes are doubled (flags bits 6 and 7 clear)
    for t in range(tracks):
        for s in range(sides):
            trk = bytearray(tlen)
            pos = 128
            tab = []
            rep = 1 if dd else 2
            for sid in ids:
                def emit(bs):
                    nonlocal pos
                    for b in bs:
                        for _ in range(rep):
                            trk[pos] = b
                            pos += 1
                tab.append(pos | (0x8000 if dd else 0))
                emit([0xFE, t, s, sid, 1, 0, 0])                      # ID field, N=1 (256), CRC
                emit([0x4E] * 12 + ([0xA1] * 3 if dd else []))        # gap
                emit([0xFB])
                emit(pattern(t, s, sid))
                emit([0, 0])
                emit([0x4E] * 20)
            for i, p in enumerate(tab):
                struct.pack_into("<H", trk, 2 * i, p)
            blob += trk
    return bytes(blob)


def main():
    # JV3 double density, 18 sectors from 1, two sides, 5 tracks, plus a 512-byte sector to skip
    raw, info = d.convert(jv3(5, 2, range(1, 19), extra_sizes=True))
    assert info["format"] == "jv3" and info["sides"] == 2 and info["placed"] == 180 and info["skipped"] == 1, info
    check(raw, 5, 2, range(1, 19), 1)
    assert len(raw) > d.SINGLE_SIDED_MAX                          # padded to read as two sided
    # JV3 single density, 10 sectors from 0: warns about sector 0
    raw, info = d.convert(jv3(3, 1, range(0, 10), dd=False))
    assert info["first"] == 0 and info["notes"], info
    check(raw, 3, 1, range(0, 10), 0)
    # DMK, double density 18 sectors, two sided
    raw, info = d.convert(dmk(4, 2, range(1, 19), dd=True))
    assert info["format"] == "dmk" and info["placed"] == 144 and not info["warnings"], info
    check(raw, 4, 2, range(1, 19), 1)
    # DMK, single density (doubled bytes), 10 sectors, single sided
    raw, info = d.convert(dmk(3, 1, range(1, 11), dd=False))
    assert info["placed"] == 30 and not info["warnings"], info
    check(raw, 3, 1, range(1, 11), 1)
    # JV1
    jv1 = b"".join(pattern(t, 0, sid) for t in range(4) for sid in range(10))
    raw, info = d.convert(jv1)
    assert info["format"] == "jv1" and info["placed"] == 40, info
    check(raw, 4, 1, range(0, 10), 0)
    print("dsk2raw: all tests passed")


if __name__ == "__main__":
    main()
