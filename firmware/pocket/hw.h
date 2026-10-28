/* IO controller hardware of the Analogue Pocket core (syn/analogue/src/fpga/core/io_ctrl_pocket.vhd) */
#ifndef POCKET_HW_H
#define POCKET_HW_H

#include <stdint.h>

__sfr __at(0x04) CTRL;        /* w: b1 hold the CP-300 in reset */
__sfr __at(0x07) ID;          /* r: A6 */
__sfr __at(0x08) DBG;         /* w: status byte, shown by the interact menu */
__sfr __at(0x10) FDC_REQ;     /* r: b0 read sector, b1 write sector, b2 read address, b3 side, b5:4 drive, b6 deleted mark */
__sfr __at(0x11) FDC_TRK;     /* r: head position */
__sfr __at(0x12) FDC_TRKREG;  /* r: track register */
__sfr __at(0x16) FDC_RES;     /* w: b0 found, b1 CRC error, b2 deleted mark */
__sfr __at(0x17) FDC_SEC;     /* r: sector number */
__sfr __at(0x13) FDC_ACK;     /* w: b0 = servicing a request, buffer port live */
__sfr __at(0x14) FDC_BUF;     /* rw: sector buffer, auto-increment */
__sfr __at(0x15) DRV_FLAGS;   /* w: b1:0 drive, b2 present, b3 write protected */

__sfr __at(0x20) SLOT_OFF0;   /* w: byte offset in the slot file, least significant byte first */
__sfr __at(0x21) SLOT_OFF1;
__sfr __at(0x22) SLOT_OFF2;
__sfr __at(0x23) SLOT_OFF3;
__sfr __at(0x24) SLOT_NUM;    /* w: slot (drive) */
__sfr __at(0x25) SLOT_CMD;    /* w: 1 read the file into the track RAM, 2 write the track RAM to the file;  r: b0 busy, b1 error */
__sfr __at(0x2C) SLOT_LENL;   /* w: bytes to move (at most 16384) */
__sfr __at(0x2D) SLOT_LENH;
__sfr __at(0x2E) SLOT_BOFF0;  /* w: where in the track RAM (offset from 8000h) */
__sfr __at(0x2F) SLOT_BOFF1;
__sfr __at(0x30) SLOT_SIZE0;  /* r: size of the file in the slot of SLOT_NUM */
__sfr __at(0x31) SLOT_SIZE1;
__sfr __at(0x32) SLOT_SIZE2;
__sfr __at(0x33) SLOT_SIZE3;
__sfr __at(0x29) SLOT_PRES;   /* r: b3:0 slot has a file */
__sfr __at(0x2A) SLOT_CHG;    /* r: b3:0 file replaced;  w: clear those bits */
__sfr __at(0x2B) SLOT_OPT;    /* r: b0 write protect all disks, b2 eject all disks, b7 slot table scanned */

#define OPT_WP        0x01
#define OPT_EJECT     0x04
#define OPT_SCANNED   0x80
#define CTRL_RESET    0x02

#endif
