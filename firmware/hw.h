/* IO controller hardware (rtl/io/io_ctrl.vhd) */
#ifndef HW_H
#define HW_H

#include <stdint.h>

#ifdef HOST_TEST
/* host build: the SD card is an image file, see tests/host_fat.c */
#define SPI_SLOW 0
#else
__sfr __at(0x00) SPI_DATA;   /* r: last byte received   w: send */
__sfr __at(0x01) SPI_CTL;    /* r: b0 busy, b1 SD write protect;  w: b0 SD cs, b1 OSD ss, b2 slow */
__sfr __at(0x02) KBD_STAT;   /* r: b0 byte available */
__sfr __at(0x03) KBD_DATA;   /* r: pop raw PS/2 byte */
__sfr __at(0x04) CTRL;       /* w: b0 menu open, b1 hold core in reset */
__sfr __at(0x05) GLYPH_ROW;  /* r: next pixel column of the selected glyph (OSD byte) */
__sfr __at(0x06) GLYPH_SEL;  /* w: select glyph */
__sfr __at(0x07) ID;         /* r: A5 */
__sfr __at(0x08) DBG;        /* w: debug byte, reported by the simulation */
__sfr __at(0x10) FDC_REQ;    /* r: b0 read sector, b1 write sector, b2 read address, b3 side, b5:4 drive, b6 deleted mark */
__sfr __at(0x11) FDC_TRK;    /* r: head position */
__sfr __at(0x12) FDC_TRKREG; /* r: track register */
__sfr __at(0x16) FDC_RES;    /* w: b0 found, b1 CRC error, b2 deleted mark */
__sfr __at(0x17) FDC_SEC;    /* r: sector number */
__sfr __at(0x13) FDC_ACK;    /* w: b0 = servicing a request, buffer port live */
__sfr __at(0x14) FDC_BUF;    /* rw: sector buffer, auto-increment */
__sfr __at(0x15) DRV_FLAGS;  /* w: b1:0 drive, b2 present, b3 write protected */
#endif

#define CTL_SD_CS   0x01
#define CTL_OSD_SS  0x02
#define CTL_SLOW    0x04

#define CTRL_MENU   0x01
#define CTRL_RESET  0x02

#endif
