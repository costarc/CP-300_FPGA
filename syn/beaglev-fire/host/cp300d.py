#!/usr/bin/env python3
"""cp300d: the Linux side of the CP-300 on the BeagleV-Fire.

    python3 cp300d.py --uio /dev/uio0                  real board (the FIC window of the gateware)
    python3 cp300d.py --mem 0x60000000                 real board through /dev/mem
    python3 cp300d.py --sim                            no hardware: a simulated register file, for the web page

Serves the web page (web/), a WebSocket with the picture, the keys and the audio, and a few HTTP calls to
mount disks and load the ROMs. Standard library only (Debian's python3 is enough).

    GET  /                       the page
    GET  /ws                     WebSocket: server -> browser  0x01 frame, 0x02 audio, text = JSON state
                                              browser -> server  text JSON {"keys":"<16 hex digits>"} or {"ctrl":{...}}
    GET  /api/state              JSON state
    PUT  /api/disk/<0-3>?name=X  body = disk image (DMK, JV1, JV3 or HFE: converted to DMK); mounts it
    GET  /api/disk/<0-3>         download the (possibly modified) DMK
    DELETE /api/disk/<0-3>       eject
    PUT  /api/rom/system         body = 16384 bytes;   PUT /api/rom/chargen   body = 2048 bytes
    POST /api/ctrl               JSON {"run":1,"reset":1,"turbo":0,"wp":0}

The register map is in rtl/bvf_regs.v.
"""
import argparse
import asyncio
import base64
import hashlib
import json
import mmap
import os
import struct
import sys
import time
import zlib
from urllib.parse import urlparse, parse_qs

HERE = os.path.dirname(os.path.abspath(__file__))
for p in (os.path.join(HERE, "..", "..", "..", "tools"), HERE):
    if os.path.exists(os.path.join(p, "dsk2dmk.py")):
        sys.path.insert(0, p)
try:
    import dsk2dmk
except ImportError:
    dsk2dmk = None

# register offsets (rtl/bvf_regs.v)
R_ID, R_CTRL, R_STATUS, R_KEYS_LO, R_KEYS_HI, R_FRAME, R_AUDIO, R_AUDIO_HEAD, R_DEBUG = 0x00, 0x04, 0x08, 0x0C, 0x10, 0x14, 0x18, 0x1C, 0x20
R_REQ_SLOT, R_REQ_OFFSET, R_REQ_LEN, R_REQ_BOFF, R_DONE = 0x40, 0x44, 0x48, 0x4C, 0x50
R_SIZE, R_PRESENT, R_CHG_SET, R_SCAN_VALID = 0x60, 0x70, 0x74, 0x78
W_ROM, W_TRK, W_FRAME = 0x10000, 0x20000, 0x30000
ID_VALUE = 0x43503001

ST_HOLD, ST_SCAN, ST_PENDING, ST_REQ_WR, ST_REQ_ERR, ST_AUD_LOST, ST_LATEST = 1, 2, 4, 8, 16, 32, 64
FRAME_WORDS = 3072          # 512 x 192 / 32
FRAME_BYTES = FRAME_WORDS * 4
SYS_ROM, CHARGEN = 16384, 2048


# ---------------------------------------------------------------- register access
class MemRegs:
    """The FIC window of the gateware, through /dev/uioN or /dev/mem."""
    def __init__(self, path, base=0, size=0x100000):
        self.fd = os.open(path, os.O_RDWR | os.O_SYNC)
        self.mm = mmap.mmap(self.fd, size, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=base)

    def read32(self, off):
        return struct.unpack_from("<I", self.mm, off)[0]

    def write32(self, off, val):
        struct.pack_into("<I", self.mm, off, val & 0xFFFFFFFF)

    def read_block(self, off, n):
        out = bytearray(n)
        for i in range(0, n, 4):                      # 32 bit accesses only: the bus is a 32 bit AXI4-Lite
            struct.pack_into("<I", out, i, self.read32(off + i))
        return bytes(out)

    def write_block(self, off, data):
        for i in range(0, len(data), 4):
            self.write32(off + i, struct.unpack_from("<I", data, i)[0])


