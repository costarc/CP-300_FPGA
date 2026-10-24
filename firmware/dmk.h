#ifndef DMK_H
#define DMK_H

#include <stdint.h>
#include "fat.h"

/* DMK disk images (David Keil): 16-byte header, then for every track and side a 128-byte table of
 * ID-field pointers followed by the track bytes as they are on the disk, ID fields, data fields and
 * CRCs included. The controller reads and writes sectors through these functions. */

#define DMK_ENTRIES 32

typedef struct {
	file_t   f;
	uint16_t tlen;          /* bytes per track, table included */
	uint8_t  ntracks;
	uint8_t  nsides;
	uint8_t  doubled;       /* single density bytes are stored twice */
	uint8_t  readonly;      /* write protect byte of the header */
	uint8_t  ctrack, cside; /* the track whose pointer table is in idam[] */
	uint8_t  cvalid;
	uint8_t  ra_next;       /* next ID field for READ ADDRESS */
	/* the first 32 ID fields of the cached track: pointer, cylinder, sector, unit offset of the
	 * data mark (0 = not a usable 256-byte sector) */
	uint8_t  nent;          /* entries in the table */
	uint8_t  efill;         /* entries 0..efill-1 have been read (ecyl, esec, edam) */
	uint16_t idam[DMK_ENTRIES];
	uint8_t  ecyl[DMK_ENTRIES];
	uint8_t  esec[DMK_ENTRIES];
	uint8_t  edam[DMK_ENTRIES];
} dmk_t;

/* result flags of read/address requests */
#define DMK_FOUND   0x01
#define DMK_CRCERR  0x02
#define DMK_DELETED 0x04    /* data mark other than FB */

void    dmk_init(void);                                       /* once at start */
void    dmk_forget(dmk_t *d);                                  /* before reusing the struct */
uint8_t dmk_open(dmk_t *d, const dirent_t *e);                /* 1 = a usable DMK */
/* 256-byte sector with ID (trkreg, sec) on the track under the head; returns DMK_* flags (0 = not found) */
uint8_t dmk_read_sector(dmk_t *d, uint8_t track, uint8_t side, uint8_t trkreg, uint8_t sec, uint8_t *buf);
uint8_t dmk_write_sector(dmk_t *d, uint8_t track, uint8_t side, uint8_t trkreg, uint8_t sec,
                         const uint8_t *buf, uint8_t deleted);  /* 1 = written */
/* next ID field of the track: C H R N CRC1 CRC2 into id[0..5]; returns DMK_FOUND or 0 */
uint8_t dmk_read_address(dmk_t *d, uint8_t track, uint8_t side, uint8_t *id);

#endif
