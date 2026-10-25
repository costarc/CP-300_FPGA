/* The file interface of dmk.c on the Analogue Pocket: a "file" is an APF data slot (one per drive),
 * read and written 512 bytes at a time through the IO controller's slot ports. */
#ifndef SLOTFILE_H
#define SLOTFILE_H

#include <stdint.h>

typedef struct {
	uint8_t slot;
} dirent_t;

typedef struct {
	uint8_t slot;
} file_t;

void    file_open(file_t *f, const dirent_t *e);
uint8_t file_read(file_t *f, uint32_t n, uint8_t *buf);          /* block n, 0 = ok */
uint8_t file_write(file_t *f, uint32_t n, const uint8_t *buf);

#endif
