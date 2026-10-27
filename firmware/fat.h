#ifndef FAT_H
#define FAT_H

#include <stdint.h>

#define ATTR_DIR  0x10

typedef struct {
	char     name[11];     /* 8.3, space padded, upper case */
	uint8_t  attr;
	uint32_t clus;
	uint32_t size;
} dirent_t;

typedef struct {
	uint32_t c;            /* current cluster (0 for the FAT16 root) */
	uint16_t s;            /* sector within the cluster / root */
	uint8_t  i;            /* entry within the sector */
	uint8_t  loaded;
	uint8_t  root16;
} dir_t;

typedef struct {
	uint32_t start;
	uint32_t size;
	uint32_t idx;          /* cluster index cached in cur */
	uint32_t cur;
} file_t;

uint8_t  fat_mount(void);
uint32_t fat_root(void);                                   /* cluster to pass to dir_open for the root */
void     dir_open(dir_t *d, uint32_t clus);
uint8_t  dir_next(dir_t *d, dirent_t *e);                  /* 1 = entry, 0 = end of directory */
uint8_t  dir_find(uint32_t clus, const char *name11, dirent_t *e);
void     file_open(file_t *f, const dirent_t *e);
uint8_t  file_sector(file_t *f, uint32_t n, uint32_t *lba); /* 0 = ok, mapped absolute LBA */
uint8_t  file_read(file_t *f, uint32_t n, uint8_t *buf);
uint8_t  file_write(file_t *f, uint32_t n, const uint8_t *buf);
/* cnt consecutive blocks from block n, 0 = ok (dmk.c) */
uint8_t  file_read_blocks(file_t *f, uint32_t n, uint16_t cnt, uint8_t *buf);
uint8_t  file_write_blocks(file_t *f, uint32_t n, uint16_t cnt, const uint8_t *buf);

#endif
