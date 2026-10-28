# Putting a Retro Computer in a Browser: an FPGA, a RISC-V Linux Core and a Web Page

**A technical paper on the CP-300 core for the BeagleV-Fire, and on the pattern behind it: a memory-mapped FPGA block, a small
host daemon, and a web page as the whole user interface.**

Part of the [CP-300 FPGA](../README.md) project. Port README: [`syn/beaglev-fire`](../syn/beaglev-fire/README.md). Status of the work
described here: runs on the author's board, package 0.2.0, see [section 12](#12-what-is-verified-and-what-is-not).

**Detailed build steps** (framework and HSS commits, MSS generation, the cape, the two framework edits, the Libero run, the
overlay identity and the package) are in the repository, in
[`syn/beaglev-fire/BUILDING.md`](../syn/beaglev-fire/BUILDING.md); this paper explains the design and only summarises the
build ([section 9.2](#92-building-the-gateware)).

---

## Abstract

The BeagleV-Fire is a Linux board built around a Microchip PolarFire SoC: four 64-bit RISC-V application cores and about 23K logic
elements of FPGA fabric on one chip. It has no video connector for the fabric, no keyboard port, no audio output and no storage
the fabric can reach. We ran a complete 1980s computer (the Prológica CP-300, a Brazilian TRS-80 Model III compatible) in that
fabric anyway. The machine runs unmodified in the FPGA; everything a user touches (screen, keyboard, speaker, floppy drives) is
provided by **a web page**, served by a small Python daemon on the board's Linux, which talks to the fabric through **one 1 MB
memory-mapped register window**.

This paper documents the design and, above all, *why* each decision went the way it did. The retro computer is the example, not the
subject. The subject is the interface problem that appears in any project that puts a hardware block next to a general-purpose
CPU: how to move **a video stream, an event stream, bulk storage and control state** across a processor/fabric boundary
reliably, cheaply, and in a way a non-specialist can use from a browser. We describe the interface contract, the clock-domain
crossing, the frame capture, the request/response mailbox that lets the host act as the machine's disk, the audio transport, the
daemon, the web protocol and the packaging, and we list the mistakes that cost the most time. A short checklist for reuse closes
the paper.

---

## Contents

1. [The problem and the constraints](#1-the-problem-and-the-constraints)
2. [Architecture overview](#2-architecture-overview)
3. [Key decisions and the reasons](#3-key-decisions-and-the-reasons)
4. [The platform: what the BeagleV-Fire gives you](#4-the-platform-what-the-beaglev-fire-gives-you)
5. [The FPGA/CPU interface](#5-the-fpgacpu-interface)
6. [The gateware](#6-the-gateware)
7. [The host side: the Linux daemon](#7-the-host-side-the-linux-daemon)
8. [The web protocol and the page](#8-the-web-protocol-and-the-page)
9. [Delivery: device tree, build, package, installer](#9-delivery-device-tree-build-package-installer)
10. [Performance and resources](#10-performance-and-resources)
11. [Lessons learned](#11-lessons-learned)
12. [What is verified and what is not](#12-what-is-verified-and-what-is-not)
13. [A checklist for other projects](#13-a-checklist-for-other-projects)
14. [Reference: register map and message formats](#14-reference-register-map-and-message-formats)

---

## 1. The problem and the constraints

### 1.1 The machine

The CP-300 is a Z80 computer with a 512 × 192 monochrome text/graphics display, a keyboard matrix of 64 positions, a one-bit
speaker and a WD1793 floppy controller. The FPGA design ([the core](../README.md), derived from the open HT1080Z core, with the T80
Z80 and a WD1793 replica) already existed for other boards. That core wants: a 42 MHz clock, a place to load two ROM images, a
keyboard matrix input, a pixel stream out, a one-bit-ish audio out, and, for the disks, someone to answer "give me sector *s* of
track *t* of drive *d*".

### 1.2 The board

| Wanted by the core | Provided by the BeagleV-Fire |
|---|---|
| A display | Nothing. No video connector wired to the fabric. |
| A keyboard | Nothing wired to the fabric. USB belongs to Linux. |
| A speaker | Nothing wired to the fabric. |
| Floppy drives / SD card | Nothing the fabric can reach. Storage belongs to Linux. |
| A clock | 50 MHz fabric clock on the bus (PCLK), PLLs available. |
| A way to talk to software | The **fabric interconnect (FIC)**: memory-mapped windows in the RISC-V address map, and interrupt lines. |

So the only thing the board offers is the *processor/fabric boundary itself*. Everything else has to be built on top of it. That
observation is the whole design: **if Linux can see the fabric as memory, Linux can be the monitor, the keyboard, the speaker and
the disk drive** and a web server is already running on it.

### 1.3 Requirements we set ourselves

1. The CP-300 core must not be rewritten. It is shared with four other ports; the BeagleV-Fire adaptation must be a *wrapper*.
2. Zero special software on the user's computer. A browser is the only client.
3. A user must be able to install it without a toolchain: a package with an installer.
4. It has to coexist with the board's stock software (its web server, Cockpit) and with other gateware designs.
5. Correctness before speed: 60 Hz video would be nice, a corrupted disk is not acceptable.

---

## 2. Architecture overview

```
 Browser                                    BeagleV-Fire (PolarFire SoC MPFS025T)
 ┌──────────────────────────┐   HTTP/WS     ┌──────────────────────────────┐   ┌────────────────────────────────────────┐
 │ canvas 512x192 (4:3)     │◄─────────────►│ nginx :80  /cp300/ ──proxy──►│   │ FPGA fabric                            │
 │ keyboard → matrix bits   │               │ cp300d.py :8300 (Python)     │   │                                        │
 │ WebAudio (edge events)   │               │   asyncio HTTP + WebSocket   │   │ APB3 slave (PCLK 50 MHz)               │
 │ drag & drop disk images  │               │   regs32.so (lw/sw access)   │   │   └─ toggle handshake CDC ─┐           │
 └──────────────────────────┘               │          │ mmap              │   │ 42 MHz core domain  ◄──────┘           │
                                            │   /dev/uio0 (generic-uio)    │   │   bvf_regs  ─ keys, run/reset, ROM load│
                                            │          │                   │   │   bvf_fb    ─ frame capture, 2 buffers │
                                            │  FIC window 0x41000000 (1 MB)│◄─►│   bvf_dataslot ─ disk mailbox + 16K RAM│
                                            │  + 1 interrupt line          │   │   bvf_audio ─ timestamped edge FIFO    │
                                            └──────────────────────────────┘   │   CP-300 core: Z80, video, WD1793,     │
                                                                               │   helper Z80 (IO controller + firmware)│
                                                                               └────────────────────────────────────────┘
```

Four independent *flows* cross the boundary, and each got the mechanism that suits its nature:

| Flow | Direction | Nature | Mechanism |
|---|---|---|---|
| Control (run, reset, turbo, write-protect) | host → fabric | rare, state | registers |
| Keyboard | host → fabric | level state, 64 bits | two registers, written whole |
| ROM load | host → fabric | one-shot bulk write | write-only window, word-addressed |
| **Screen** | fabric → host | continuous stream, 12 KB × 60/s | double-buffered frame RAM, polled, read in bulk |
| **Audio** | fabric → host | sparse, *timing-critical* events | timestamped FIFO, popped |
| **Disk** | fabric → host → fabric | request/response, *the fabric is the client* | mailbox + shared track RAM + completion handshake |

The rest of the paper is, in effect, a justification of that table.

---

## 3. Key decisions and the reasons

Each entry: what we chose, what we rejected, why.

### D1. Wrap the core; do not modify it

The CP-300 core, its helper Z80 ("IO controller") and the firmware that serves disk images are those of the Analogue Pocket port,
unchanged. The BeagleV-Fire adds only `rtl/` glue (about 800 lines of Verilog in total, including the AXI4-Lite variant). **Reason:** the same IO-controller
firmware that asks the Pocket's framework for "a piece of a file" can ask a Linux daemon for the same thing, if the glue presents
the same interface. This turned the hardest part (a floppy controller fed from files) from new work into an *adapter* (`bvf_dataslot`).
**Cost:** no BeagleV-specific optimisation inside the core (e.g. the 64 KB RAM is the full size although 48 KB suffice).

### D2. The browser is the whole front end

**Rejected:** a bare-metal framebuffer driver on the RISC-V cores (no connector to drive); a local Qt/SDL application (needs a
display on the board, which most users do not have attached); a VNC wrapper (a second protocol stack, poor audio).
**Chosen:** a web page. **Reason:** the board already runs a web server and is reached over a network; browsers give a canvas,
keyboard events, WebAudio, file drag-and-drop and a 4:3 layout engine for free, on any client OS, including a phone with an
on-screen keyboard.

### D3. One memory-mapped window, no kernel driver

**Rejected:** a custom Linux kernel module; a virtio or network path (UDP/Ethernet to the fabric); DMA descriptors.
**Chosen:** a **generic UIO device**: the device tree overlay declares a 1 MB region with `compatible = "generic-uio"`; the kernel
exposes it as `/dev/uio0`, and an ordinary process `mmap`s it. **Reason:** a kernel module means building against the board's
exact kernel, which makes a distributable package fragile. UIO ships in the stock kernel; only a kernel command line option
(`uio_pdrv_genirq.of_id=generic-uio`) is needed; check that it is present on your image. As a fallback the daemon can also map
the window through `/dev/mem` (`cp300d.py --mem 0x41000000`, root only); the installed service always uses `--uio /dev/uio0`.
**Cost:** CPU-driven (programmed I/O) transfers. We measured that is adequate (section 10): a full frame is read in about 1.5 ms.

### D4. The host *polls*; the interrupt line is wired but not used

The fabric raises a level interrupt for a pending disk request (`irq = busy`), and `make_cape.py` wires it to bit 0 of the cape's
`INT[23:0]` bus. It stops there: the device tree overlay declares no `interrupts` property, so the UIO device has no IRQ and
`read()` on `/dev/uio0` would never return. The daemon polls the status register on a 0.5 ms (busy) / 4 ms (idle) schedule.
**Reason:** it removes a whole class of failures (UIO interrupt re-arm semantics, missed edges), and the disk path is not latency
critical *at that granularity*: the emulated floppy controller stays busy until the IO controller's firmware has the data, and the
firmware waits up to about one second per request before it reports an error. Switching to the interrupt is listed as future work
(it needs the `interrupts` property in the overlay as well as the daemon change); it would lower idle CPU use, not change function.

### D5. Frames are *pulled*, double-buffered, and validated by a counter, not by locking

The fabric always writes the picture; the host reads whichever buffer is complete. There is no lock between them. A 16-bit frame
counter bracketing the read tells the host whether the writer lapped it (section 5.4). **Reason:** a lock would need the fabric to
wait for Linux, which would stall the emulated machine whenever Linux stalls. The machine's timing must not depend on the host.

### D6. Audio is sent as *edges with microsecond timestamps*, not as samples

The CP-300's sound is one bit toggled by software. We could sample it at 44.1 kHz in the fabric. **Rejected:** that quantises
the timing, wastes bandwidth when silent and makes the host regenerate the signal anyway. **Chosen:** push `{level, time_µs}` on
every change; the browser reconstructs the waveform at its own sample rate. **Reason:** the data rate follows the machine's actual
activity (silent = zero traffic), the timing is exact to 1 µs, and the host/browser latency does not distort the *shape* of the
sound, only delays it (section 5.5).

### D7. The host is the machine's disk; the fabric is the *client*

This inverts the usual direction. When the emulated CPU reads a sector, the IO controller (a helper Z80 inside the fabric)
*requests* a byte range from the host by raising a toggle, and the host answers by filling a RAM and writing DONE. **Reason:**
the fabric has no file system and no storage; the host has both. A mailbox in the register map is the simplest contract that
puts all file handling (format conversion, persistence, download) in Python, where it is a few dozen lines and easy to test
without hardware.

### D8. Treat the register window as a 32-bit bus with no byte strobes

Discovered the hard way (section 11): the window has no byte enables. All access goes through a ten-line C helper that issues
real `lw`/`sw`. **Rule adopted:** *no layer above that helper ever assumes a byte or half-word store works.*

### D9. A single bridge from a 50 MHz bus to a 42 MHz core, with a request toggle handshake

**Rejected:** a dual-clock FIFO per register class; running the whole core on the bus clock. **Chosen:** a four-state toggle
handshake that moves exactly one register access at a time between the domains. **Reason:** one mechanism covers every
register and every RAM window; the throughput it costs (one access at a time) is irrelevant for what crosses it
(section 5.2).

### D10. Ship a package with an installer, not a build recipe

The gateware is built with a non-public-toolchain version (Libero SoC 2026.1, unofficial for this framework) and a custom
bootloader build; no end user should repeat that. The package contains the bitstream, the overlay, the daemon, the web page,
the service, the web-server and Cockpit integration, and an installer that is idempotent and asks for an explicit acceptance
before it touches the flash (section 9).

---

## 4. The platform: what the BeagleV-Fire gives you

Understanding the integration points matters more than the device details, because they are the part that transfers to other
SoC-FPGA boards (Zynq, Cyclone V SoC, Agilex, other PolarFire SoC boards).

* **The MSS (microprocessor subsystem)** contains the RISC-V cores, the memory controller and the buses; its configuration is
  *generated* (`pfsoc_mss`) and is not part of the fabric design.
* **The FIC (fabric interface controller)** exposes the fabric as address ranges in the processor's physical map, and carries
  fabric interrupts back. In the BeagleV-Fire framework the fabric bus is `fabric-bus@40000000` in the device tree, and a "cape"
  component receives an **APB3 slave** port at `0x41000000` (16 MB of window; the CP-300 uses the first 1 MB), plus 24 interrupt
  lines.
* **The gateware framework** (BeagleBoard.org, `git.beagleboard.org/beaglev-fire/gateware`) is a Libero Tcl build system that
  assembles the MSS, the stock infrastructure and a selectable *cape option*. Adding a design means adding a cape directory; this
  is done by `syn/beaglev-fire/gateware/make_cape.py`.
* **Boot and flashing.** The board's bootloader (HSS) and the fabric bitstream live in SPI flash. Reprogramming the fabric means
  rewriting that flash through `change-gateware.sh`, **with no fallback copy**. This single fact shaped the installer and the
  disclaimer more than anything else.

**Transferable rule:** on any SoC-FPGA, find out first (1) how the CPU addresses fabric registers and how wide and strobe-capable
that path is, (2) how the fabric's identity is communicated to the OS (device tree here), (3) what happens when the fabric is
reprogrammed while Linux is running, and (4) how you get back if you break the boot path. Everything else follows.

---

## 5. The FPGA/CPU interface

This is the heart of the paper. The address map and registers are the contract; the rest of the system is an implementation of it.

### 5.1 The address map (window offsets)

```
0x00000  registers (64 words)              ID, control, status, keys, frame/audio counters, disk request, slot table
0x10000  ROM load window     (write only)  word n of the ROM image at 0x10000 + 4n
0x20000  track RAM, 16 KB    (read/write)  disk data in transit, little-endian words
0x30000  frame RAM, 2 x 12 KB (read only)  buffer 0 at 0x30000, buffer 1 at 0x34000
```

Four windows decoded by `addr[19:16]`. Unmapped windows read as zero. The full register list is in
[section 14](#14-reference-register-map-and-message-formats).

**Design rule used throughout:** *one register file is the only interface; the other windows are bulk memories hanging off the same
address decoder.* A new peripheral on the fabric costs one more `case` arm and one more window, never a new bus.

### 5.2 Crossing from the 50 MHz bus to the 42 MHz core

The APB3 slave (`apb_regbus.v`) runs on PCLK; the machine runs on its own PLL-derived 42 MHz clock. Rather than synchronise
every signal, the bridge synchronises a single bit:

```
PCLK domain                                   core clock domain
-----------                                   -----------------
psel&penable&!busy → latch addr/wdata/wr
                   → req_tog flips   ──2FF──► rq2 != rq3 ?  → drive b_addr/b_wdata, b_wr or b_rd for 1 clock
                   busy = 1                      read: wait 2 clocks for data (registered RAM outputs)
                                                 r_rdata captured
ack2 == req_tog ◄──2FF── ack_tog flips ◄──────── done
→ prdata = r_rdata, pready = 1 (1 clock), busy = 0
```

Properties worth copying:

* **Only one flag is ever in flight per direction**, so single-bit toggles through a two-flop synchroniser are safe. The *data*
  (address, write data, read data) is *not* synchronised; it is stable for the whole handshake by construction (latched before the
  toggle, read after the acknowledge). This is the standard "data is quasi-static while the handshake is active" argument; the
  timing tool is told nothing special because the data paths are launched by one edge and consumed several clocks later.
* **PREADY is used.** APB3 permits wait states; the master stalls on the bus until `pready`. This is why a 12 KB frame can be read
  with ordinary loads: the CPU simply waits as long as the bridge needs, and no software retry exists. The framework's template
  cape exposes only `PRDATA`; `make_cape.py` adds the `PREADY` and `PSLVERR` ports to the cape and maps them onto its APB bus
  interface; without them the bridge's wait states would never reach the bus. `PSLVERR` is tied to 0.
* **The cost** is several clocks of each domain per register access (two synchroniser stages each way plus the state machine). That is irrelevant for the control and mailbox traffic and, for
  the frame, simply defines the 1.5 ms bulk read (section 10).
* **A `PAGED` mode** exists for a bus window smaller than 1 MB: 4 KB pages, an 8-bit page register (address bits 19:12) at window
  offset `0xFFC`. It is not used on the BeagleV-Fire but is the escape hatch for narrower windows on other boards. It is **not
  simulated**: `sim/tb_apb.v` instantiates the bridge with `PAGED = 0` only (its header comment says "plain and paged", but no
  paged test exists yet).
* **A known gap:** there is no bus timeout. If the 42 MHz clock were absent the CPU would hang on the access. The core domain's
  reset is held by `pll_locked`, but the bridge itself would still wait. On the improvement list.

### 5.3 Control and the start sequence

`CTRL` bit 0 (`run`) holds the whole machine *and the IO controller* in reset while zero. The order of operations matters and was
a bug source (section 11):

```
1. CTRL = 0, SCAN_VALID = 0        # hold everything
2. write the two ROMs (big-endian packed words) into the ROM load window
3. CTRL.run = 1                    # release the IO controller (the CP-300 stays held by io_hold)
4. publish the slot table: SIZE_n, PRESENT, then SCAN_VALID = 1
5. the IO controller sees "scanned", mounts drive 0 if present, releases io_hold → the CP-300 starts
```

Step 3 before step 4 is mandatory because the slot-table registers are themselves held cleared while `run = 0`.

### 5.4 The screen: frame capture and tear-free reads

**Capture (`bvf_fb.v`).** The core already produces a pixel stream with `pxen` (pixel enable), `screen` (inside the picture),
`ink` (the pixel) and `vs_n` (vertical sync). The capture block counts x and y, shifts 32 pixels into a word, and writes the word
into RAM when the 32nd pixel arrives. A frame is 512 × 192 × 1 bit = 12 288 bytes = 3072 words.

* **Word layout:** `word = y * 16 + x / 32`; pixel *x* is **bit (x mod 32)**, leftmost pixel least significant. This was chosen so that
  the host sees *LSB-first bytes in reading order* on a little-endian CPU, which is what the browser's draw loop wants, so the
  daemon never shuffles bits.
* **Two buffers.** The writer fills buffer `wbuf`; when the last line ends it publishes (`lat <= wbuf`, `frame_cnt++`) and flips.
  The host reads buffer `latest`, which the writer will not touch again for one full frame time (16.7 ms).

**Tear-free read without a lock.** The host does:

```
f0 = read FRAME                      # {latest buffer, counter}
data = bulk-read 12 KB from buffer(latest of f0)
f1 = read FRAME
accept data iff (counter(f1) - counter(f0)) mod 65536 < 2
```

If the counter advanced by at most one, the writer was filling the *other* buffer the whole time and `data` is a consistent frame.
If it advanced by two or more, the writer came back around to the buffer being read, so the copy is discarded and retried
(up to three times). A dropped frame costs nothing; the next one arrives 16 ms later. The test needs no cooperation from the
fabric beyond the counter.

**Why not read-out line by line, or use a larger buffer ring?** The two-buffer scheme gives the host a whole frame time to read.
Our read takes about 1.5 ms of a 16.7 ms window, so the retry path almost never triggers (the daemon counts it:
`stats.dropped`). A ring would only be needed for much slower hosts.

**Generalisation.** For any "FPGA produces a rate-limited data stream, host samples it" problem: *double buffer + monotonic
counter read before and after, accept if the counter distance is small enough that the writer cannot have reached your buffer.*
This pattern works for sensor frames, ADC blocks, trace buffers and so on.

### 5.5 The audio: edges with timestamps

The core's speaker output is a small integer (three levels). `bvf_audio.v` compares it with the previous value every clock; on a
change it pushes `{level[8:0], time[22:0]}`, where time is a free-running **microsecond counter** (the 42 MHz clock divided by 42;
wraps at 2²³ µs = 8.39 s). A 256-entry FIFO sits between fabric and host; the host reads `AUDIO` (count), reads `AUDIO_HEAD`, then
writes to pop. On overflow, new edges are dropped and a sticky `lost` flag is set (cleared by the host). The FIFO and `lost` are
reset while `CTRL.run = 0`; the microsecond counter is not, it runs freely. The daemon never clears `lost`; it only appears in
`STATUS`.

Why timestamps, not a sample stream:

* **Silence is free.** Between sounds nothing is pushed; the host sees `count = 0` and does no work.
* **Exact timing.** Edge spacing is 1 µs precise, independent of how late the host polls.
* **Latency is a constant, not a distortion.** The browser schedules audio with a play-head slightly ahead of the audio clock
  (about 60 ms), and converts timestamp differences into sample counts. The waveform is reproduced faithfully and merely delayed.
* **Robustness.** A host stall just means the FIFO holds edges longer; the 256 entries bound how long a stall can be absorbed (it depends on how busy the sound is). If it is exceeded, `lost` tells you.

The 23-bit wrap is handled by the browser with a masked subtraction (`(t - lastT) & 0x7FFFFF`), valid as long as consecutive events
are less than 8.39 s apart. Each interval is clamped to one second of samples, so a long pause is never rendered as a long run of the
old level; and once the play-head has fallen behind the audio clock (any pause longer than the ~60 ms lead) the browser starts over
and drops the interval before the next edge, so a gap that wrapped the counter cannot be misread either.

### 5.6 The disk: a mailbox where the fabric is the client

The emulated floppy controller (WD1793) needs sector data. In the fabric, a helper Z80 (the *IO controller*) runs a small C
firmware (`firmware/dmk.c` with `firmware/pocket/slotfile.c`, the same code as on the Pocket). It sees the image as 512-byte blocks
and keeps a block cache in the track RAM. When the WD1793 needs a track, the firmware asks the host, in one request, for the run of
blocks that covers that track of the DMK image; when sectors are written, it writes the changed blocks back (consecutive blocks in
one request). So a request's offset is always a multiple of 512 and its length is a whole number of blocks (shorter only for the last
block of the image), at most 16 KB. The interface to the host:

```
fabric → host:   REQ_SLOT, REQ_OFFSET, REQ_LEN, REQ_BOFF   (what to move; BOFF = where in track RAM)
                 STATUS.pending, STATUS.is_write
host → fabric:   track RAM (read request: host fills; write request: host drains)
                 DONE (b0 = error)        completes the request
```

Handshake: the IO controller flips `req_tog`; `bvf_dataslot` computes `busy = req_tog ^ done_tog`. The host sees `pending`,
fetches the four request registers, moves the data through the **track RAM window**, and writes `DONE`, which flips `done_tog`,
dropping `busy` so the firmware continues. The error bit of the last `DONE` is latched and shown both to the firmware and in
`STATUS` b4. Two toggles instead of a request/ack pair of levels means that no signal needs clearing, which removes a whole race class.
The firmware gives up on a request after about one second (a poll-count timeout), so the host must answer within that time.

**Track RAM** is a 16 KB true dual-port RAM built from four byte lanes (`bvf_trk_ram`): one port for the host (32-bit words), one
for the IO controller (bytes, with `addr[1:0]` selecting the lane). Little-endian lane order was chosen so that Linux sees the
bytes in file order (the Pocket's version was big-endian). This is a representative cross-agent buffer: **two independent
masters of different widths on two ports of one RAM, with a toggle handshake as the only synchronisation**.

**The slot table.** The host also tells the fabric *which drives hold a file* (`PRESENT`), *how large* (`SIZE_n`), and *which were just
replaced* (`CHG_SET`). The "changed" bits are kept as an XOR of a host-toggled register and a fabric "seen" register
(`changed = cg ^ seen`), so the host sets a bit by toggling and the fabric clears it by copying: again, neither side writes the
other's state.

**Persistence.** A write request lands in the host's in-memory copy of the DMK (clipped to the image size; a read past the end is
padded with zeros); a dirty flag is set only if the bytes actually changed; every two seconds the daemon writes dirty images to
`/var/lib/cp300/driveN.dmk`. A newly mounted image is written there at once. A page's *Download* button gives the image back (as DMK). Uploaded `.dsk/.jv1/.jv3/.hfe` files are
converted to DMK by `tools/dsk2dmk.py` in the daemon: format knowledge lives in Python, not RTL.

---

## 6. The gateware

### 6.1 Module map (`syn/beaglev-fire/rtl`)

| Module | Role | Clock |
|---|---|---|
| `bvf_core_apb.v` | top: APB3 slave in, `irq` out; instantiates the bridge and the core wrapper | PCLK + 42 MHz |
| `apb_regbus.v` | APB3 ↔ simple register bus, toggle CDC, optional paging | both |
| `bvf_core_bus.v` | the CP-300 + IO controller + capture + audio + registers, wired together | 42 MHz |
| `bvf_regs.v` | register file, address decoder, read mux | 42 MHz |
| `bvf_fb.v` | pixel stream → frame RAM (2 buffers) + counter | 42 MHz |
| `bvf_dataslot.v` | disk request handshake, slot table, track RAM wrapper | 42 MHz |
| `bvf_trk_ram.v` | one byte lane of the dual-port RAM | 42 MHz |
| `bvf_audio.v` | edge detector + µs timestamp + 256-entry FIFO | 42 MHz |
| `bvf_core.v`, `axil_regbus.v` | AXI4-Lite variant of the wrapper, kept for the simulation and as an alternative bus | |

All plain, vendor-neutral Verilog: RAMs are *inferred*, no vendor megafunctions. The only vendor primitive is the PLL, generated by
Libero from a one-line Tcl core description (`PF_CCC`, 50 MHz in, 42 MHz out).

### 6.2 Read timing convention

`bvf_regs` documents a convention that every block follows: **read data is valid two clocks after `rd`**. RAM outputs are registered
(one clock) and the window mux is selected by a delayed copy of the address (`win_q`), so that the mux selects the *window of the
previous request*, not the one currently on the bus. Every block with a RAM (frame, track RAM) honours the same one-clock latency.
Fixing this convention once, in a comment at the top of the register file, saved having to reason per block about when data appears.

### 6.3 Resets and the "held" states

There are three nested "hold" conditions, and keeping them straight is most of the debugging:

```
core_reset  = ~run | ~pll_locked | io_hold | rst_pulse        the Z80 system
IO reset    = ~run | ~pll_locked                               the helper Z80 + slot table + disk handshake
audio reset = ~run                                             the edge FIFO and its `lost` flag
regs reset  = ~pll_locked                                     the register file itself (so `run` can be written)
```

The register file holds `CTRL` and the keys, so they survive `run = 0`. The frame capture has no reset at all: it captures whatever
the core's video circuit produces, so the frame counter and buffers are never cleared by the host.

`io_hold` is raised by the IO controller itself after reset and cleared by its firmware once it has mounted drive 0. This is how
"the CP-300 starts only when the disk is ready" is realised without any host involvement beyond the slot table.

### 6.4 What was *not* put in the fabric

Decisions to keep the fabric small (it ends at 78% of the LUTs and 88% of block RAM): no frame buffering beyond two buffers; no
compression in RTL (done in Python/zlib); no audio resampling; no ROM storage (the ROMs are loaded at run time: the two images are
copyrighted, so they are never part of a bitstream or a package); no file system.

---

## 7. The host side: the Linux daemon

`host/cp300d.py` is about 650 lines of standard-library Python (no pip packages, so the package installs on the stock image) with
three layers.

### 7.1 Register access: `regs32.c`

Ten lines of C compiled on first use with `gcc` (and cached next to the daemon, falling back to the temp directory when the
install directory is read-only), called through `ctypes`:

```c
uint32_t rd32(uintptr_t a)             { return *(volatile uint32_t *)a; }
void     wr32(uintptr_t a, uint32_t v) { *(volatile uint32_t *)a = v; }
void rdblk(uintptr_t a, uint32_t *dst, size_t words);   // word loop, volatile
void wrblk(uintptr_t a, const uint32_t *src, size_t words);
```

Why this exists is [lesson L1](#l1-the-window-has-no-byte-strobes). Why a *block* routine exists: a 3072-word frame read through
`ctypes` one word at a time would spend its time in the call overhead; one call per frame reduces it to the loop, which is what
brings the frame read to about 1.5 ms.

### 7.2 The device object

`Cp300` exposes the machine as methods that mirror the interface contract:

* `start()`: hold, load ROMs, release, publish slots (the order of section 5.3).
* `mount(n, blob, name)` / `eject(n)`: convert, store (saved to the data directory at once), update `SIZE_n`, `PRESENT`, toggle
  `CHG_SET`. Eject deletes the saved image.
* `service()`: the mailbox: read `STATUS`; if pending, read the four request registers, validate (`len ≤ 16384`,
  `boff + len ≤ 16384`, slot has a file, otherwise `DONE(err=1)`), move data, `DONE`.
* `new_frame()`: the bracket-with-counter read of section 5.4.
* `audio_events()`: pops up to 128 edges per call.
* `debug()`: the bring-up probe (below).

A `SimRegs` class implements the same interface against a Python model (it draws a picture of the keys pressed and answers disk
requests), so **the daemon and the web page can be developed and tested with no hardware at all** (`--sim`; `test_cp300d.py` is a
test suite built on it). Writing the register-file *interface* as a replaceable class was probably the best productivity decision of
the project: the entire web side was finished before the gateware was.

### 7.3 The pump

A single `asyncio` task is the hardware loop, in priority order:

```
loop:
    while service(): ...            # disk requests first: the emulated CPU is blocked on them
    f = new_frame()                  # at most once per hardware frame
    if f and clients: for each client: send zlib(frame XOR previous frame) over the WebSocket
    ev = audio_events()              # forward edges to every client
    every 2 s: save dirty disk images
    sleep 0.5 ms if there was disk work, else 4 ms
```

Notes for reuse:

* **Priority.** Anything the *hardware* blocks on is served before anything the *user* sees. The disk path got 0.5 ms polling;
  video is allowed to drop.
* **Frame transport.** Each client receives the XOR of the current frame with its own previous frame, compressed with zlib level 1.
  Most of the time most pixels do not change, so a frame becomes a few hundred bytes. If a client has no previous frame (new
  connection) it receives a "key" frame (kind 0). This is plain delta coding; it was chosen over PNG/JPEG because it is lossless,
  trivial in both directions, and the browser has a native `DecompressionStream`.
* **Python is the bottleneck, not the bus.** The measured frame rate in the page is about 40 fps against a 60 Hz source. The bulk read
  is 1.5 ms; the XOR (a Python loop over 12 288 bytes) and WebSocket framing dominate. This is known and unfixed: moving the XOR
  into `regs32.c` or into the fabric would remove it.
* **Disconnect safety.** When the last browser disconnects the keyboard register is zeroed, so no key can stay "pressed" in the
  machine.

### 7.4 A bring-up probe built into the product

`GET /api/debug` returns the control, status, frame, debug-byte and audio-count registers, the time of 1000 register reads, the
time of one frame read, a **write-readback test** and the measured frame counter rate over one second. The readback test writes
`0xA5A55A5A` to `KEYS_LO` and reads it back; writes `CTRL = 1` and reads it back, then re-applies the daemon's own control state;
and writes an eight-byte pattern *as a block* over `KEYS_LO`/`KEYS_HI` to detect byte-store corruption. It leaves the keys at zero
(not at their previous value), and the `CTRL = 1` write starts the machine for a moment if it was stopped, so it is a bring-up tool,
not something to call while a program runs. The call also blocks the daemon for the one-second rate measurement. The integration bugs of section 11 (L1 to L3) were isolated
with this kind of probe. If you build one thing before your first board bring-up, build this.

---

## 8. The web protocol and the page

### 8.1 Transport

One HTTP server, written on `asyncio.start_server`, with a hand-written WebSocket (RFC 6455) of about forty lines: handshake
(`Sec-WebSocket-Accept`), frame encode (7/16/64-bit lengths), frame decode with client masking, ping/pong, and a close that just
drops the connection (no close frame is echoed). Client binary messages are ignored. No third-party dependency was a deliberate
decision (see D10); limitations are no TLS (the board's nginx or Cockpit can terminate it) and no fragmentation support, which the
page never uses. Request bodies above 4 MB are refused with HTTP 413, matching nginx's `client_max_body_size 4m`.

| Endpoint | Use |
|---|---|
| `GET /` | the page |
| `GET /ws` | WebSocket (below) |
| `GET /api/state` | JSON state: run/turbo/wp, ROM presence, drive names and sizes, counters |
| `GET /api/debug` | the bring-up probe |
| `PUT /api/disk/N?name=X` | upload an image, converted to DMK and mounted |
| `GET /api/disk/N` / `DELETE` | download (as DMK) / eject |
| `PUT /api/rom/system` / `chargen` | exactly 16384 / 2048 bytes, else HTTP 400; saved, and once both are present the machine is (re)started |
| `POST /api/ctrl` | `{run, reset, turbo, wp}` |

### 8.2 WebSocket messages

```
server → browser, binary:
  0x01 | seq u16 LE | kind u8 | zlib(payload)         frame; kind 0 = whole frame, kind 1 = XOR with the previous frame
  0x02 | (time u32 LE, level u16 LE) × n              audio edges (time is the 23-bit µs counter)
server → browser, text:   JSON state (sent on connect and on every change)
browser → server, text:   {"keys": "<16 hex digits>"}  the whole 64-bit matrix, every change
                          {"ctrl": {...}}              run / reset / turbo / wp
```

Design points:

* **The keyboard is sent as the *whole state*, not as events.** The browser holds the set of pressed matrix bits and sends the
  full 64-bit mask on every change. A lost or reordered message cannot leave a key stuck, and the daemon does no key logic, it
  writes two registers. (This is the right choice whenever the receiver wants a level and not an edge.)
* **State is pushed.** Every change on the server is pushed to all clients; clients do not poll.
* **Frames are in order and, per client, complete.** The daemon may skip hardware frames, but every frame it reads goes to every
  client, so each client's XOR chain is unbroken; TCP keeps them in order. `seq` is sent but the page does not use it. The only
  key frame a client gets is the first one after it connects. **Known gap:** if the page fails to decode a frame it drops its
  `prev` frame, but the server does not know and keeps sending XOR frames, which the page then draws as they are (wrong picture)
  until the WebSocket reconnects. A "send me a key frame" message, or a key frame every few seconds, would close this.

### 8.3 The page (`host/web/index.html`)

A single self-contained file, no framework, no build step, about 290 lines.

* **Keyboard mapping is from *characters* to the machine's *matrix*,** not from physical keys, with an explicit table of how the
  original keyboard types shifted symbols (`"` = shift+2, as on a Model III). Rationale: users type the character they see on their
  keyboard layout (a Brazilian layout and a US layout differ), and the machine's BASIC wants characters. An on-screen keyboard
  built from the same table makes the page usable on a tablet.
* **Picture.** The decoded bytes are expanded to RGBA and drawn with `putImageData` to a 512 × 192 canvas scaled by CSS to a **4:3**
  box with `image-rendering: pixelated`. The aspect ratio is a *presentation* decision: the real tube displays 512 × 192 on a 4:3
  screen, so each dot is 2× wide and 4× tall. The first version was "correct" in pixels and visibly stretched, which is the lesson:
  *fidelity of a retro display is a property of the display geometry, not of the framebuffer.* The phosphor colour (white, green,
  amber) is a client-side setting stored in `localStorage`.
* **Audio.** A user gesture is required by browsers before audio can start; the *Sound* button creates and resumes the
  `AudioContext`. Incoming edges are converted into runs of constant level (samples = Δt × sample rate), written into an
  `AudioBuffer`, and scheduled back-to-back at a play-head kept ~60 ms ahead of `currentTime`. If the play-head falls behind
  (a gap), it restarts and the first edge after it is not rendered, to avoid a click.
* **Relative URLs.** The page may be served under a prefix (`/cp300/` via the board's nginx), so it derives `BASE` from
  `location.pathname` and uses no absolute path. Missing this makes pages that work on `localhost:8300` break behind a reverse proxy.
* **Never trusts the server's HTML:** drive names are inserted with `textContent`.

---

## 9. Delivery: device tree, build, package, installer

### 9.1 The device tree overlay

The same overlay does three jobs (`gateware/CAPE/CP300/cp300.dtso`):

```dts
&{/chosen} { overlays { CP300-GATEWARE = "GATEWARE_GIT_VERSION"; }; };      // an identity the OS can read

&{/fabric-bus@40000000} {
    cp300: cp300@41000000 { compatible = "generic-uio"; reg = <0x0 0x41000000 0x0 0x100000>;
                            clocks = <&fabric_clk3>; status = "okay"; };
};
```

* `/chosen/overlays/CP300-GATEWARE` is how the *board* reports which gateware is loaded. The installer and the Cockpit page read
  it to decide "is CP-300 loaded or did someone flash another design?" The framework substitutes the git version.
* `generic-uio` makes `/dev/uio0` with name `cp300` (`/sys/class/uio/uio0/name`). The systemd unit refuses to start the daemon unless
  that file reads `cp300`, so a different gateware can never be driven by this software. The service runs as the ordinary user
  `beagle`; the installer's udev rule (`99-cp300-uio.rules`, group `kmem`, mode 0660) gives it access to the device.
* The overlay has no `interrupts` property (see D4).

### 9.2 Building the gateware

The full procedure, step by step with the exact commands, versions and pitfalls, is in the repository:
**[`syn/beaglev-fire/BUILDING.md`](../syn/beaglev-fire/BUILDING.md)**. In outline it is:

1. clone the gateware framework and check out the commit of the board's stock gateware (`943f37f`, `2025.10-13`);
2. generate the MSS configuration with `pfsoc_mss`;
3. build the HSS bootloader at the commit the framework pins (`4bea7e2`, with the framework's patches; SoftConsole in WSL);
4. run `python syn/beaglev-fire/gateware/make_cape.py <framework>` to add `CAPE_OPTION:CP300`;
5. make the two documented edits to the scratch framework copy (Libero version check, AXI interconnect version);
6. run `BUILD_BVF_GATEWARE.tcl` in Libero with `CAPE_OPTION:CP300` and a new `DESIGN_VERSION`, which exports
   `LinuxProgramming/` (`mpfs_bitstream.spi`, `mpfs_dtbo.spi`);
7. build the package with `syn/beaglev-fire/package/build_package.py --gateware <dir>`.

The structural points:

* `make_cape.py` **adds** a cape option to a checkout of the framework: it copies the `VERILOG_TEMPLATE` cape, replaces its
  `apb_ctrl_status` register block with the CP-300 instance and a PLL, adds `PREADY`/`PSLVERR` to the cape's ports and APB bus
  interface, routes `irq` to `INT[0]`, stages the HDL (stripping `translate_off` blocks that Libero's parser ignores; forcing one
  small array, `head_pos` in `wd1793.vhd`, to registers to avoid a synthesiser error), generates the import script, and replaces
  the template's cape overlay with `cp300.dtso` (the template's LED overlay stays). The framework itself is
  never edited in the repository; two small edits made on a scratch copy are documented instead.
* **Pin the framework to the stock gateware's version.** A framework newer or older than the bootloader/MSS the board was shipped with
  can give a design that boots to nothing. We pinned to the commit that matches the board's stock gateware, and the HSS to the one
  that commit pins.
* **The identity string must be unique per design** (`…-CP300`) and the design *version* number must differ from what is loaded or the
  board will not reprogram.

### 9.3 The package and the installer

`package/build_package.py` produces a byte-reproducible `tar.gz` (sorted entries, fixed owner and mtime) plus a SHA-256. Contents:
installer, load helper, daemon, page, `dsk2dmk.py`, service/nginx/Cockpit files, the two flash images, `VERSION`, `GATEWARE_ID`
(extracted from the overlay image itself, the string ending in `-CP300`), `SOURCE.txt` (source URL, commit, gateware checksums),
`README.txt`, licence and disclaimer. Text files are normalised to LF line endings (see L6). The test suite is left out.

`install.sh` is **idempotent and layered**, because the three things it installs have very different risk:

| Layer | Risk | Behaviour |
|---|---|---|
| Software (`/opt/cp300`, service, udev rule, `cp300-load-gateware`) | none | always replaced; `regs32.so` is compiled at install (gcc is installed if missing) |
| Web integration (nginx snippet, Cockpit entry) | low | replaced; the original site file is backed up once, outside `sites-enabled` |
| **Gateware flash** (bitstream, overlay and HSS bootloader) | **can brick the board** | only if not already loaded; shows the disclaimer; requires typing `I ACCEPT` (or `--yes`) |

Options (`--yes`, `--no-flash`, `--no-web`, `--force-flash`, `--check`, `--uninstall [--purge]`) make each layer individually
reachable. `--check` changes nothing and reports installed version, loaded gateware and daemon state: **the first command a
support conversation should ask for**.

**Coexistence.** The service starts only if the CP-300 gateware is the loaded one; flashing a different design leaves the software
and the Cockpit entry in place, dormant, and `cp300-load-gateware` brings the CP-300 back. This was an explicit requirement: users
swap gateware often, and the integration must survive that.

**The web-server integration is a snippet plus one line in the stock site.** The configuration lives in
`/etc/nginx/snippets/cp300.conf`; the only change to the stock site file is one `include snippets/cp300.conf;` line inserted after its
first `server_name`, which `--uninstall` removes again. The snippet (`location /cp300/ { proxy_pass http://127.0.0.1:8300/; …}`, plus a
redirect from `/cp300`) includes WebSocket upgrade headers and `proxy_read_timeout 1h`, `client_max_body_size 4m` for uploads. Cockpit gets a
sidebar *landing* page; opening the page in a new tab, rather than embedding it, is deliberate: Cockpit is served over HTTPS and a
browser refuses to frame an `http://` page inside it (mixed content), and Cockpit's CSP blocks inline scripts, so the entry's logic
is an external `cp300.js` using Cockpit's own channel APIs.

---

## 10. Performance and resources

All numbers are from the author's board with the stock 2025.10-13 gateware base unless noted.

| Quantity | Value | Note |
|---|---|---|
| Machine clock | 42 MHz | PF_CCC from the 50 MHz PCLK |
| Resources | 17,890 / 22,956 4-input LUTs (78%), 18,952 LE (83%), 74 / 84 large block RAMs (88%) | timing met; little room left |
| Register window | 1 MB used of 16 MB | at `0x41000000` |
| Frame | 512 × 192 × 1 bit = 12,288 bytes | 3072 words |
| Bulk frame read | about 1.5 ms | one `rdblk` call |
| Frame rate in the page | about 40 fps (hardware 60 Hz) | Python (XOR + framing) is the limit |
| Audio FIFO | 256 edges, 1 µs timestamps, 8.39 s wrap | |
| Disk transfer unit | up to 16 KB per request (a track) | one mailbox cycle |
| Polling | 0.5 ms with disk activity, 4 ms idle | interrupt unused |
| Host CPU | one Python process, one core | |

**Where the time goes, in the order we would fix it:** (1) the Python XOR over the frame: do it in C (the helper library already
exists) or in the fabric; (2) polling: use the interrupt; (3) frame dedup: skip the whole pipeline when the frame counter has not
moved, which already happens. The *bus* is not the bottleneck at any point.

---

## 11. Lessons learned

These cost the most time. They are listed so that they cost the next project less.

### L1. The window has no byte strobes

*Symptom:* writes read back as one byte repeated in all four lanes (a word written was read as the same byte four times), and the data moved through the window was corrupt.
*Cause:* the fabric window is an APB3 bus with no `PSTRB`; the CPU's byte store sends the whole data bus, and Python's `memcpy`
and `struct.pack_into` perform byte stores on this core. *Fix:* all access through `lw`/`sw` in C. *Rule:* **prove 32-bit read/write
integrity with a probe before anything else**, and make "never a byte access" a property of one small module.

### L2. Reset order across a held state

*Symptom:* the machine never started although all registers looked correct. *Cause:* the slot-table registers are cleared while
`run = 0`; the daemon had published the slot table first and *then* released `run`, which erased it, and the firmware waited forever
for "scanned". *Fix:* release the IO controller, then publish (section 5.3). *Rule:* **write down which registers belong to which
reset domain, and make the init sequence follow it.** A comment table of the domains (section 6.3) is cheap.

### L3. Torn frames

*Symptom:* torn frames in the browser. *Cause:* the frame was read through a slow path while the writer advanced. *Fix:* a fast bulk read and the counter bracket of section 5.4. *Rule:* **any reader of a
fabric-written buffer needs a consistency check designed in, not retrofitted.**

### L4. The toolchain version is part of the design

The framework, the MSS configuration, the bootloader and the synthesis tool must be a *matching set*. We first built on the
framework's `develop` branch, which turned out to be much older (2023) than the board's stock gateware; we rebuilt on the exact
commit of the stock gateware and used that. An *unofficial* Libero version needed two
documented edits (a version check, and pinning the AXI interconnect IP to the version that has a parameter the scripts set).
*Rule:* **identify the exact stock build first; match to it; treat any deviation as a known risk in the disclaimer.**

### L5. Synthesis surprises from "innocent" RTL

A small array with a reset was inferred as RAM and then rejected because of its initial value (an `MF682` error); Libero's parser
ignored `translate_off` pragmas so simulation-only code was synthesised. *Fixes:* strip pragma blocks in the staging script; give the synthesiser an explicit
`syn_ramstyle = "registers"` hint; remove initial values from arrays that have a reset. *Rule:* **simulate with the vendor's
synthesis semantics in mind, and script the adaptations** so they are reproducible and not edits of someone's checkout.

### L6. Systems integration is half the work

None of these were gateware bugs: a duplicate `default` server in nginx because a backup file had been left in `sites-enabled`; the
Cockpit page stuck at "checking…" because of its Content-Security-Policy; an https page that cannot frame an http one; a systemd
unit that must be conditional on the gateware; a path prefix that broke absolute URLs; line-ending changes on files carried from
Windows. *Rule:* **budget as much for the integration with the host's stock software as for the core.**

### L7. Build the whole host side against a simulator first

`SimRegs` made the daemon and the page testable off-board. When the hardware arrived the only failures were the *interface* ones
(L1, L2, L3), which is exactly what a probe like `/api/debug` isolates. Waiting for the hardware before starting the software would have serialised the work.

### L8. State machines on the host that rely on "level" semantics are more robust than "event" semantics

Keys as full masks; `changed` as XOR of two registers; the request as a toggle pair. Every one of these removes a class of lost-event
bugs, at no cost.

---

## 12. What is verified and what is not

**Verified on the author's board** (BeagleV-Fire, Ubuntu 24.04 image of 2025-07-21, kernel 6.6.75, stock gateware 2025.10-13): the
gateware builds, meets timing and boots the board; `/dev/uio0` appears and the ID register reads `0x43503001`; the CP-300 boots
TRSDOS 1.3 from an uploaded disk image; a game plays; keyboard and sound work; the page works through nginx (`/cp300/`) and from the
Cockpit sidebar; the installer's software path and its "already loaded, do not flash" path ran.

**Not verified:**

* The installer's flash-and-reboot path (`--force-flash`) and "another gateware, and back".
* Saving to a disk image across a reset, end to end.
* A recovery with a FlashPro5/6 programmer.
* Boards, kernels or stock gateware versions other than the above.
* A build on the framework's officially supported Libero version (2025.2 or earlier) to remove the doubt about 2026.1.
* The frame rate above about 40 fps; the interrupt path (not declared in the overlay, not used by the daemon).
* The bridge's `PAGED` mode (no simulation, not used on this board).

Flashing the board rewrites its bootloader with no fallback; the README and the package carry a disclaimer and the installer asks for
explicit acceptance.

---

## 13. A checklist for other projects

For any design that pairs an FPGA block with a CPU running an OS, whether a retro core, a sensor front end, a codec, a network
accelerator or a test instrument:

**Interface**
1. Choose **one memory-mapped register file** as the contract, plus **bulk windows** hanging off the same decoder. Version it with an
   ID register that the software checks before doing anything.
2. Assume **32-bit, no-byte-strobe** access until you have proven otherwise. Put all access in one tiny C helper.
3. Classify every flow: *state* (registers, whole-value writes), *stream* (double buffer + counter), *events* (timestamped FIFO),
   *request/response* (mailbox with toggles). Do not force them into one mechanism.
4. Cross clock domains once, at the bridge, with a toggle handshake; keep everything behind it in one clock.
5. Use **level/idempotent** semantics for anything the host sets (full masks, toggles), **counters** for anything it observes.
6. Document the **read latency** convention at the top of the register file and make every block honour it.
7. Give the host a **probe** (`/api/debug`-style): ID, status, timing, readback tests. It is the first thing you will use.

**Host software**
8. Develop the host against a **simulated register file** with the same interface; run the same tests on the hardware afterwards.
9. Serve the hardware before the user: devices the hardware blocks on get the highest polling priority; video may drop frames.
10. Prefer a **web UI** when the device is headless: it needs no client software, runs on a phone, and the board's own web server
    can front it. Use WebSocket for the streams and plain HTTP for the files.
11. Keep format knowledge (file conversion, protocol parsing) out of the RTL.

**Platform and delivery**
12. Identify the platform's stock build and **match it exactly**; write down every deviation.
13. Make the OS discover the design: **device tree overlay with a name and an identity string**; make the service conditional on it.
14. Ship a **package + installer layered by risk**, with `--check` and an explicit acknowledgement before any irreversible step. State
    plainly how recovery works and what it costs.
15. Plan for the design being **swapped out and back**: integration must survive another gateware being loaded.

---

## 14. Reference: register map and message formats

### 14.1 Registers (byte offsets in the window)

| Offset | Dir | Name | Content |
|---|---|---|---|
| `0x00` | R | ID | `0x43503001` |
| `0x04` | RW | CTRL | b0 `run` (0 holds core and IO controller in reset), b1 reset pulse (W), b2 `turbo`, b3 write-protect all disks |
| `0x08` | R | STATUS | b0 core held by IO controller, b1 slot table scanned, b2 disk request pending, b3 request is a write, b4 error bit of the last `DONE`, b5 audio FIFO lost, b6 newest-frame buffer |
| `0x0C` | RW | KEYS_LO | key matrix bits 31:0 (bit = 8 × row + column) |
| `0x10` | RW | KEYS_HI | key matrix bits 63:32 |
| `0x14` | R | FRAME | [15:0] frame counter, [16] buffer that holds the newest frame |
| `0x18` | R/W | AUDIO | R: FIFO count [8:0]; W b0: clear `lost` |
| `0x1C` | R/W | AUDIO_HEAD | R: `{level[8:0], time[22:0]}` of the head; W: pop it |
| `0x20` | R | DEBUG | last byte written to the IO controller's debug port |
| `0x40` | R | REQ_SLOT | drive of the pending request |
| `0x44` | R | REQ_OFFSET | byte offset in the image |
| `0x48` | R | REQ_LEN | byte count (≤ 16384) |
| `0x4C` | R | REQ_BOFF | offset in the track RAM |
| `0x50` | W | DONE | b0 = error; completes the request |
| `0x60 + 4n` | W | SIZE_n | size of the image in drive *n* (n = 0..3) |
| `0x70` | W | PRESENT | mask of drives that hold an image |
| `0x74` | W | CHG_SET | toggle "image replaced" for the drives in the mask |
| `0x78` | W | SCAN_VALID | b0: the slot table has been published |
| `0x10000..` | W | ROM load | word *n* at `0x10000 + 4n`: system ROM words 0..4095, character generator at `0x14000..` |
| `0x20000..0x23FFF` | RW | track RAM | little-endian words |
| `0x30000..0x32FFF` / `0x34000..0x36FFF` | R | frame RAM | buffer 0 / buffer 1; word = y × 16 + x / 32; pixel x = bit (x mod 32) |

ROM words are big-endian packed (first byte in bits 31:24), because the core's ROM port expects that; the daemon does the packing.

### 14.2 Where to look in the repository

| What | Where |
|---|---|
| Register block, decoder and the register map as a comment | [`syn/beaglev-fire/rtl/bvf_regs.v`](../syn/beaglev-fire/rtl/bvf_regs.v) |
| APB bridge and CDC | [`rtl/apb_regbus.v`](../syn/beaglev-fire/rtl/apb_regbus.v) |
| Frame capture | [`rtl/bvf_fb.v`](../syn/beaglev-fire/rtl/bvf_fb.v) |
| Disk mailbox | [`rtl/bvf_dataslot.v`](../syn/beaglev-fire/rtl/bvf_dataslot.v) |
| IO controller firmware (the client of the mailbox) | [`firmware/dmk.c`](../firmware/dmk.c), [`firmware/pocket/slotfile.c`](../firmware/pocket/slotfile.c) |
| Audio FIFO | [`rtl/bvf_audio.v`](../syn/beaglev-fire/rtl/bvf_audio.v) |
| Daemon and register helper | [`host/cp300d.py`](../syn/beaglev-fire/host/cp300d.py), [`host/regs32.c`](../syn/beaglev-fire/host/regs32.c) |
| The page | [`host/web/index.html`](../syn/beaglev-fire/host/web/index.html) |
| Cape, overlay | [`gateware/make_cape.py`](../syn/beaglev-fire/gateware/make_cape.py), [`gateware/CAPE/CP300/cp300.dtso`](../syn/beaglev-fire/gateware/CAPE/CP300/cp300.dtso) |
| Package and installer | [`package/`](../syn/beaglev-fire/package) |
| Simulation | [`sim/`](../syn/beaglev-fire/sim) (Icarus), [`host/test_cp300d.py`](../syn/beaglev-fire/host/test_cp300d.py) |
| Build procedure, step by step | [`syn/beaglev-fire/BUILDING.md`](../syn/beaglev-fire/BUILDING.md) |
| Cape notes, state of the work | [`gateware/README.md`](../syn/beaglev-fire/gateware/README.md), [`HANDOVER.md`](../syn/beaglev-fire/HANDOVER.md) |

### 14.3 Third-party material this work builds on

The HT1080Z core (Jozsef Laszlo), the T80 Z80 core, the WD1793 replica (Slavinsky, Sorgelig, Hodge), the BeagleV-Fire gateware
framework (MIT; Microchip and BeagleBoard.org) and the Microchip Hart Software Services bootloader. Licences: see the
[main README](../README.md#licence-and-credits). This is an independent hobby project; it is not made or endorsed by Microchip,
BeagleBoard.org, Prológica or Tandy.
