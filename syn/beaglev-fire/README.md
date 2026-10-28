# CP-300 on the BeagleV-Fire

The CP-300 core for the BeagleV-Fire (Microchip PolarFire SoC MPFS025T: RISC-V Linux plus about 23K LEs of FPGA fabric). The board has no video output, no keyboard and no SD slot for the core, so the **browser is the monitor, keyboard and disk drive**: a small Linux daemon (`host/cp300d.py`) talks to the fabric over an AXI4-Lite window and serves a web page.

**Status: first implementation.** Simulated and tested on a PC; **not built in Libero and never run on a board.** What passes:

| Test | What it covers |
|---|---|
| `sim/run.sh` (Icarus Verilog) | AXI4-Lite bridge, register block, frame capture (512 x 192 pixel compare), disk mailbox + track RAM byte order, ROM load strobes, audio FIFO, slot table |
| `host/test_cp300d.py` | the daemon against simulated registers: HTTP, WebSocket, frame keyframe/delta, keys, audio events, JV1 to DMK mount and download, a read and a write request of the IO controller |
| `host/web/index.html` in the Browser pane against `cp300d.py --sim` | the page connects, draws at 60 fps, a key press shows in the picture |

## How it is built

```
Browser (canvas, WebAudio, keyboard, drag and drop)
   |  WebSocket (frames: zlib of the XOR with the previous one; audio edges; keys)   HTTP PUT/GET (disks, ROMs)
cp300d.py on the board  (stdlib Python, one asyncio loop)
   |  mmap of the FIC window (/dev/uio0 or /dev/mem), 32 bit accesses
AXI4-Lite -> axil_regbus.v (CDC) -> bvf_regs.v -> bvf_fb (frame RAM), bvf_dataslot (disk mailbox + track RAM),
                                                   bvf_audio (edge FIFO), keys, ROM loader
                                   -> CP-300 core + IO controller of the Analogue Pocket port, unchanged
```

The gateware reuses the Pocket port's core wrapper (`ht1080z_ext`), the helper Z80 and its firmware (`io_ctrl_pocket`, `firmware/pocket`: it serves the WD1793's sector requests out of DMK images, a whole track at a time) and the run-time ROM loader. `bvf_dataslot.v` is `apf_dataslot.vhd` with the Analogue framework replaced by registers the daemon writes. Everything in `rtl/` is plain inferred Verilog, no vendor megafunctions.

## Files

| Path | |
|---|---|
| `rtl/bvf_core.v` | top: bus, core, IO controller, frame, audio, registers. Ports: 42 MHz clock, AXI4-Lite slave, `irq` |
| `rtl/bvf_regs.v` | the register map (header of the file) |
| `rtl/axil_regbus.v` | AXI4-Lite slave to the core clock domain |
| `rtl/bvf_fb.v` | 512 x 192 x 1 bit frame capture, two buffers, frame counter |
| `rtl/bvf_dataslot.v`, `bvf_trk_ram.v` | disk request handshake, slot table, 16 KB track RAM |
| `rtl/bvf_audio.v` | speaker level changes with microsecond stamps, 256 entry FIFO |
| `sim/` | `tb_bvf.v`, `run.sh` |
| `host/cp300d.py` | the daemon (`--uio`, `--mem`, `--sim`) |
| `host/web/index.html` | the page |
| `host/test_cp300d.py` | daemon test |

Files taken from other places and not copied here: `../analogue/src/fpga/core/{ht1080z_ext,io_ctrl_pocket,io_fw_pkg,cp300_roms_stub}.vhd`, `rtl/` of the repository root (`ht1080z`, `wd1793`, `T80`, `cp300_rom`), `tools/dsk2dmk.py`.

## Trying the page without a board

```
cd syn/beaglev-fire/host
python3 cp300d.py --sim --port 8300        # then open http://localhost:8300/
```

The simulated picture shows a frame, a moving bar and a block for every key held. ROMs are not needed in `--sim`.

## On the board (not done yet, see HANDOVER.md)

```
python3 cp300d.py --uio /dev/uio0          # or --mem 0x60000000
```

Open `http://<board>:8300/`, load the two ROMs once (they are stored in `host/data/` on the board, never in the bitstream), drop DMK/DSK/HFE/JV1/JV3 images on a drive, click the screen and type.

The page is plain static files. If the board's own web server should be the front door it can link to or reverse-proxy port 8300; the live channel needs a process that can hold a WebSocket, which a file-serving server cannot.

Disk images that are changed by the CP-300 are written back to `host/data/driveN.dmk` every 2 seconds and can be downloaded as DMK.

## Notes on the keyboard

The browser maps characters, not physical keys: letters are always the capitals the CP-300 prints, `!"#$%&'()*+<=>?` press the CP-300's shifted digit keys, Esc = BREAK, Backspace and Left = left arrow, Home = CLEAR. The on-screen keyboard works by touch.
