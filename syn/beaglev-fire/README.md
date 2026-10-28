# CP-300 on the BeagleV-Fire

An FPGA recreation of the **Prológica CP-300** (the Brazilian TRS-80 Model III compatible, 1983) on the
[BeagleV-Fire](https://www.beagleboard.org/boards/beaglev-fire): a RISC-V Linux board with a Microchip PolarFire SoC
(MPFS025T) and about 23K logic elements of FPGA fabric. Part of the [CP-300 FPGA](../../README.md) project.

The board has no video output and no keyboard port for the FPGA, so **the browser is the monitor, keyboard, speaker and
disk drive**. The CP-300 runs in the fabric; a small Python daemon on the board's Linux moves the picture, the key presses,
the sound and the disk data between the fabric and a web page.

```
 browser:  screen (canvas) · keyboard · sound (WebAudio) · drag-and-drop disks
    │  HTTP + WebSocket
 nginx (port 80)  ──►  cp300d.py (Linux, port 8300)
                              │  32-bit register window, /dev/uio0
 FPGA fabric:  APB bridge ─► registers, frame capture, disk mailbox, audio FIFO ─► CP-300 core
```

It runs the original CP-300 ROM and boots TRS-80 Model III disk systems (TRSDOS 1.3 tested) from disk images that you
drop on a drive in the page.

> **Status: works on the author's board** (BeagleV-Fire, Ubuntu 24.04 image of 2025-07-21, kernel 6.6.75, stock gateware
> 2025.10-13). Screen, keyboard, sound, disk boot and a game were checked in a browser. See [Limitations](#limitations).

## DISCLAIMER: you can brick your board

**Installing the CP-300 gateware flashes the board**: the FPGA bitstream, the device tree overlay and the Hart Software Services
bootloader are rewritten, and the board's own update mechanism keeps no fallback copy. A failed or interrupted flash, a power
loss, a defect or incompatibility in this software, or a board or software version other than the one it was tried on can leave
the BeagleV-Fire **unable to start**. Recovering it may need a FlashPro5/6 programmer and may not be possible at all.

This software and gateware are provided **"as is", without warranty of any kind**. The author and contributors accept **no
responsibility or liability** for any damage to your board or other equipment, loss of data, or any other loss. **You use it
entirely at your own risk.** This adds to the warranty disclaimer of the GPL-3.0 under which it is released. The package
contains the full text (`DISCLAIMER.txt`), and its installer asks you to type `I ACCEPT` before it flashes. This is an
independent hobby project, not made or endorsed by Microchip, BeagleBoard.org, Prológica or Tandy.

## What you need

- A **BeagleV-Fire** running the BeagleBoard.org Ubuntu image, on your network, with SSH access and `sudo`.
- The two **ROM images** of the machine. They are copyrighted and **not included**: the system ROM, 16384 bytes
  (`27C128cp300.BIN` for the CP-300), and the character generator, 2048 bytes (`2716cp300.BIN`; the CP-500 / shared
  `CHARGEN.BIN` works too). See [../../roms/README.md](../../roms/README.md).
- Disk images (`.dsk`, `.dmk`, `.hfe`, `.jv1`, `.jv3`) of the software you want to run.
- **A way back if the flash fails**: a FlashPro5/6 programmer is the documented recovery
  ([BeagleBoard flashing guide](https://docs.beagleboard.org/boards/beaglev/fire/demos-and-tutorials/flashing-board.html)).

## Install

The package is in [`releases/`](releases): `cp300-beaglev-fire-<version>.tar.gz` and its `.sha256`. Copy it to the board and run:

```bash
sha256sum -c cp300-beaglev-fire-<version>.tar.gz.sha256
tar xzf cp300-beaglev-fire-<version>.tar.gz
cd cp300-beaglev-fire-<version>
sudo ./install.sh
```

The installer

1. puts the software in `/opt/cp300` and starts it at boot (service `cp300d`),
2. adds the CP-300 to the stock web server (`http://<board>/cp300/`) and to **Cockpit** (sidebar, *Tools → CP-300*),
3. shows the disclaimer, asks you to type `I ACCEPT`, and **flashes the CP-300 gateware**, then the board reboots.
   The FPGA is reprogrammed while the board starts: it takes a couple of minutes, **do not power it off before it is back**.

If the CP-300 gateware is already the loaded one it does not flash again. Options: `--yes` (do not ask; you accept the
disclaimer), `--no-flash` (software only), `--no-web` (gateware only), `--force-flash`, `--check` (report only),
`--uninstall` (`--purge` also deletes disks and ROMs). The README inside the package has the details.

## Use

Open `http://<board>/cp300/`.

1. **First time:** choose the two ROM files in the *ROMs* panel. They are kept on the board.
2. **Disks:** drop an image on a drive (or *Choose file*). Drive 0 is the boot drive. Changes made by the CP-300 are written
   back to the image on the board every two seconds; *Download* gives the image as DMK.
   The two **FreeHD hard disks** (version 0.4.0) are cards under the drives: drop an `.hdv` image on one (the daemon calls
   `PUT /api/hd/0` and `/api/hd/1`); the image is used as it is and *Download* gives it back. The FreeHD ports (`C0`-`CF`)
   answer only while an image is mounted. **Needs the gateware of 0.4.0**: the package 0.3.0 has no hard disk;
   the sources (`rtl/bvf_regs.v`, `bvf_dataslot.v`) are changed and pass the simulation, but the bitstream was not rebuilt.
3. Click the screen and type. **Esc** = BREAK, **Backspace** and **Left** = left arrow, **Home** = CLEAR. The browser maps
   characters, not physical keys (`"` presses the CP-300's shifted 2). An on-screen keyboard is below the screen.
4. **Sound** needs one click on the *Sound* button (browsers refuse audio before that). **Reset**, **Turbo** and
   **Write-protect disks** are buttons above the drives.

The picture is the machine's 512 × 192 monochrome output, shown on a 4:3 screen as on the real tube; the colour (green,
amber, white) is a setting.

## Another gateware, and back

The CP-300 gateware replaces the one in the board's flash. Flashing any other (for example the stock one,
`sudo /usr/share/beagleboard/gateware/change-gateware.sh default`) replaces it again. The software and the Cockpit entry stay
and wait: the service starts only when the CP-300 gateware is loaded. To use the CP-300 again run the installer once more, or only:

```bash
sudo cp300-load-gateware
```

## Troubleshooting

| Symptom | Check |
|---|---|
| The screen is black, the machine is stopped | The ROMs are missing: upload them in the *ROMs* panel. |
| Cockpit says *Gateware: …not loaded* | Another gateware is loaded: `sudo cp300-load-gateware`. |
| Cockpit says *Daemon: not running* | `systemctl status cp300d` and `journalctl -u cp300d`. The service starts only if `/sys/class/uio/uio0/name` is `cp300`. |
| No sound | Click *Sound* first. |
| Choppy picture | The page shows its frame rate (about 40 fps; the hardware runs at 60). |
| What is the hardware doing? | `curl http://localhost:8300/api/debug` on the board: registers and bus timing. |
| `./install.sh --check` | Shows the installed version, the loaded gateware and the daemon state; changes nothing. |

## How it works

- **Gateware** (`rtl/`, plain inferred Verilog): an APB3 slave on the framework's cape bus (window at `0x41000000`, 1 MB)
  bridges to the core's 42 MHz clock (a PLL fed from the 50 MHz fabric clock). Behind it: `bvf_regs` (control, keys, ROM loader,
  slot table), `bvf_fb` (frame capture, two buffers), `bvf_dataslot` (disk request handshake and 16 KB track RAM) and
  `bvf_audio` (speaker level changes with microsecond stamps). The CP-300 core (`ht1080z_ext`, T80, WD1793) and the helper Z80
  that serves disk requests out of DMK images (`io_ctrl_pocket`, firmware in [`../../firmware/pocket`](../../firmware/pocket))
  are the ones of the [Analogue Pocket port](../analogue), unchanged.
- **Daemon** (`host/cp300d.py`, standard-library Python): maps the window through `/dev/uio0`, serves the page and a WebSocket
  (frames as zlib of the XOR with the previous frame, audio edges, keys) and stores disks and ROMs in `/var/lib/cp300`. A disk
  request of the gateware wakes it through the UIO interrupt (PLIC 126); with a gateware that has none it polls.
- **Register access** (`host/regs32.c`, built with `gcc` on the board): the window is a 32-bit APB bus without byte strobes, and
  Python's `memcpy`-based access stores one byte at a time on this board, which corrupts the words. Every access is a real
  32-bit load or store.
- **The CP-300 cape** (`gateware/`): `make_cape.py` adds a `CP300` option to the
  [BeagleV-Fire gateware framework](https://git.beagleboard.org/beaglev-fire/gateware), together with the device tree overlay
  that creates `/dev/uio0` (name `cp300`).

Resources on the MPFS025T with the framework: 17,890 of 22,956 4-input LUTs (78%), 18,952 logic elements (83%), 74 of 84 large
block RAMs (88%), timing met. There is little room left for additions.

## Building the package yourself

The gateware is built outside this repository with Libero SoC, the framework's scripts and a bootloader built with SoftConsole;
the steps and the pitfalls found are in [BUILDING.md](BUILDING.md). How the design works and why it was done this way (interface, frame capture, audio, disk mailbox, web protocol) is in the
[technical paper](../../docs/beaglev-fire-technical-paper.md). `package/build_package.py` then assembles the package.
Simulation: `sim/run.sh` and `sim/run_apb.sh` (Icarus Verilog) and `host/test_cp300d.py`.

## Repository layout

| Path | |
|---|---|
| `rtl/` | the gateware around the core: `bvf_core_apb.v` (top), `bvf_core_bus.v`, `apb_regbus.v`, `bvf_regs.v`, `bvf_fb.v`, `bvf_dataslot.v`, `bvf_trk_ram.v`, `bvf_audio.v` (`bvf_core.v` / `axil_regbus.v`: the AXI4-Lite variant used in simulation) |
| `gateware/` | `make_cape.py`, the cape's device tree overlay (`CAPE/CP300/cp300.dtso`) |
| `host/` | `cp300d.py`, `regs32.c`, `web/index.html`, `deploy/` (service, web server snippet, Cockpit entry), `test_cp300d.py` |
| `package/` | `build_package.py`, `install.sh`, `cp300-load-gateware`, the README and the DISCLAIMER inside the package |
| `releases/` | the built packages |
| `sim/` | testbenches |

## Limitations

- **Flashing has no fallback** (see the disclaimer). The gateware was built with Libero SoC 2026.1, which the BeagleV-Fire
  framework does not officially support (it lists up to 2025.2), and a bootloader built on a PC. It works on the author's
  board; yours may differ.
- Tested on one board and one stock gateware version (`2025.10-13-g943f37f`). Other versions of the board's image may need
  the gateware rebuilt on a matching framework version.
- Monochrome picture; no cassette, no hard disk, no RS-232.
- The frame rate in the page is about 40 fps (the daemon's Python on the board's cores is the limit).
- The design fills 83% of the logic and 88% of the block RAM.
- The installer's flash-and-reboot path and the "another gateware, and back" sequence are not yet tested on a board.

## Licence and credits

GPL-3.0, see [../../LICENSE](../../LICENSE). Third-party parts keep their own licences (full list in the
[main README](../../README.md#licence-and-credits)): the HT1080Z core (Jozsef Laszlo), T80, the WD1793 (Slavinsky, Sorgelig, Stan
Hodge), the BeagleV-Fire gateware framework (MIT, Microchip and BeagleBoard.org) and the Microchip Hart Software Services
bootloader. **ROMs and disk images are not part of this project.**
