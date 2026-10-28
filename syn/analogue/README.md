# CP-300 for the Analogue Pocket

The CP-300 core of this repository on the **Analogue Pocket** (Cyclone V 5CEBA4F23C8, openFPGA / APF), with an **on-screen keyboard** and **audio**.

> **Status: runs on a real Analogue Pocket** (checked by the author): the ROM boots and a DOS boots from a disk image loaded from the Core Settings menu. The newest SD-card speed optimisations (whole-track reads, see [Known limits](#known-limits-and-risks)) are **not yet re-tested on hardware**. What was checked in simulation is listed under [Verification](#verification).

| | |
|---|---|
| Video | the core's own 512 x 192 picture at 10.5 MHz / 59.4 Hz, scaled by the Pocket; three aspect modes, three phosphor colours |
| Audio | 48 kHz 16 bit I2S, mono: the cassette port speaker bit, with volume and on/off in the core settings |
| Keyboard | on-screen keyboard (Select), buttons as keys when it is hidden |
| Disks | four WD1793 drives, **DMK** images (`.dsk` / `.dmk`) loaded from the Core Settings menu, read and write |
| Not here | cassette, hard disk, RS-232, PS/2 and the original keyboard matrix (those are the DE0/Tang boards' features), save states, docked USB keyboard |

## Using it

### First start

1. Build the core ([Building](#building)) and run `python package.py`. Copy `dist-sd/Cores/` and `dist-sd/Platforms/` to the root of the Pocket's SD card.
2. Put the **CP-300 ROMs** and your disk images in `Assets/cp300/common/` on the card. The ROMs are not in the core (see [ROMs](#roms)): `27C128cp300.BIN` (16 KB system ROM) and `2716cp300.BIN` (2 KB character generator). Disk images are `.dsk` / `.dmk` files in DMK format.
3. Start **CP-300** from the Pocket's core list. If a ROM file is missing the Pocket opens its file browser for it; pick the file once and it is remembered. With no disk selected the CP-300 ROM shows its `Cass?` prompt: answer **A** for BASIC (the ROM takes A/B, not L/H), then ENTER at `Mem. usada?` (open the keyboard with Select to type).
4. To boot a disk: Analogue button, **Core Settings**, **Drive 0 (boot)**, pick the file, then **Reset CP-300**. The Pocket remembers the choice for the next start.
5. At `TRSDOS Ready` (TRSDOS 1.3) type `BASIC`, press ENTER at `How many files?` and `Memory size?`, then `RUN"NAME/BAS"` (add `:1` for a file on Drive 1).

**Disks.** The four drives are data slots, shown in the **Core Settings** menu as *Drive 0 (boot)* to *Drive 3*: pick a `.dsk` or `.dmk` file (DMK format; `tools/dsk2dmk.py` in the repository root converts JV1/JV3/HFE) and choose **Reset CP-300**, and the ROM boots it. With no disk in Drive 0 the ROM goes to `Cass?`; the Pocket remembers the file in a slot, so to get back to `Cass?` turn on *Eject all disks* and choose **Reset CP-300**. The Pocket remembers the file you picked and loads the same one at the next start; the core is held in reset until the slots have been read, so a remembered disk is there when the ROM first looks. A file chosen while the core runs swaps the floppy like a real drive. Changes the DOS makes to a disk are written back to the file on the SD card (turn on *Write protect disks* to prevent that).

**On-screen keyboard.** *Select* opens it over the lower 128 lines of the picture (the CP-300 keeps running above it) and closes it.

| Button | Keyboard open | Keyboard closed (if "Buttons are keys" is on) |
|---|---|---|
| D-pad | move the cursor over the keys (auto-repeat) | UP / DOWN / LEFT / RIGHT keys |
| A | press the key under the cursor while held; on a SHIFT key it latches SHIFT | SPACE |
| B | latch SHIFT for the next key (the legends change to the shifted ones) | ENTER |
| X / Y | SPACE / ENTER | BREAK / CLEAR |
| L / R | BREAK / CLEAR | SHIFT / - |
| Start | move the keyboard between the bottom and the top of the picture | - |
| Select | close | open |

The keyboard is the CP-300's own 8 x 8 matrix (the table in the repository README): letters, digits, `: ; , - . / @`, ENTER, CLEAR, BREAK, the four arrows, SPACE and both SHIFTs. SHIFT + digit and the other shifted symbols work through the latch, as on the real keyboard.

**Core Settings** (Analogue button, then Core Settings):

| Setting | Values | What it does |
|---|---|---|
| Drive 0 (boot) .. Drive 3 | file browser | the disk image in that drive |
| Phosphor | White / Green / Amber | colour of the text |
| Turbo CPU | off / on | Z80 at about 4 MHz instead of 2.0 MHz |
| Sound | on / off | the cassette-port speaker |
| Volume | Low / Medium / High / Max | |
| Buttons are keys | on / off | d-pad and buttons type keys while the keyboard is hidden |
| Write protect disks | on / off | the DOS cannot change the disk files |
| Eject all disks | on / off | all four drives read as empty, so the ROM boots to `Cass?`; not remembered, off at every start |
| Reset CP-300 | action | reset the machine (needed after choosing a new boot disk) |
| Disk status | read only, hex | bit 7 = IO controller running, bits 3:0 = drives holding a usable DMK |

The Pocket's *Display Mode* menu offers the scaler modes: 4:3 (default, tall pixels), 5:3 and square pixels. Cassette (`Cass?` loading from tape) is not available; software comes from disks.

**Troubleshooting.** Disk status shows 0 for a drive: the file is not a DMK with 256-byte sectors (convert with `tools/dsk2dmk.py`). `Diskette?` or a hang at boot: choose the file again and Reset CP-300. Disk errors under load: see *Disk speed* in the known limits.

### Machines

The machine is whatever system ROM is in the *System ROM* slot. Open the Pocket's **Core Settings** menu, choose *System ROM (16 KB)* (and *Character ROM (2 KB)* if the machine needs its own), pick the file, then choose **Reset CP-300**. (Both slots are user-reloadable, like the four drives.) For example, pick `CP500.ROM` (or the CP-500 P24 / Turbo `27c128.BIN`, or a 14 KB TRS-80 Model III ROM) instead of the CP-300's `27C128cp300.BIN` in *Core Settings*, then choose **Reset CP-300**. The character generator (*Character ROM*, `2716cp300.BIN`) is the same on all of them; for a machine with other glyphs pick its own file there too. Names to keep in `Assets/cp300/common/`:

| Machine | System ROM, source file | Character generator |
|---|---|---|
| CP-300 | `27C128cp300.BIN` | `2716cp300.BIN` |
| CP-500 | `cp500.rom` (also `CP500M80_27128.bin`) | `2716cp300.BIN` |
| CP-500 P24 / Turbo | `27c128.BIN` / `CP-500 Turbo 27128.Bin` (same file) | `2716cp300.BIN` |
| TRS-80 Model III (14 KB, 0000-37FF) | `TRS80M3.ROM` | its own `.rom` / `.bin` if its glyphs differ |

(The Pocket takes any file name, because you pick the file; DE0 and Tang names are `NAME.ROM` / `NAME.CHR`.) This is the same model as the DE0 (`MACHINE` menu item, see the top-level README); the BASIC ROM is identical code, only the upper 2 KB differs and is not reachable by the CPU.

### ROMs

The ROM set widely shared for the CP-300 (`roms_cp300.zip`: `27C128cp300.BIN` and `2716cp300.BIN`) works **as it is**: unzip it into `Assets/cp300/common/`, no conversion. (Checked: the two files are byte-identical to the 900-61..64 dumps in a row and to 900-65.)

The bitstream contains no CP-300 ROM, so the core can be published; each user supplies the ROMs, which are loaded into the core's ROM RAMs when it starts:

| File (in `Assets/cp300/common/`) | Size | Content |
|---|---|---|
| `27C128cp300.BIN` | 16384 bytes | the system ROM, address 0000-3FFF: `900-61`..`900-64` one after the other (2732s, 4 KB each), or the 27C128 of later boards |
| `2716cp300.BIN` | 2048 bytes | the character generator `900-65` (2716) |

If you have the four EPROM dumps in `roms/` (see `roms/README.md`), `python tools/mkpocketrom.py` writes both files; for a 27C128 dump use `python tools/mkpocketrom.py outdir --27c128 27C128cp300.BIN 900-65.BIN`. In *Core Settings* the two files appear as *System ROM* and *Character ROM*; the Pocket remembers the choice. Without a system ROM the screen stays black.

## How it works

```
                +-------------------------------------------------------------+
 Pocket (APF)   | core_top.v                                                  |
  bridge  ------+--> core_bridge_cmd (framework commands, slot size table)     |
  74.25 MHz     |--> apf_dataslot.vhd  data slot read/write of 512 byte blocks |
                |        ^  |                                                  |
                |        |  v        42 MHz                                   |
                |   io_ctrl_pocket.vhd (helper Z80 + firmware/pocket, DMK)     |
                |        |                                                     |
                |   ht1080z.vhd + wd1793.vhd + RAM ROMs   (the CP-300, shared) |
                |        |  picture / keys / audio                             |
                |   osd_kbd.v --> picture overlay + key matrix                 |
 video, audio <-+--  video registers (clk_vid 10.5 MHz), sound_i2s.sv          |
                +-------------------------------------------------------------+
```

* **Core and clocks.** The same `ht1080z` / `videoctrl` / `wd1793` / T80 / CP-300 ROM files as the DE0 and Tang builds (`rtl/`), at the same 42 MHz (Z80 = 42 / 21 = 2.0 MHz; turbo 4.0). One PLL (`mf_pllbase_0002.v`, hand-edited `altera_pll` parameters) makes 42 MHz, the 10.5 MHz pixel clock and its 90 degree copy from the Pocket's 74.25 MHz; the PLL IP can be regenerated in Quartus's IP editor with the same frequencies.
* **RAM.** The 48 KB of Z80 RAM is a 64 KB block RAM (`ram64` in `core_top.v`): no SDRAM, no waits.
* **ROMs.** `cp300_rom` and `videoctrl` (shared with the other boards) have a `RUNTIME_ROM` generic: the system ROM and the character generator are then RAMs, written through an `rl_*` word port. `core_top.v` feeds it from the bridge: data slots 4 (system ROM, `50000000h`) and 5 (character generator, `50004000h`) are loaded by the framework before the core starts, so the four bytes of each bridge write go straight into byte-lane RAMs (written with `clk_74a`, read with the 42 MHz clock). `osd_font.vhd` keeps its own copy of the character generator from the same writes. The Pocket project compiles the shared files against an empty `cp300_roms_stub.vhd`, so no ROM content is in the project or the bitstream; `sim/run_rtrom.sh` shows the RAM version is bit-identical to the ROM version.
* **Disks.** The DE0 build has a helper Z80 that reads DMK files from a FAT SD card. Here the card is the Pocket's, so the helper Z80 keeps its DMK code (`firmware/dmk.c`, shared) but reads and writes **data slots** through the APF target commands (`0180` data slot read, `0184` data slot write): one 512 byte block per command, through the bridge ranges `20000000h` (blocks read) and `30000000h` (blocks written). `apf_dataslot.vhd` also scans the framework's slot size table and watches the "data slot update" event, so the firmware knows which drives hold a file and when one is swapped. The four slots are `deferload` and user-reloadable (`data.json`), so the framework never copies a disk anywhere. Firmware: `firmware/pocket` (`build.sh`, SDCC 4.6, writes `core/io_fw_pkg.vhd`). Its I/O port map is the header of `io_ctrl_pocket.vhd`.
* **Video.** The core's raw picture (`vid_screen`, `vid_ink`, `vid_pxen`) is used directly: 512 x 192 active pixels, 10.5 MHz, 262 lines (59.4 Hz). `core_top.v` counts the pixels, lets `osd_kbd` colour them, then hands the held values to `clk_vid`, which the framework samples. VS/HS are single-clock pulses made from the core's sync, DE is the 512 x 192 area, the rest is black. Three scaler modes in `video.json` (4:3, 5:3 and square pixels).
* **On-screen keyboard.** `osd_kbd.v`. The layout, key matrix numbers and the cursor navigation tables are generated by `tools/mkoskbd.py` into `osd_kbd_text.hex`, `_cells.hex` and `_nav.hex` (ROMs read with `$readmemh`); the glyphs come from the CP-300 character generator through `osd_font.vhd`. Keys go to the CP-300 as the same `ext_keys` matrix the DE0 build feeds from its GPIO keyboard.
* **Audio.** The core's cassette-port speaker (three levels on port FF) is centred, scaled and sent through `sound_i2s.sv` (agg23's APF I2S block, MIT) as mono 16 bit at 48 kHz.
* **Settings.** `interact.json` registers at bridge `40000000h..` (`core_top.v`), written by the framework (persistent ones at boot) and crossed into the 42 MHz domain through 3-flop synchronisers.

Bridge map: `2xxxxxxx` receive buffer (write), `3xxxxxxx` transmit buffer (read), `4xxxxxxx` settings, `F8xxxxxx` framework. The bridge is big endian (`bridge_endian_little = 0`): the first byte of a word is bits 31:24.

## Building

Needs **Quartus Prime Lite 18.1 or newer** (the framework template was made with 18.1.1), no ROM files (they are loaded from the SD card at run time) and, only if you change the firmware, SDCC 4.6.

```
firmware/pocket/build.sh                       # only after changing firmware/ (io_fw_pkg.vhd is committed)
python tools/mkoskbd.py                        # only after changing the keyboard layout
# Quartus Prime: open syn/analogue/src/fpga/ap_core.qpf and compile, or
#   cd syn/analogue/src/fpga && quartus_sh --flow compile ap_core
python syn/analogue/package.py                 # -> syn/analogue/dist-sd/{Cores,Platforms}
```

The bitstream contains no ROM, so the `.rbf_r` and the packaged core can be published. Never publish the ROM files themselves (copyrighted).

`icon.bin` and `Platforms/_images/cp300.bin` are the framework template's placeholders; make real ones from PNGs with Pocket Sync or the Analogue image tools (36 x 36 icon, 521 x 165 platform picture).

## Verification

Done (all on Windows, GHDL 6, iverilog 12):

* `firmware/pocket/build.sh`: the firmware builds with SDCC 4.6 (5.1 KB of 16 KB).
* `sim/run_slot.sh`: **GHDL**, the real firmware on `io_ctrl_pocket` + `apf_dataslot` against a behavioural APF host (target commands, 128-word bridge bursts every 9 clocks, slot size table, update event) and a floppy controller played by the bench: the firmware waits for the table, mounts drive 0 from slot 0 and releases the CP-300; sector reads from a 35 track DMK are bit-exact; a missing sector is reported; a sector write goes back to the host image and reads back with a good CRC; ID field read; eject and re-insert show up as unmount / remount. It takes about half an hour (the T80 runs the firmware's CRC code).
* `sim/run_osd.sh`: **iverilog**, `osd_kbd.v` with the real character generator: navigation, key matrix output, SHIFT latch (B and A on a SHIFT key), quick keys, open/close; renders the keyboard to `sim/out/osd_<n>.png`.
* `sim/run_rtrom.sh`: **GHDL**, `cp300_rom` and `videoctrl` with `RUNTIME_ROM` loaded through the word port against the same entities built from the ROM package (needs `roms/cp300_roms_pkg.vhd`): every one of the 16384 system ROM addresses, and a frame of picture with text in video RAM with and without the kana set, bit for bit.
* `sim/run_video.sh`: **iverilog**, `pocket_video.v` fed with the timing of `videoctrl.vhd` (672 x 263 at 10.5 MHz, 512 x 192 picture): one VS and HS pulse per frame / line, VS to HS 8 clocks, HS to DE 128, DE exactly over the picture, pixel values right, black elsewhere.
* `sim/lint.sh`: **iverilog** elaboration of `core_top.v` with the VHDL entities stubbed: port names and widths and declaration order of the glue.
* `package.py` on a dummy bitstream.

Not done: any Quartus Prime compile (synthesis, fitting, timing), the PLL with those frequencies, the video timing against the Pocket scaler, the APF data slot commands against a real Pocket, the CP-300 booting a disk in this wrapper (the core files are the ones the DE0 and Tang builds boot with; only their surroundings are new), audio on the speakers.

## Known limits and risks

* **Newest SD-card speed work not re-tested on hardware.** The whole-track reads and the other SD-card speed optimisations were added after the last test on a real Pocket.
* **Disk speed.** Every DMK block fetch is an APF command round trip, and the firmware's CRC code on a 21 MHz Z80 takes about 2 ms per sector. The WD1793 wait-state timeout is 100 ms, so slow commands would show as disk errors; if they do, a bigger block cache in `firmware/dmk.c` (a whole track) is the fix.
* **Only DMK, 256-byte sectors**, like the other boards. No formatting.
* **Docked keyboard** (USB HID scan codes on `cont3_*`) is not decoded; the buttons and the on-screen keyboard are the input.
* **Display modes.** The Pocket's LCD "original" display modes need grayscale handling that this core does not implement; only the CRT Trinitron mode is offered.
* **APF licence.** `src/fpga/apf` and `core_bridge_cmd.v` are Analogue's framework files, from the open-fpga core template (their own licence/EULA applies); `sound_i2s.sv` and `sync_fifo.sv` are Adam Gastineau's (MIT, `analogue-pocket-utils`).
