#!/usr/bin/env python3
"""Layout of the on-screen keyboard of the Analogue Pocket core (osd_kbd.v).

    python tools/mkoskbd.py [outdir]        writes osd_kbd_text.hex, osd_kbd_cells.hex, osd_kbd_nav.hex
                                            (default: syn/analogue/src/fpga/core)
    python tools/mkoskbd.py --show          prints the keyboard as text

The keyboard is a grid of 16 x 5 cells of 4 x 3 characters, under a header line: 64 x 16 characters,
8 x 8 pixels each, 512 x 128 pixels on the 512 x 192 picture. Every key is one or more cells. The
hex files are the ROMs of osd_kbd.v:

  osd_kbd_text.hex   2 x 1024 bytes, ASCII: plane 0 = the keyboard as it is, plane 1 = what the keys show
                     while SHIFT is latched; index = {plane, row (0..15), column (0..63)}
  osd_kbd_cells.hex  128 bytes, index = row * 16 + column of a cell: bit 7 = a key is here, bits 5:0 = its
                     position in the keyboard matrix of the CP-300 (8 * row + column of the README table)
  osd_kbd_nav.hex    128 words of 28 bits, index = cell: {down, up, right, left} (7 bit cell numbers) the
                     cursor goes to on that d-pad direction

The CP-300 keyboard matrix (row = address line A0-A7, column = data bit):
  A0 @ A B C D E F G     A1 H I J K L M N O     A2 P Q R S T U V W     A3 X Y Z
  A4 0 1 2 3 4 5 6 7     A5 8 9 : ; , - . /      A6 ENTER CLEAR BREAK UP DOWN LEFT RIGHT SPACE
  A7 L-SHIFT R-SHIFT
"""
import os
import sys

COLS, ROWS = 16, 5          # cells
TW, TH = 4, 3               # characters per cell

M = {}
for r, names in enumerate(["@ABCDEFG", "HIJKLMNO", "PQRSTUVW", "XYZ", "01234567", "89:;,-./"]):
    for c, ch in enumerate(names):
        M[ch] = 8 * ([0, 1, 2, 3, 4, 5][r]) + c
M.update({"ENTER": 48, "CLEAR": 49, "BREAK": 50, "UP": 51, "DOWN": 52, "LEFT": 53, "RIGHT": 54, "SPACE": 55,
          "LSHIFT": 56, "RSHIFT": 57})

# what SHIFT + key types on the TRS-80 Model III keyboard
SHIFTED = {"1": "!", "2": '"', "3": "#", "4": "$", "5": "%", "6": "&", "7": "'", "8": "(", "9": ")",
           ":": "*", ";": "+", ",": "<", "-": "=", ".": ">", "/": "?"}

# (label, width in cells, matrix key); None = a gap of one cell
LAYOUT = [
    [("1", 1), ("2", 1), ("3", 1), ("4", 1), ("5", 1), ("6", 1), ("7", 1), ("8", 1), ("9", 1), ("0", 1),
     (":", 1), ("-", 1), ("BREAK", 2), ("CLEAR", 2)],
    [("Q", 1), ("W", 1), ("E", 1), ("R", 1), ("T", 1), ("Y", 1), ("U", 1), ("I", 1), ("O", 1), ("P", 1),
     ("@", 1), ("ENTER", 5)],
    [("A", 1), ("S", 1), ("D", 1), ("F", 1), ("G", 1), ("H", 1), ("J", 1), ("K", 1), ("L", 1), (";", 1),
     None, None, ("LEFT", 1), ("DOWN", 1), ("UP", 1), ("RIGHT", 1)],
    [("LSHIFT", 2), ("Z", 1), ("X", 1), ("C", 1), ("V", 1), ("B", 1), ("N", 1), ("M", 1), (",", 1), (".", 1),
     ("/", 1), ("RSHIFT", 2)],
    [None, None, None, None, ("SPACE", 8)],
]
CAPTION = {"BREAK": "BREAK", "CLEAR": "CLEAR", "ENTER": "ENTER", "SPACE": "SPACE", "LSHIFT": "SHIFT",
           "RSHIFT": "SHIFT", "UP": "UP", "DOWN": "DN", "LEFT": "<-", "RIGHT": "->"}
