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
#endif

#define CTL_SD_CS   0x01
#define CTL_OSD_SS  0x02
#define CTL_SLOW    0x04

#define CTRL_MENU   0x01
#define CTRL_RESET  0x02

#endif
