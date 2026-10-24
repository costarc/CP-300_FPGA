#!/usr/bin/env python3
"""Build a small test SD card image (MBR + one FAT16 or FAT32 partition).

    python tools/mkfat.py out.img [--fat32] [--files dir]

The image gets /CP300 with the files from --files (default: generated
test files). Used by firmware/tests/ and sim/ to exercise the IO controller
firmware without a card. File data is deterministic: byte i of file F is
(i * 7 + len(F)) & 255 unless the file comes from --files.
"""
import argparse
import os
import struct


def z80_asm(items, org):
    """Tiny assembler for the boot sector: items are bytes, ("label", name), or
    (opcode_bytes, kind, name) with kind "rel" (JR/DJNZ) or "abs" (16-bit address)."""
    labels, pos = {}, org
    for it in items:
        if isinstance(it, bytes):
            pos += len(it)
        elif it[0] == "label":
            labels[it[1]] = pos
        else:
            pos += len(it[0]) + (1 if it[1] == "rel" else 2)
    out, pos = bytearray(), org
    for it in items:
        if isinstance(it, bytes):
            out += it
            pos += len(it)
        elif it[0] == "label":
            continue
        else:
            op, kind, name = it
            pos += len(op) + (1 if kind == "rel" else 2)
            out += op
            if kind == "rel":
                d = labels[name] - pos
                assert -128 <= d < 128, name
                out.append(d & 255)
            else:
                out += struct.pack("<H", labels[name])
    return bytes(out), labels


def boot_disk():
    """Raw 40 track x 18 x 256 disk. The boot sector prints "BOOT OK" on the first screen line,
    then tests the controller: SEEK track 5, READ sector 3 (checks the data), WRITE it back
    changed, READ again and compare. It prints "FDC OK " or "FDC BAD" on the second line.
    Track 5 sector 3 holds byte i = i ^ 5A."""
    I = lambda *b: bytes(b)
    prog = [
        (I(0x21), "abs", "msg_boot"), I(0x11, 0x00, 0x3C, 0x01, 0x07, 0x00, 0xED, 0xB0),
        I(0x3E, 0x81, 0xD3, 0xF4),                       # drive 0
        I(0x3E, 0x05, 0xD3, 0xF3, 0x3E, 0x10, 0xD3, 0xF0),   # SEEK 5
        (I(0xCD), "abs", "wbusy"),
        I(0x3E, 0x03, 0xD3, 0xF2, 0x3E, 0x80, 0xD3, 0xF0),   # READ sector 3
        I(0x21, 0x00, 0x44), (I(0xCD), "abs", "rdsec"),
        I(0x3A, 0x00, 0x44, 0xFE, 0x5A), (I(0x20), "rel", "bad"),
        I(0x3A, 0xFF, 0x44, 0xFE, 0xA5), (I(0x20), "rel", "bad"),
        I(0x3E, 0x77, 0x32, 0x00, 0x44),                 # change byte 0
        I(0x3E, 0x03, 0xD3, 0xF2, 0x3E, 0xA0, 0xD3, 0xF0),   # WRITE sector 3
        I(0x21, 0x00, 0x44), (I(0xCD), "abs", "wrsec"),
        I(0x3E, 0x03, 0xD3, 0xF2, 0x3E, 0x80, 0xD3, 0xF0),   # READ it back
        I(0x21, 0x00, 0x45), (I(0xCD), "abs", "rdsec"),
        I(0x3A, 0x00, 0x45, 0xFE, 0x77), (I(0x20), "rel", "bad"),
        I(0x3A, 0x01, 0x45, 0xFE, 0x5B), (I(0x20), "rel", "bad"),
        (I(0x21), "abs", "msg_ok"), (I(0x18), "rel", "print"),
        ("label", "bad"), (I(0x21), "abs", "msg_bad"),
        ("label", "print"), I(0x11, 0x40, 0x3C, 0x01, 0x07, 0x00, 0xED, 0xB0),
        ("label", "halt"), (I(0x18), "rel", "halt"),
        ("label", "wbusy"), I(0xDB, 0xF0, 0xCB, 0x47), (I(0x20), "rel", "wbusy"), I(0xC9),
        ("label", "rdsec"), I(0xDB, 0xF0, 0xCB, 0x4F), (I(0x28), "rel", "rdn"),
        I(0xDB, 0xF3, 0x77, 0x23), (I(0x18), "rel", "rdsec"),
        ("label", "rdn"), I(0xCB, 0x47), (I(0x20), "rel", "rdsec"), I(0xC9),
        ("label", "wrsec"), I(0xDB, 0xF0, 0xCB, 0x4F), (I(0x28), "rel", "wrn"),
        I(0x7E, 0xD3, 0xF3, 0x23), (I(0x18), "rel", "wrsec"),
        ("label", "wrn"), I(0xCB, 0x47), (I(0x20), "rel", "wrsec"), I(0xC9),
        ("label", "msg_boot"), b"BOOT OK",
        ("label", "msg_ok"), b"FDC OK ",
        ("label", "msg_bad"), b"FDC BAD",
    ]
    code, _ = z80_asm(prog, 0x4300)
    assert len(code) <= 256
    disk = bytearray(40 * 18 * 256)
    disk[0:len(code)] = code
    o = (5 * 18 + 2) * 256
    for i in range(256):
        disk[o + i] = i ^ 0x5A
    return bytes(disk)


def test_files():
    def gen(n, salt):
        return bytes((i * 7 + salt) & 255 for i in range(n))
    cfg = (b"C3" + b"BOOT    DSK" + b" " * 44).ljust(512, b"\0")
    return {
        "BOOT.DSK": boot_disk(),
        "TRSDOS13.DSK": gen(40 * 18 * 256, 1),
        "LDOS.DSK": gen(40 * 18 * 256 + 512, 2),
        "GAME.CAS": gen(5000, 3),
        "CP300.CFG": cfg,
    }