HEADER = "A KEY  B SHIFT  X SPC  Y ENT  L BRK  R CLR  START MOVE  SEL HIDE"
START_CELL = 2 * 16 + 0     # the cursor starts on A


def build():
    cells = [None] * 128                     # (matrix, key number)
    text = [[bytearray(b" " * 64) for _ in range(16)] for _ in range(2)]
    hdr = HEADER.ljust(64)
    assert len(HEADER) <= 64, len(HEADER)
    for p in range(2):
        text[p][0][:] = hdr.encode()
    keyno = 0
    for r, row in enumerate(LAYOUT):
        c = 0
        for k in row:
            if k is None:
                c += 1
                continue
            label, w = k
            for i in range(w):
                cells[r * 16 + c + i] = (M[label], keyno)
            for p in range(2):
                x0, y0 = c * TW, 1 + r * TH
                wid = w * TW
                text[p][y0][x0:x0 + wid] = b"+" + b"-" * (wid - 2) + b"+"
                text[p][y0 + 2][x0:x0 + wid] = b"+" + b"-" * (wid - 2) + b"+"
                inner = wid - 2
                if label in CAPTION:
                    cap = CAPTION[label].center(inner)
                elif label in SHIFTED:
                    cap = (SHIFTED[label] + label if p else label + SHIFTED[label]).ljust(inner)
                else:
                    cap = (" " + label)[:inner].ljust(inner)
                text[p][y0 + 1][x0:x0 + wid] = b"|" + cap.encode() + b"|"
            keyno += 1
            c += w
        assert c <= COLS, (r, c)
    return cells, text


def navigation(cells):
    def valid(i):
        return cells[i] is not None

    def key(i):
        return cells[i][1]

    nav = []
    for cell in range(128):
        r, c = divmod(cell, 16)
        if r >= ROWS or not valid(cell):
            nav.append((cell, cell, cell, cell))
            continue
        # left / right: next cell of another key in the row
        def horiz(step):
            cc = c + step
            while 0 <= cc < COLS:
                j = r * 16 + cc
                if valid(j) and key(j) != key(cell):
                    return j
                cc += step
            return cell

        # up / down: the nearest key of the next row that has one
        def vert(step):
            rr = r + step
            while 0 <= rr < ROWS:
                best = None
                for cc in range(COLS):
                    j = rr * 16 + cc
                    if valid(j):
                        d = abs(cc - c)
                        if best is None or d < best[0]:
                            best = (d, j)
                if best:
                    return best[1]
                rr += step
            return cell

        nav.append((horiz(-1), horiz(+1), vert(-1), vert(+1)))     # left, right, up, down
    return nav


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    cells, text = build()
    if "--show" in sys.argv:
        for p in range(2):
            print("plane", p)
            for line in text[p]:
                print(line.decode())
        return
    out = args[0] if args else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "syn", "analogue",
                                            "src", "fpga", "core")
    nav = navigation(cells)
    with open(os.path.join(out, "osd_kbd_text.hex"), "w") as f:
        for p in range(2):
            for line in text[p]:
                for b in line:
                    f.write("%02X\n" % b)
    with open(os.path.join(out, "osd_kbd_cells.hex"), "w") as f:
        for i in range(128):
            f.write("%02X\n" % (0 if cells[i] is None else 0x80 | cells[i][0]))
    with open(os.path.join(out, "osd_kbd_nav.hex"), "w") as f:
        for l, r, u, d in nav:
            f.write("%07X\n" % ((d << 21) | (u << 14) | (r << 7) | l))
    print("start cell", START_CELL, "keys", len({c[1] for c in cells if c}))


if __name__ == "__main__":
    main()
