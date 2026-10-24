/* DMK image access for the floppy controller. */
#include "dmk.h"

#define NONE 0xFFFF

/* byte u of a field that starts at p, with a step of 1 or 2: no 32-bit multiply (slow on a Z80) */
#define UNIT(p, st, u) ((p) + ((st) == 2 ? (uint16_t)((uint16_t)(u) << 1) : (uint16_t)(u)))

static uint16_t crc_tab[256];

static uint8_t  bcache[512];       /* one block of one image */
static dmk_t   *bowner;
static uint16_t bblk = NONE;
static uint8_t  bdirty;
static uint8_t  bfail;

void dmk_init(void)
{
	uint16_t i, c;
	uint8_t k;

	for (i = 0; i < 256; i++) {
		c = i << 8;
		for (k = 0; k < 8; k++)
			c = (c & 0x8000) ? (c << 1) ^ 0x1021 : c << 1;
		crc_tab[i] = c;
	}
	bowner = 0;
	bblk = NONE;
}

static uint16_t crc_add(uint16_t crc, uint8_t b)
{
	return (crc << 8) ^ crc_tab[(crc >> 8) ^ b];
}

static void flush(void)
{
	if (bdirty && bowner && file_write(&bowner->f, bblk, bcache))
		bfail = 1;
	bdirty = 0;
}

static void load(dmk_t *d, uint16_t blk)
{
	if (bowner == d && bblk == blk)
		return;
	flush();
	bowner = d;
	bblk = blk;
	if (file_read(&d->f, blk, bcache)) {
		bfail = 1;
		bblk = NONE;
	}
}

static uint8_t gb(dmk_t *d, uint32_t off)
{
	load(d, (uint16_t)(off >> 9));
	return bcache[(uint16_t)off & 511];
}

static void pb(dmk_t *d, uint32_t off, uint8_t v)
{
	load(d, (uint16_t)(off >> 9));
	bcache[(uint16_t)off & 511] = v;
	bdirty = 1;
}

void dmk_forget(dmk_t *d)
{
	if (bowner == d) {
		flush();
		bowner = 0;
		bblk = NONE;
	}
	d->cvalid = 0;
}

uint8_t dmk_open(dmk_t *d, const dirent_t *e)
{
	uint8_t flags;

	dmk_forget(d);
	file_open(&d->f, e);
	bfail = 0;
	d->ntracks = gb(d, 1);
	d->tlen = gb(d, 2) | ((uint16_t)gb(d, 3) << 8);
	flags = gb(d, 4);
	d->readonly = gb(d, 0) == 0xFF;
	d->nsides = (flags & 0x10) ? 1 : 2;
	d->doubled = !(flags & 0xC0);
	d->cvalid = 0;
	d->ra_next = 0;
	if (bfail || d->ntracks == 0 || d->ntracks > 100 || d->tlen < 0x80 + 16 || d->tlen > 0x2940)
		return 0;
	return 1;
}

static uint32_t track_off(dmk_t *d, uint8_t track, uint8_t side)
{
	uint32_t n = track;

	n = n * d->nsides + side;
	return 16 + n * d->tlen;
}

/* where the entry i of the track table is: first byte of the ID mark, step between bytes, density */
static uint32_t entry_pos(dmk_t *d, uint32_t base, uint8_t i, uint8_t *step, uint8_t *dd)
{
	uint16_t p = d->idam[i];

	*dd = (p & 0x8000) != 0;
	*step = (d->doubled && !*dd) ? 2 : 1;
	return base + (p & 0x3FFF);
}

/* read the ID field of entry i: cylinder, sector and where the data mark is, kept for later lookups */
static void fill_entry(dmk_t *d, uint32_t base, uint8_t i)
{
	uint32_t p, end = base + d->tlen;
	uint8_t k, m, st, dd;

	d->edam[i] = 0;
	p = entry_pos(d, base, i, &st, &dd);
	if (gb(d, p) != 0xFE)
		return;
	d->ecyl[i] = gb(d, UNIT(p, st, 1));
	d->esec[i] = gb(d, UNIT(p, st, 3));
	if (gb(d, UNIT(p, st, 4)) != 1)             /* only 256-byte sectors */
		return;
	for (k = 7; k < 90; k++) {
		if (UNIT(p, st, k) >= end)
			break;
		m = gb(d, UNIT(p, st, k));
		if (m >= 0xF8 && m <= 0xFB) {
			d->edam[i] = k;
			break;
		}
	}
}

/* the pointer table of a track (the ID fields are read when a lookup needs them);
 * 0 if the track is not in the image */