class SimRegs:
    """A register file that behaves like the gateware as far as the daemon can tell: for the web page and
    for testing the daemon without a board. The picture shows a grid of the keys pressed."""
    def __init__(self):
        self.t0 = time.monotonic()
        self.ctrl = 0
        self.keys = 0
        self.slots = [0] * 4
        self.present = 0
        self.scan = 0
        self.trk = bytearray(16384)
        self.rom = bytearray(SYS_ROM + CHARGEN)
        self.req = None                     # (slot, offset, len, boff, write)
        self.req_done = 0
        self.audio = []
        self.cnt_audio_keys = 0
        self.log = []

    def _frame_no(self):
        return int((time.monotonic() - self.t0) * 60) & 0xFFFF

    def _picture(self):
        n = self._frame_no()
        px = bytearray(FRAME_BYTES)
        def setpx(x, y):
            px[(y * 512 + x) // 8] |= 1 << (x % 8)
        for x in range(512):
            setpx(x, 0); setpx(x, 191)
        for y in range(192):
            setpx(0, y); setpx(511, y)
        for k in range(64):
            if (self.keys >> k) & 1:
                cx, cy = (k % 8) * 56 + 40, (k // 8) * 20 + 16
                for y in range(cy, cy + 14):
                    for x in range(cx, cx + 48):
                        setpx(x, y)
        x = n % 500 + 6
        for y in range(180, 186):
            setpx(x, y)
        return bytes(px)

    def read32(self, off):
        if off == R_ID: return ID_VALUE
        if off == R_CTRL: return self.ctrl
        if off == R_STATUS:
            return (ST_SCAN if self.scan else 0) | (ST_PENDING if self.req else 0) | (ST_REQ_WR if self.req and self.req[4] else 0) | ST_LATEST
        if off == R_KEYS_LO: return self.keys & 0xFFFFFFFF
        if off == R_KEYS_HI: return self.keys >> 32
        if off == R_FRAME: return self._frame_no()
        if off == R_AUDIO: return len(self.audio)
        if off == R_AUDIO_HEAD: return self.audio[0] if self.audio else 0
        if off == R_DEBUG: return 0xA6
        if self.req and off in (R_REQ_SLOT, R_REQ_OFFSET, R_REQ_LEN, R_REQ_BOFF):
            return self.req[(R_REQ_SLOT, R_REQ_OFFSET, R_REQ_LEN, R_REQ_BOFF).index(off)]
        return 0

    def write32(self, off, val):
        if off == R_CTRL:
            if (val & 1) and not (self.ctrl & 1) and (self.present & 1):
                self.req = (0, 0, 1024, 0, 0)            # as the IO controller does when it mounts drive 0
            self.ctrl = val & ~2
        elif off == R_KEYS_LO:
            self._key_edge(val)
        elif off == R_KEYS_HI:
            self.keys = (self.keys & 0xFFFFFFFF) | (val << 32)
        elif off == R_AUDIO_HEAD and self.audio:
            self.audio.pop(0)
        elif off == R_DONE:
            self.log.append(("done", val, bytes(self.trk[:8]) if self.req and not self.req[4] else b""))
            self.req = None
        elif R_SIZE <= off < R_SIZE + 16:
            self.slots[(off - R_SIZE) // 4] = val
        elif off == R_PRESENT:
            self.present = val
        elif off == R_SCAN_VALID:
            self.scan = val & 1
        elif W_ROM <= off < W_ROM + 0x10000:
            pass
        elif W_TRK <= off < W_TRK + 16384:
            struct.pack_into("<I", self.trk, off - W_TRK, val)

    def _key_edge(self, lo):
        if lo & ~(self.keys & 0xFFFFFFFF):               # a key went down: click
            t = int((time.monotonic() - self.t0) * 1e6) & 0x7FFFFF
            self.audio += [(0x11 << 23) | t, (0x10 << 23) | ((t + 800) & 0x7FFFFF)]
        self.keys = (self.keys & ~0xFFFFFFFF) | lo

    def read_block(self, off, n):
        if off == W_FRAME:
            return self._picture()[:n]
        if W_TRK <= off < W_TRK + 16384:
            return bytes(self.trk[off - W_TRK:off - W_TRK + n])
        return b"\0" * n

    def write_block(self, off, data):
        if W_TRK <= off < W_TRK + 16384:
            self.trk[off - W_TRK:off - W_TRK + len(data)] = data
        elif W_ROM <= off < W_ROM + 0x10000:
            self.rom[off - W_ROM:off - W_ROM + len(data)] = data


# ---------------------------------------------------------------- the device
class Cp300:
    def __init__(self, regs, datadir):
        self.r = regs
        self.datadir = datadir
        os.makedirs(datadir, exist_ok=True)
        self.disks = [None] * 4                       # bytearray of a DMK
        self.names = [""] * 4
        self.dirty = [False] * 4
        self.sysrom = None
        self.chargen = None
        self.ctrl = {"run": 0, "turbo": 0, "wp": 0}
        self.last_frame = -1
        self.frame_seq = 0
        self.stats = {"requests": 0, "errors": 0, "frames": 0, "dropped": 0}
        if self.r.read32(R_ID) != ID_VALUE:
            raise SystemExit("register window does not answer with the CP-300 ID (0x%08X)" % ID_VALUE)
        self._load_saved()

    # -- saved state
    def _path(self, name):
        return os.path.join(self.datadir, name)

    def _load_saved(self):
        for n, key in ((0, "system.rom"), (1, "chargen.rom")):
            p = self._path(key)
            if os.path.exists(p):
                data = open(p, "rb").read()
                if n == 0 and len(data) == SYS_ROM: self.sysrom = data
                if n == 1 and len(data) == CHARGEN: self.chargen = data
        meta = {}
        if os.path.exists(self._path("drives.json")):
            meta = json.load(open(self._path("drives.json")))
        for n in range(4):
            p = self._path("drive%d.dmk" % n)
            if os.path.exists(p):
                self.disks[n] = bytearray(open(p, "rb").read())
                self.names[n] = meta.get(str(n), "drive%d.dmk" % n)

    def _save_meta(self):
        json.dump({str(n): self.names[n] for n in range(4)}, open(self._path("drives.json"), "w"))

    def save_dirty(self):
        for n in range(4):
            if self.dirty[n] and self.disks[n] is not None:
                open(self._path("drive%d.dmk" % n), "wb").write(self.disks[n])
                self.dirty[n] = False

    # -- ROMs and start
    def roms_ready(self):
        return self.sysrom is not None and self.chargen is not None

    def load_roms(self):
        # four bytes make a word, first byte in bits 31:24 (rtl/ht1080z): big endian words
        for base, data in ((0, self.sysrom), (0x4000, self.chargen)):
            words = struct.unpack(">%dI" % (len(data) // 4), data)
            for i, w in enumerate(words):
                self.r.write32(W_ROM + base + 4 * i, w)

    def publish_slots(self):
        mask = 0
        for n in range(4):
            size = len(self.disks[n]) if self.disks[n] is not None else 0
            self.r.write32(R_SIZE + 4 * n, size)
            if size:
                mask |= 1 << n
        self.r.write32(R_PRESENT, mask)
        self.r.write32(R_SCAN_VALID, 1)

    def apply_ctrl(self, reset=False):
        v = (1 if self.ctrl["run"] else 0) | (2 if reset else 0) | (4 if self.ctrl["turbo"] else 0) | (8 if self.ctrl["wp"] else 0)
        self.r.write32(R_CTRL, v)

    def start(self):
        """Hold the core, load the ROMs and the slot table, then release it."""
        self.r.write32(R_CTRL, 0)
        self.r.write32(R_SCAN_VALID, 0)
        if not self.roms_ready():
            return False
        self.load_roms()
        self.publish_slots()
        self.ctrl["run"] = 1
        self.apply_ctrl()
        return True

    # -- disks
    def mount(self, n, blob, name):
        if dsk2dmk is None:
            raise ValueError("dsk2dmk.py not found next to the daemon: only DMK images can be mounted")
        dmk, info = dsk2dmk.convert(bytes(blob))
        self.disks[n] = bytearray(dmk)
        self.names[n] = name
        self.dirty[n] = True
        self.save_dirty()
        self._save_meta()
        self.r.write32(R_SIZE + 4 * n, len(dmk))
        mask = sum(1 << i for i in range(4) if self.disks[i] is not None)
        self.r.write32(R_PRESENT, mask)
        self.r.write32(R_CHG_SET, 1 << n)
        return info

    def eject(self, n):
        self.disks[n] = None
        self.names[n] = ""
        p = self._path("drive%d.dmk" % n)
        if os.path.exists(p):
            os.remove(p)
        self._save_meta()
        self.r.write32(R_SIZE + 4 * n, 0)
        mask = sum(1 << i for i in range(4) if self.disks[i] is not None)
        self.r.write32(R_PRESENT, mask)
        self.r.write32(R_CHG_SET, 1 << n)

    def service(self):
        """Answer a request of the IO controller (a piece of a DMK image, up to a whole track)."""
        st = self.r.read32(R_STATUS)
        if not st & ST_PENDING:
            return False
        slot = self.r.read32(R_REQ_SLOT) & 3
        off = self.r.read32(R_REQ_OFFSET)
        ln = self.r.read32(R_REQ_LEN)
        boff = self.r.read32(R_REQ_BOFF)
        wr = bool(st & ST_REQ_WR)
        d = self.disks[slot]
        err = 0
        if d is None or ln > 16384 or boff + ln > 16384:
            err = 1
        elif wr:
            data = self.r.read_block(W_TRK + boff, (ln + 3) & ~3)[:ln]
            n = max(0, min(ln, len(d) - off))
            if n > 0 and d[off:off + n] != data[:n]:
                d[off:off + n] = data[:n]
                self.dirty[slot] = True
        else:
            data = bytes(d[off:off + ln]).ljust(ln, b"\0")
            self.r.write_block(W_TRK + boff, data + b"\0" * (-ln % 4))
        self.r.write32(R_DONE, err)
        self.stats["requests"] += 1
        self.stats["errors"] += err
        return True

    # -- picture, keys, audio
    def new_frame(self):
        """The newest complete frame as 12288 bytes (pixel x = bit x%8 of byte x/8), or None if unchanged."""
        for _ in range(3):
            f0 = self.r.read32(R_FRAME)
            cnt, buf = f0 & 0xFFFF, (f0 >> 16) & 1
            if cnt == self.last_frame:
                return None
            data = self.r.read_block(W_FRAME + buf * 0x4000, FRAME_BYTES)
            f1 = self.r.read32(R_FRAME)
            if ((f1 & 0xFFFF) - cnt) & 0xFFFF < 2:           # the writer did not reach this buffer meanwhile
                self.last_frame = cnt
                self.frame_seq = (self.frame_seq + 1) & 0xFFFF
                self.stats["frames"] += 1
                return data
            self.stats["dropped"] += 1
        return None

    def set_keys(self, keys):
        self.r.write32(R_KEYS_LO, keys & 0xFFFFFFFF)
        self.r.write32(R_KEYS_HI, keys >> 32)

    def audio_events(self):
        n = self.r.read32(R_AUDIO)
        out = []
        for _ in range(min(n, 128)):
            w = self.r.read32(R_AUDIO_HEAD)
            out.append((w & 0x7FFFFF, w >> 23))
            self.r.write32(R_AUDIO_HEAD, 0)
        return out

    def state(self):
        return {"run": self.ctrl["run"], "turbo": self.ctrl["turbo"], "wp": self.ctrl["wp"],
                "roms": {"system": self.sysrom is not None, "chargen": self.chargen is not None},
                "drives": [{"name": self.names[n], "size": len(self.disks[n]) if self.disks[n] is not None else 0}
                           for n in range(4)],
                "stats": self.stats}


# ---------------------------------------------------------------- HTTP + WebSocket (RFC 6455, enough for one page)
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
TYPES = {".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".png": "image/png", ".svg": "image/svg+xml"}


def ws_frame(opcode, payload):
    n = len(payload)
    if n < 126: head = struct.pack("!BB", 0x80 | opcode, n)
    elif n < 65536: head = struct.pack("!BBH", 0x80 | opcode, 126, n)
    else: head = struct.pack("!BBQ", 0x80 | opcode, 127, n)
    return head + payload


async def ws_read(reader):
    h = await reader.readexactly(2)
    op, n = h[0] & 0x0F, h[1] & 0x7F
    if n == 126: n = struct.unpack("!H", await reader.readexactly(2))[0]
    elif n == 127: n = struct.unpack("!Q", await reader.readexactly(8))[0]
    mask = await reader.readexactly(4) if h[1] & 0x80 else None
    data = await reader.readexactly(n)
    if mask:
        data = bytes(b ^ mask[i & 3] for i, b in enumerate(data))
    return op, data


class Server:
    def __init__(self, dev, webdir):
        self.dev = dev
        self.webdir = webdir
        self.clients = set()
        self.keys = 0

    async def handle(self, reader, writer):
        try:
            line = await reader.readline()
            if not line:
                return
            method, target, _ = line.decode("latin1").split(" ", 2)
            headers = {}
            while True:
                h = (await reader.readline()).decode("latin1").strip()
                if not h:
                    break
                k, v = h.split(":", 1)
                headers[k.strip().lower()] = v.strip()
            body = b""
            if "content-length" in headers:
                n = int(headers["content-length"])
                if n > 4 * 1024 * 1024:
                    return await self.reply(writer, 413, b"too big")
                body = await reader.readexactly(n)
            url = urlparse(target)
            if url.path == "/ws" and headers.get("upgrade", "").lower() == "websocket":
                return await self.websocket(reader, writer, headers)
            if url.path.startswith("/api/"):
                return await self.api(writer, method, url, body)
            if method != "GET":
                return await self.reply(writer, 405, b"method not allowed")
            return await self.static(writer, url.path)
        except (asyncio.IncompleteReadError, ConnectionError):
            pass
        finally:
            try:
                writer.close()
            except Exception:
                pass

    async def reply(self, writer, code, body, ctype="text/plain", extra=""):
        reason = {200: "OK", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed", 413: "Too Large", 500: "Error"}.get(code, "OK")
        writer.write(("HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\n%sConnection: close\r\n\r\n"
                      % (code, reason, ctype, len(body), extra)).encode() + body)
        await writer.drain()

    async def static(self, writer, path):
        if path == "/":
            path = "/index.html"
        full = os.path.normpath(os.path.join(self.webdir, path.lstrip("/")))
        if not full.startswith(os.path.normpath(self.webdir)) or not os.path.isfile(full):
            return await self.reply(writer, 404, b"not found")
        await self.reply(writer, 200, open(full, "rb").read(), TYPES.get(os.path.splitext(full)[1], "application/octet-stream"))

    async def api(self, writer, method, url, body):
        parts = url.path.strip("/").split("/")[1:]
        q = parse_qs(url.query)
        dev = self.dev
        try:
            if parts == ["state"]:
                return await self.json(writer, dev.state())
            if parts[0] == "disk" and len(parts) == 2 and parts[1] in "0123":
                n = int(parts[1])
                if method == "PUT":
                    info = dev.mount(n, body, q.get("name", ["disk%d.dsk" % n])[0])
                    await self.push_state()
                    return await self.json(writer, {"ok": True, "info": info})
                if method == "DELETE":
                    dev.eject(n)
                    await self.push_state()
                    return await self.json(writer, {"ok": True})
                if method == "GET" and dev.disks[n] is not None:
                    dev.save_dirty()
                    return await self.reply(writer, 200, bytes(dev.disks[n]), "application/octet-stream",
                                            'Content-Disposition: attachment; filename="%s"\r\n' % (os.path.splitext(dev.names[n])[0] or "disk") + ".dmk")
            if parts[0] == "rom" and len(parts) == 2 and method == "PUT":
                want = {"system": SYS_ROM, "chargen": CHARGEN}.get(parts[1])
                if want is None or len(body) != want:
                    return await self.json(writer, {"ok": False, "error": "%s ROM must be %s bytes" % (parts[1], want)}, 400)
                setattr(dev, "sysrom" if parts[1] == "system" else "chargen", body)
                open(dev._path("system.rom" if parts[1] == "system" else "chargen.rom"), "wb").write(body)
                if dev.roms_ready():
                    dev.start()
                await self.push_state()
                return await self.json(writer, {"ok": True})
            if parts == ["ctrl"] and method == "POST":
                self.ctrl(json.loads(body or b"{}"))
                await self.push_state()
                return await self.json(writer, dev.state())
        except (ValueError, SystemExit) as e:
            return await self.json(writer, {"ok": False, "error": str(e)}, 400)
        return await self.reply(writer, 404, b"no such call")

    async def json(self, writer, obj, code=200):
        await self.reply(writer, code, json.dumps(obj).encode(), "application/json")

    def ctrl(self, c):
        d = self.dev
        for k in ("run", "turbo", "wp"):
            if k in c:
                d.ctrl[k] = 1 if c[k] else 0
        if c.get("run") and not d.roms_ready():
            d.ctrl["run"] = 0
        if "run" in c and d.ctrl["run"] and not (d.r.read32(R_CTRL) & 1):
            d.start()
        else:
            d.apply_ctrl(reset=bool(c.get("reset")))

    async def push_state(self):
        msg = ws_frame(1, json.dumps(self.dev.state()).encode())
        for c in list(self.clients):
            c.w.write(msg)

    async def websocket(self, reader, writer, headers):
        acc = base64.b64encode(hashlib.sha1((headers["sec-websocket-key"] + WS_GUID).encode()).digest()).decode()
        writer.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n" % acc).encode())
        me = _Client(writer)
        self.clients.add(me)
        writer.write(ws_frame(1, json.dumps(self.dev.state()).encode()))
        await writer.drain()
        try:
            while True:
                op, data = await ws_read(reader)
                if op == 8:
                    break
                if op == 9:
                    writer.write(ws_frame(10, data))
                elif op == 1:
                    msg = json.loads(data)
                    if "keys" in msg:
                        self.keys = int(msg["keys"], 16) & ((1 << 64) - 1)
                        self.dev.set_keys(self.keys)
                    if "ctrl" in msg:
                        self.ctrl(msg["ctrl"])
                        await self.push_state()
        except (asyncio.IncompleteReadError, ConnectionError, ValueError):
            pass
        finally:
            self.clients.discard(me)
            if not self.clients:
                self.dev.set_keys(0)

    async def pump(self):
        """The hardware loop: disk requests first (they are time critical), then picture and audio."""
        dev = self.dev
        last_save = time.monotonic()
        while True:
            busy = False
            while dev.service():
                busy = True
            frame = dev.new_frame()
            if frame is not None and self.clients:
                for c in list(self.clients):
                    if c.prev is None:
                        pl, kind = frame, 0
                    else:
                        pl, kind = bytes(a ^ b for a, b in zip(frame, c.prev)), 1
                    c.prev = frame
                    c.w.write(ws_frame(2, b"\x01" + struct.pack("<HB", dev.frame_seq, kind) + zlib.compress(pl, 1)))
            ev = dev.audio_events()
            if ev and self.clients:
                msg = ws_frame(2, b"\x02" + b"".join(struct.pack("<IH", t, lv) for t, lv in ev))
                for c in list(self.clients):
                    c.w.write(msg)
            if time.monotonic() - last_save > 2:
                dev.save_dirty()
                last_save = time.monotonic()
            await asyncio.sleep(0.0005 if busy else 0.004)


class _Client:
    def __init__(self, w):
        self.w = w
        self.prev = None


async def main_async(args):
    if args.sim:
        regs = SimRegs()
    elif args.uio:
        regs = MemRegs(args.uio)
    else:
        regs = MemRegs("/dev/mem", int(args.mem, 0))
    dev = Cp300(regs, args.data)
    if args.sim and not dev.roms_ready():
        dev.sysrom, dev.chargen = bytes(SYS_ROM), bytes(CHARGEN)
    if dev.roms_ready():
        dev.start()
    srv = Server(dev, args.web)
    server = await asyncio.start_server(srv.handle, args.host, args.port)
    print("cp300d: http://%s:%d/  (%s)" % (args.host, args.port, "simulated registers" if args.sim else "hardware"), flush=True)
    asyncio.get_event_loop().create_task(srv.pump())
    async with server:
        await server.serve_forever()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--uio", help="UIO device of the gateware, e.g. /dev/uio0")
    g.add_argument("--mem", help="physical base address of the FIC window (through /dev/mem)")
    g.add_argument("--sim", action="store_true", help="simulated registers, no hardware")
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=8300)
    ap.add_argument("--data", default=os.path.join(HERE, "data"), help="where ROMs and disk images are kept")
    ap.add_argument("--web", default=os.path.join(HERE, "web"))
    args = ap.parse_args()
    try:
        asyncio.run(main_async(args))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
