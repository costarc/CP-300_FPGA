#!/usr/bin/env python3
"""Test of cp300d against its simulated registers: starts the daemon, then drives it like the web page does.

    python test_cp300d.py            prints PASS or the first failure
"""
import base64
import http.client
import json
import os
import socket
import struct
import subprocess
import sys
import tempfile
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "tools"))
import cp300d          # noqa: E402
import dsk2dmk         # noqa: E402

PORT = 18300


def make_jv1():
    """35 tracks x 10 sectors x 256 bytes: sector bytes are (track*31 + sector*7 + i) & 255."""
    out = bytearray()
    for t in range(35):
        for s in range(10):
            out += bytes((t * 31 + s * 7 + i) & 255 for i in range(256))
    return bytes(out)


class WS:
    def __init__(self, port):
        self.s = socket.create_connection(("127.0.0.1", port), timeout=5)
        key = base64.b64encode(os.urandom(16)).decode()
        self.s.sendall(("GET /ws HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                        "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n" % key).encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            buf += self.s.recv(1)
        assert b" 101 " in buf.split(b"\r\n")[0], buf

    def recv_exact(self, n):
        d = b""
        while len(d) < n:
            c = self.s.recv(n - len(d))
            if not c:
                raise EOFError
            d += c
        return d

    def recv(self):
        h = self.recv_exact(2)
        op, n = h[0] & 15, h[1] & 127
        if n == 126: n = struct.unpack("!H", self.recv_exact(2))[0]
        elif n == 127: n = struct.unpack("!Q", self.recv_exact(8))[0]
        return op, self.recv_exact(n)

    def send_text(self, text):
        data = text.encode()
        mask = os.urandom(4)
        head = bytes([0x81, 0x80 | len(data)]) if len(data) < 126 else bytes([0x81, 0x80 | 126]) + struct.pack("!H", len(data))
        self.s.sendall(head + mask + bytes(b ^ mask[i & 3] for i, b in enumerate(data)))


def req(method, path, body=None):
    c = http.client.HTTPConnection("127.0.0.1", PORT, timeout=10)
    c.request(method, path, body)
    r = c.getresponse()
    return r.status, r.read()


def px(fb, x, y):
    return (fb[(y * 512 + x) // 8] >> (x % 8)) & 1


def main():
    data = tempfile.mkdtemp(prefix="cp300d_")
    p = subprocess.Popen([sys.executable, "-I", os.path.join(HERE, "cp300d.py"), "--sim", "--port", str(PORT),
                          "--host", "127.0.0.1", "--data", data], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        for _ in range(50):
            try:
                st, body = req("GET", "/api/state")
                break
            except OSError:
                time.sleep(0.1)
        else:
            raise SystemExit("FAIL: daemon did not start")
        s = json.loads(body)
        assert s["run"] == 1 and s["roms"]["system"], s
        print("ok   state", s["drives"][0])

        st, body = req("GET", "/")
        assert st == 200 and b"CP-300" in body
        print("ok   page served")

        # disk upload: a JV1 image is converted to DMK
        jv1 = make_jv1()
        expect, _ = dsk2dmk.convert(jv1)
        st, body = req("PUT", "/api/disk/0?name=TEST.DSK", jv1)
        assert st == 200, body
        st, got = req("GET", "/api/disk/0")
        assert st == 200 and got == expect, "downloaded DMK differs (%d vs %d bytes)" % (len(got), len(expect))
        print("ok   disk mount + download (%d bytes DMK)" % len(got))

        # websocket: first message is the state, then a keyframe, then deltas
        ws = WS(PORT)
        op, txt = ws.recv()
        assert op == 1 and json.loads(txt)["drives"][0]["size"] == len(expect)
        fb = None
        deadline = time.time() + 5
        while time.time() < deadline:
            op, m = ws.recv()
            if op == 2 and m[0] == 1:
                kind = m[3]
                d = zlib.decompress(m[4:])
                assert len(d) == 12288
                fb = d if kind == 0 else bytes(a ^ b for a, b in zip(fb, d))
                break
        assert fb is not None and px(fb, 0, 0) == 1 and px(fb, 100, 100) == 0
        print("ok   frame keyframe, border pixel set")

        # press matrix key 'A' (row 0 col 1 = bit 1): the sim draws a block at (1 * 56 + 40, 16)
        ws.send_text(json.dumps({"keys": "%016x" % (1 << 1)}))
        seen_block = clicks = False
        deadline = time.time() + 5
        while time.time() < deadline and not (seen_block and clicks):
            op, m = ws.recv()
            if op != 2:
                continue
            if m[0] == 1:
                kind = m[3]
                d = zlib.decompress(m[4:])
                fb = d if kind == 0 else bytes(a ^ b for a, b in zip(fb, d))
                if px(fb, 100, 20):
                    seen_block = True
            elif m[0] == 2:
                clicks = clicks or (len(m) - 1) // 6 >= 2
        assert seen_block, "key block not drawn"
        assert clicks, "no audio events"
        print("ok   key press changes the picture, audio events arrive")

        # XOR frames come with consecutive seq; after {"keyframe":1} the next frame is a whole one
        last = None
        for _ in range(3):
            while True:
                op, m = ws.recv()
                if op == 2 and m[0] == 1:
                    break
            seq = m[1] | m[2] << 8
            assert m[3] == 1 and (last is None or seq == (last + 1) & 0xFFFF), (m[3], seq, last)
            last = seq
        ws.send_text(json.dumps({"keyframe": 1}))
        kinds = []
        deadline = time.time() + 5
        while time.time() < deadline and 0 not in kinds:
            op, m = ws.recv()
            if op == 2 and m[0] == 1:
                kinds.append(m[3])
                if m[3] == 0:
                    fb = zlib.decompress(m[4:])
        assert 0 in kinds and len(kinds) <= 3, kinds
        assert px(fb, 0, 0) == 1
        print("ok   consecutive seq, key frame on request")

        # the probe leaves the machine as it was: keys put back, CTRL not written
        ws.send_text(json.dumps({"keys": "%016x" % (1 << 5)}))
        time.sleep(0.2)
        st, body = req("POST", "/api/ctrl", json.dumps({"turbo": 1}).encode())
        before = json.loads(body)
        st, body = req("GET", "/api/debug")
        dbg = json.loads(body)
        assert st == 200 and dbg["irq"] is False and dbg["frames_per_second"] > 30, dbg
        assert dbg["keys_lo_readback"] == "0xa5a55a5a" and dbg["block_write_readback"] == ["0x11223344", "0x55667788"], dbg
        assert int(dbg["ctrl"], 16) == 5, dbg                     # run + turbo
        st, body = req("GET", "/api/state")
        assert json.loads(body)["turbo"] == before["turbo"] == 1
        st, body = req("GET", "/api/debug")
        assert int(json.loads(body)["ctrl"], 16) == 5
        print("ok   /api/debug: readback tests, CTRL untouched")

        ws.send_text(json.dumps({"keys": "%016x" % 0}))
        st, body = req("PUT", "/api/rom/system", b"short")
        assert st == 400
        st, body = req("POST", "/api/ctrl", json.dumps({"turbo": 1}).encode())
        assert json.loads(body)["turbo"] == 1
        print("ok   ROM size check, ctrl")
    finally:
        p.terminate()
        try:
            p.wait(5)
        except subprocess.TimeoutExpired:
            p.kill()
    # the service() path against the simulated IO controller request is covered here directly
    regs = cp300d.SimRegs()
    dev = cp300d.Cp300(regs, tempfile.mkdtemp(prefix="cp300d_"))
    dev.sysrom, dev.chargen = bytes(16384), bytes(2048)
    dev.mount(0, make_jv1(), "T.DSK")
    dev.start()
    assert regs.req is not None, "sim did not issue the boot request"
    assert dev.service()
    first = bytes(regs.trk[:8])
    dmk = dev.disks[0]
    assert first == bytes(dmk[0:8]) and regs.req is None, (first, bytes(dmk[:8]))
    print("ok   IO controller request served from the DMK")
    # write request
    regs.req = (0, 1024, 512, 0, 1)
    regs.trk[0:512] = bytes(range(256)) * 2
    assert dev.service()
    assert bytes(dev.disks[0][1024:1024 + 512]) == bytes(range(256)) * 2 and dev.dirty[0]
    print("ok   write request stored in the DMK")
    # the probe puts the keys back
    dev.set_keys(0x0000002000000040)
    dev.debug()
    assert regs.keys == 0x0000002000000040, hex(regs.keys)
    print("ok   /api/debug restores the keys")
    # FreeHD hard disk: an HDV image in slot 6 (hard disk 0), served and written like a floppy image
    hdv = bytearray(256 + 64 * 256)
    hdv[0:3] = b"\x56\xcb\x10"
    hdv[28], hdv[29] = 1, 64
    for i in range(64 * 256):
        hdv[256 + i] = (i * 3) & 255
    try:
        dev.mount_hd(0, b"\x00" * 600, "BAD.HDV")
        raise AssertionError("a file without the HDV header was accepted")
    except ValueError:
        pass
    info = dev.mount_hd(0, hdv, "T.HDV")
    assert info == {"cylinders": 1, "sectors_per_cylinder": 64}
    assert regs.slots[6] == len(hdv) and regs.present & (1 << 6)
    regs.req = (6, 512, 512, 0, 0)
    assert dev.service()
    assert bytes(regs.trk[:512]) == bytes(hdv[512:1024]), "HDV read request"
    regs.req = (6, 1024, 512, 0, 1)
    regs.trk[0:512] = bytes(range(256)) * 2
    assert dev.service()
    assert bytes(dev.disks[6][1024:1536]) == bytes(range(256)) * 2 and dev.dirty[6]
    dev.save_dirty()
    assert dev.state()["hd"][0]["size"] == len(hdv)
    dev.eject(6)
    assert regs.slots[6] == 0 and not regs.present & (1 << 6)
    print("ok   FreeHD image mounted, read, written, ejected")
    print("PASS")


if __name__ == "__main__":
    main()