static uint8_t load_track(dmk_t *d, uint8_t track, uint8_t side)
{
	uint32_t base;
	uint16_t ptr;
	uint8_t i;

	if (track >= d->ntracks || side >= d->nsides)
		return 0;
	if (d->cvalid && d->ctrack == track && d->cside == side)
		return 1;
	base = track_off(d, track, side);
	bfail = 0;
	d->nent = 0;
	d->efill = 0;
	for (i = 0; i < DMK_ENTRIES; i++) {
		ptr = gb(d, base + 2 * i) | ((uint16_t)gb(d, base + 2 * i + 1) << 8);
		if (!ptr)
			break;
		d->idam[i] = ptr;
		d->nent = i + 1;
	}
	if (bfail)
		return 0;
	d->ctrack = track;
	d->cside = side;
	d->cvalid = 1;
	d->ra_next = 0;
	return 1;
}

/* find the 256-byte sector; pos/step/dd describe its ID field, dam is the unit offset of the data mark */
static uint8_t find(dmk_t *d, uint8_t track, uint8_t side, uint8_t trkreg, uint8_t sec,
                    uint32_t *pos, uint8_t *step, uint8_t *dd, uint8_t *dam)
{
	uint8_t i;

	if (!load_track(d, track, side))
		return 0;
	for (i = 0; i < d->nent; i++) {
		if (i >= d->efill) {
			fill_entry(d, track_off(d, track, side), i);
			d->efill = i + 1;
		}
		if (d->edam[i] && d->ecyl[i] == trkreg && d->esec[i] == sec) {
			*pos = entry_pos(d, track_off(d, track, side), i, step, dd);
			*dam = d->edam[i];
			return 1;
		}
	}
	return 0;
}

static uint16_t crc_start(uint8_t dd, uint8_t mark)
{
	uint16_t crc = 0xFFFF;

	if (dd) {
		crc = crc_add(crc, 0xA1);
		crc = crc_add(crc, 0xA1);
		crc = crc_add(crc, 0xA1);
	}
	return crc_add(crc, mark);
}

uint8_t dmk_read_sector(dmk_t *d, uint8_t track, uint8_t side, uint8_t trkreg, uint8_t sec, uint8_t *buf)
{
	uint32_t pos, p;
	uint8_t step, dd, k, mark, v, res;
	uint16_t j, crc, stored;

	bfail = 0;
	if (!find(d, track, side, trkreg, sec, &pos, &step, &dd, &k))
		return 0;
	mark = gb(d, UNIT(pos, step, k));
	crc = crc_start(dd, mark);
	p = UNIT(pos, step, k + 1);
	for (j = 0; j < 256; j++) {
		v = gb(d, p);
		buf[j] = v;
		crc = crc_add(crc, v);
		p += step;
	}
	stored = (uint16_t)gb(d, p) << 8;
	stored |= gb(d, p + step);
	if (bfail)
		return 0;
	res = DMK_FOUND;
	if (stored != crc)
		res |= DMK_CRCERR;
	if (mark != 0xFB)
		res |= DMK_DELETED;
	return res;
}

/* a byte at unit u (counted from the ID mark) goes into every copy of a doubled byte */
static void put_unit(dmk_t *d, uint32_t pos, uint8_t step, uint16_t u, uint8_t v)
{
	uint32_t p = UNIT(pos, step, u);

	pb(d, p, v);
	if (step == 2)
		pb(d, p + 1, v);
}

uint8_t dmk_write_sector(dmk_t *d, uint8_t track, uint8_t side, uint8_t trkreg, uint8_t sec,
                         const uint8_t *buf, uint8_t deleted)
{
	uint32_t pos;
	uint8_t step, dd, k, mark;
	uint16_t j, crc, u;

	bfail = 0;
	if (d->readonly || !find(d, track, side, trkreg, sec, &pos, &step, &dd, &k))
		return 0;
	mark = deleted ? 0xF8 : 0xFB;
	crc = crc_start(dd, mark);
	put_unit(d, pos, step, k, mark);
	u = k + 1;
	for (j = 0; j < 256; j++) {
		put_unit(d, pos, step, u++, buf[j]);
		crc = crc_add(crc, buf[j]);
	}
	put_unit(d, pos, step, u++, crc >> 8);
	put_unit(d, pos, step, u, crc);
	flush();
	return !bfail;
}

uint8_t dmk_read_address(dmk_t *d, uint8_t track, uint8_t side, uint8_t *id)
{
	uint32_t base, p;
	uint8_t i, k, st, dd;

	bfail = 0;
	if (!load_track(d, track, side) || !d->nent)
		return 0;
	i = d->ra_next;
	if (i >= d->nent)
		i = 0;
	d->ra_next = i + 1;
	base = track_off(d, track, side);
	p = entry_pos(d, base, i, &st, &dd);
	for (k = 0; k < 6; k++)
		id[k] = gb(d, UNIT(p, st, k + 1));
	return bfail ? 0 : DMK_FOUND;
}
