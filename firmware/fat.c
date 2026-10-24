/* Minimal FAT16/FAT32 driver: 8.3 names (long names are skipped), directory
 * walking, and sector access to existing files (no create, no extend).
 * 512-byte sectors only. */
#include "fat.h"
#include "sd.h"

static uint32_t part_lba;
static uint32_t fat_lba;
static uint32_t root_lba;      /* FAT16 only */
static uint32_t data_lba;
static uint32_t root_clus;     /* FAT32 only */
static uint16_t root_secs;     /* FAT16 only */
static uint8_t  spc;
static uint8_t  spc_shift;
static uint8_t  fat32;

static uint8_t  fat_buf[512];
static uint32_t fat_buf_lba;
static uint8_t  dir_buf[512];
static uint32_t dir_buf_lba;

static uint16_t rd16(const uint8_t *p) { return p[0] | ((uint16_t)p[1] << 8); }
static uint32_t rd32(const uint8_t *p)
{
	return p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

#define NOLBA 0xFFFFFFFFUL

uint8_t fat_mount(void)
{
	uint8_t *b = dir_buf;
	uint32_t totsec, fatsz, nclus;
	uint16_t rsvd, rootent;
	uint8_t nfats, t;

	fat_buf_lba = NOLBA;
	dir_buf_lba = NOLBA;
	part_lba = 0;
	if (sd_read(0, b))
		return 1;
	if (b[510] != 0x55 || b[511] != 0xAA)
		return 2;
	t = b[450];
	/* a boot sector starts with a jump; otherwise it is an MBR */
	if (b[0] != 0xEB && b[0] != 0xE9) {
		if (t == 0)
			return 3;
		part_lba = rd32(b + 454);
		if (sd_read(part_lba, b))
			return 1;
		if (b[510] != 0x55 || b[511] != 0xAA)
			return 2;
	}
	if (rd16(b + 11) != 512)
		return 4;
	spc = b[13];
	rsvd = rd16(b + 14);
	nfats = b[16];
	rootent = rd16(b + 17);
	totsec = rd16(b + 19);
	if (totsec == 0)
		totsec = rd32(b + 32);
	fatsz = rd16(b + 22);
	if (fatsz == 0)
		fatsz = rd32(b + 36);
	if (spc == 0 || (spc & (spc - 1)))
		return 4;
	for (spc_shift = 0; (1 << spc_shift) < spc; spc_shift++)
		;
	root_secs = (rootent * 32 + 511) >> 9;
	fat_lba = part_lba + rsvd;
	root_lba = fat_lba + fatsz * nfats;
	data_lba = root_lba + root_secs;
	nclus = (totsec - (data_lba - part_lba)) >> spc_shift;
	if (nclus < 4085)
		return 5;               /* FAT12 */
	fat32 = nclus >= 65525;
	root_clus = fat32 ? rd32(b + 44) : 0;
	return 0;
}

uint32_t fat_root(void)
{
	return root_clus;
}

static uint32_t clus_lba(uint32_t c)
{
	return data_lba + ((c - 2) << spc_shift);
}

/* next cluster of the chain, 0 at the end */
static uint32_t next_cluster(uint32_t c)
{
	uint32_t lba, n;
	uint16_t off;

	if (fat32) {
		lba = fat_lba + (c >> 7);
		off = (uint16_t)(c & 127) << 2;
	} else {
		lba = fat_lba + (c >> 8);
		off = (uint16_t)(c & 255) << 1;
	}
	if (lba != fat_buf_lba) {
		if (sd_read(lba, fat_buf))
			return 0;
		fat_buf_lba = lba;
	}
	if (fat32) {
		n = rd32(fat_buf + off) & 0x0FFFFFFFUL;
		if (n >= 0x0FFFFFF8UL || n < 2)
			return 0;
	} else {
		n = rd16(fat_buf + off);
		if (n >= 0xFFF8U || n < 2)
			return 0;
	}
	return n;
}

void dir_open(dir_t *d, uint32_t clus)
{
	d->c = clus;
	d->s = 0;
	d->i = 0;
	d->loaded = 0;
	d->root16 = (clus == 0 && !fat32);
	if (clus == 0 && fat32)
		d->c = root_clus;
}

uint8_t dir_next(dir_t *d, dirent_t *e)
{
	const uint8_t *p;
	char *dst;
	uint32_t lba;
	uint8_t k;

	for (;;) {
		if (d->root16) {
			if (d->s >= root_secs)
				return 0;
			lba = root_lba + d->s;
		} else {
			if (d->c < 2)
				return 0;
			lba = clus_lba(d->c) + d->s;
		}
		if (lba != dir_buf_lba) {
			if (sd_read(lba, dir_buf)) {
				dir_buf_lba = NOLBA;
				return 0;
			}
			dir_buf_lba = lba;
		}
		p = dir_buf + ((uint16_t)d->i << 5);
		d->i++;
		if (d->i == 16) {
			d->i = 0;
			d->s++;
			if (!d->root16 && d->s == spc) {
				d->s = 0;
				d->c = next_cluster(d->c);
			}
		}
		if (p[0] == 0)
			return 0;
		if (p[0] == 0xE5 || p[11] == 0x0F || (p[11] & 0x08))
			continue;
		/* pointer copy (SDCC 4.0 miscompiled e->name[k] = p[k]; kept, it is as cheap) */
		dst = e->name;
		for (k = 0; k < 11; k++)
			*dst++ = p[k];
		e->attr = p[11];
		e->clus = rd16(p + 26) | ((uint32_t)rd16(p + 20) << 16);
		if (!fat32)
			e->clus &= 0xFFFFUL;
		e->size = rd32(p + 28);
		return 1;
	}
}

uint8_t dir_find(uint32_t clus, const char *name11, dirent_t *e)
{
	dir_t d;
	uint8_t k;

	dir_open(&d, clus);
	while (dir_next(&d, e)) {
		for (k = 0; k < 11 && e->name[k] == name11[k]; k++)
			;
		if (k == 11)
			return 1;
	}
	return 0;
}

void file_open(file_t *f, const dirent_t *e)
{
	f->start = e->clus;
	f->size = e->size;
	f->idx = 0;
	f->cur = e->clus;
}

uint8_t file_sector(file_t *f, uint32_t n, uint32_t *lba)
{
	uint32_t ci = n >> spc_shift;

	if (f->start < 2)
		return 1;
	if (ci < f->idx) {
		f->idx = 0;
		f->cur = f->start;
	}
	while (f->idx < ci) {
		f->cur = next_cluster(f->cur);
		if (f->cur == 0) {
			f->idx = 0xFFFFFFFFUL;
			return 2;
		}
		f->idx++;
	}
	*lba = clus_lba(f->cur) + (n & (spc - 1));
	return 0;
}

uint8_t file_read(file_t *f, uint32_t n, uint8_t *buf)
{
	uint32_t lba;

	if (file_sector(f, n, &lba))
		return 1;
	return sd_read(lba, buf);
}

uint8_t file_write(file_t *f, uint32_t n, const uint8_t *buf)
{
	uint32_t lba;

	if (file_sector(f, n, &lba))
		return 1;
	return sd_write(lba, buf);
}
