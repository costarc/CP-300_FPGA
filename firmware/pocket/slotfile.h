/* The file interface of dmk.c on the Analogue Pocket: a "file" is an APF data slot (one per drive).
 * The IO controller moves whole runs of blocks between the slot and the track RAM at 8000h-BFFF
 * (io_ctrl_pocket.vhd); dmk.c keeps its block cache there. */
#ifndef SLOTFILE_H
#define SLOTFILE_H

#include <stdint.h>

#define TRACK_RAM ((uint8_t *)0x8000)

typedef struct {
	uint8_t slot;
} dirent_t;

typedef struct {
	uint8_t  slot;
	uint32_t size;
} file_t;

void    file_open(file_t *f, const dirent_t *e);
/* cnt blocks from block n; buf is in the track RAM. 0 = ok. The last block of the file may be short. */
uint8_t file_read_blocks(file_t *f, uint32_t n, uint16_t cnt, uint8_t *buf);
uint8_t file_write_blocks(file_t *f, uint32_t n, uint16_t cnt, const uint8_t *buf);

#endif