def short_name(name):
    base, _, ext = name.upper().rpartition(".")
    if not base:
        base, ext = ext, ""
    return (base[:8].ljust(8) + ext[:3].ljust(3)).encode("ascii")


def build(path, fat32, files, clusters=None, spc_arg=None):
    spc = spc_arg or (1 if fat32 else 4)
    if fat32:
        total_clusters = 66000          # >= 65525 so it really is FAT32
        rsvd = 32
        root_ents = 0
    else:
        total_clusters = clusters or 20000
        rsvd = 1
        root_ents = 512
    ent_size = 4 if fat32 else 2
    fat_secs = (total_clusters + 2) * ent_size // 512 + 1
    root_secs = root_ents * 32 // 512
    vol_secs = rsvd + 2 * fat_secs + root_secs + total_clusters * spc
    part_start = 63
    img = bytearray((part_start + vol_secs) * 512)

    # MBR
    img[446 + 4] = 0x0C if fat32 else 0x06
    struct.pack_into("<II", img, 446 + 8, part_start, vol_secs)
    img[510:512] = b"\x55\xAA"

    v = part_start * 512
    boot = bytearray(512)
    boot[0:3] = b"\xEB\x58\x90" if fat32 else b"\xEB\x3C\x90"
    boot[3:11] = b"MSWIN4.1"
    struct.pack_into("<HBHBH", boot, 11, 512, spc, rsvd, 2, root_ents)
    if vol_secs < 65536 and not fat32:
        struct.pack_into("<H", boot, 19, vol_secs)
    else:
        struct.pack_into("<I", boot, 32, vol_secs)
    boot[21] = 0xF8
    if fat32:
        struct.pack_into("<I", boot, 36, fat_secs)
        struct.pack_into("<I", boot, 44, 2)      # root cluster
    else:
        struct.pack_into("<H", boot, 22, fat_secs)
    boot[510:512] = b"\x55\xAA"
    img[v:v + 512] = boot

    fat_off = v + rsvd * 512
    root_off = fat_off + 2 * fat_secs * 512
    data_off = root_off + root_secs * 512
    fat = {0: 0x0FFFFFF8 if fat32 else 0xFFF8, 1: 0x0FFFFFFF if fat32 else 0xFFFF}
    next_free = [2]
    eoc = 0x0FFFFFFF if fat32 else 0xFFFF

    def alloc(nbytes):
        n = max(1, (nbytes + spc * 512 - 1) // (spc * 512))
        chain = list(range(next_free[0], next_free[0] + n))
        next_free[0] += n
        for a, b in zip(chain, chain[1:]):
            fat[a] = b
        fat[chain[-1]] = eoc
        return chain

    def put(chain, data):
        for k, c in enumerate(chain):
            chunk = data[k * spc * 512:(k + 1) * spc * 512]
            o = data_off + (c - 2) * spc * 512
            img[o:o + len(chunk)] = chunk

    def dirent(name11, attr, clus, size):
        e = bytearray(32)
        e[0:11] = name11
        e[11] = attr
        struct.pack_into("<H", e, 20, clus >> 16)
        struct.pack_into("<H", e, 26, clus & 0xFFFF)
        struct.pack_into("<I", e, 28, size)
        return bytes(e)

    root_chain = alloc(512) if fat32 else None   # FAT32 root is cluster 2

    # CP300 directory: more than one cluster's worth of entries is not needed,
    # but a 1-sector cluster (FAT32) still spans clusters at 17 entries
    dir_entries = []
    for name, data in files.items():
        chain = alloc(len(data))
        put(chain, data)
        dir_entries.append(dirent(short_name(name), 0x20, chain[0], len(data)))
    # a long-name entry and a deleted entry that must be skipped
    lfn = bytearray(32); lfn[0] = 0x41; lfn[11] = 0x0F
    deleted = bytearray(dirent(short_name("OLD.DSK"), 0x20, 0, 0)); deleted[0] = 0xE5
    dir_entries = [bytes(lfn), bytes(deleted)] + dir_entries
    dir_entries = [dirent(b".          ", 0x10, 0, 0)] + dir_entries
    dir_data = b"".join(dir_entries)
    dir_chain = alloc(len(dir_data))
    put(dir_chain, dir_data)

    root = [dirent(b"TESTCARD   ", 0x08, 0, 0),
            dirent(b"CP300      ", 0x10, dir_chain[0], 0)]
    root_data = b"".join(root)
    if fat32:
        put(root_chain, root_data)
    else:
        img[root_off:root_off + len(root_data)] = root_data

    for c, nxt in fat.items():
        for copy in range(2):
            o = fat_off + copy * fat_secs * 512 + c * ent_size
            if fat32:
                struct.pack_into("<I", img, o, nxt)
            else:
                struct.pack_into("<H", img, o, nxt)
    with open(path, "wb") as f:
        f.write(img)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--fat32", action="store_true")
    ap.add_argument("--files")
    ap.add_argument("--clusters", type=int, help="FAT16 cluster count (>= 4085), e.g. 4200 for a 2 MB simulation image")
    ap.add_argument("--spc", type=int, help="sectors per cluster")
    a = ap.parse_args()
    if a.files:
        files = {n: open(os.path.join(a.files, n), "rb").read() for n in sorted(os.listdir(a.files))}
    else:
        files = test_files()
    build(a.out, a.fat32, files, a.clusters, a.spc)


if __name__ == "__main__":
    main()
