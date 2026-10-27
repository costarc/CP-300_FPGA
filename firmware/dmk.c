/* DMK image access for the floppy controller. */
#include "dmk.h"

#define NONE 0xFFFF

/* byte u of a field that starts at p, with a step of 1 or 2: no 32-bit multiply (slow on a Z80) */
#define UNIT(p, st, u) ((p) + ((st) == 2 ? (uint16_t)((uint16_t)(u) << 1) : (uint16_t)(u)))

static uint16_t crc_tab[256];

/* the block cache: DMK_WIN slots of 512 bytes, tagged with the image and the block they hold */
#ifdef DMK_CBUF_ADDR
#define cbuf ((uint8_t *)DMK_CBUF_ADDR)
#else
static uint8_t cbuf[DMK_WIN * 512];
#endif
static dmk_t   *s_own[DMK_WIN];
static uint16_t s_blk[DMK_WIN];
static uint8_t  s_dirty[DMK_WIN];
static uint8_t  s_last;            /* the slot used last: the next byte is most likely in it */
static uint8_t  s_victim;          /* the slot replaced next */
static uint8_t  bfail;
static uint8_t  junk;

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
	for (k = 0; k < DMK_WIN; k++) {
		s_own[k] = 0;
		s_blk[k] = NONE;
		s_dirty[k] = 0;
	}
	s_last = s_victim = 0;
}

static uint16_t crc_add(uint16_t crc, uint8_t b)
{
	return (crc << 8) ^ crc_tab[(crc >> 8) ^ b];
}

/* write the changed slots back (of the image d, or of all if d is 0); consecutive blocks in
 * consecutive slots go out in one call */
static void flush(dmk_t *d)
{
	uint8_t i, j;

	for (i = 0; i < DMK_WIN; i++) {
		if (!s_dirty[i] || (d && s_own[i] != d))
			continue;
		for (j = i; (uint8_t)(j + 1) < DMK_WIN && s_dirty[j + 1] && s_own[j + 1] == s_own[i] &&
		     s_blk[j + 1] == s_blk[j] + 1; j++)
			;
		if (file_write_blocks(&s_own[i]->f, s_blk[i], j - i + 1, cbuf + ((uint16_t)i << 9)))
			bfail = 1;
		for (; i <= j; i++)
			s_dirty[i] = 0;
		i = j;
	}
}

/* the slot that holds block blk of d, read in if it is not there (0xFF: it could not be read) */
static uint8_t slot_of(dmk_t *d, uint16_t blk)
{
	uint8_t i;

	for (i = 0; i < DMK_WIN; i++)
		if (s_own[i] == d && s_blk[i] == blk)
			return s_last = i;
	i = s_victim;
	s_victim = (uint8_t)(i + 1) == DMK_WIN ? 0 : i + 1;
	if (s_dirty[i]) {
		if (file_write_blocks(&s_own[i]->f, s_blk[i], 1, cbuf + ((uint16_t)i << 9)))
			bfail = 1;
		s_dirty[i] = 0;
	}
	s_own[i] = 0;
	s_blk[i] = NONE;
	if (file_read_blocks(&d->f, blk, 1, cbuf + ((uint16_t)i << 9)))
		return 0xFF;
	s_own[i] = d;
	s_blk[i] = blk;
	return s_last = i;
}

#if DMK_SPAN
/* make the n blocks from first the slots 0..n-1, with one call */
static void span_load(dmk_t *d, uint16_t first, uint16_t n)
{
	uint8_t k;

	if (n > DMK_WIN)
		n = DMK_WIN;
	if (first > d->endblk)
		return;                                    /* the blocks fail one by one when used */
	if (first + n - 1 > d->endblk)
		n = d->endblk - first + 1;
	for (k = 0; k < n; k++)
		if (s_own[k] != d || s_blk[k] != first + k)
			break;
	if (k == n)
		return;
	flush(0);
	for (k = 0; k < DMK_WIN; k++) {
		s_own[k] = 0;
		s_blk[k] = NONE;
	}
	if (file_read_blocks(&d->f, first, n, cbuf)) {
		/* a short image or a bad block: keep what can be read */
		for (k = 0; k < n; k++)
			if (file_read_blocks(&d->f, first + k, 1, cbuf + ((uint16_t)k << 9)))
				break;
		n = k;
	}
	for (k = 0; k < n; k++) {
		s_own[k] = d;
		s_blk[k] = first + k;
	}
	s_last = 0;
}
#endif

/* where byte off of the image is in the slot memory; s_last is its slot (for the dirty flag) */
static uint8_t *at(dmk_t *d, uint32_t off)
{
	uint16_t blk = (uint16_t)(off >> 9);
	uint8_t i = s_last;

	if (s_own[i] != d || s_blk[i] != blk) {
		i = slot_of(d, blk);
		if (i == 0xFF) {
			bfail = 1;
			junk = 0;
			return &junk;
		}
	}
	return cbuf + ((uint16_t)i << 9) + ((uint16_t)off & 511);
}

static uint8_t gb(dmk_t *d, uint32_t off)
{
	return *at(d, off);
}

static void pb(dmk_t *d, uint32_t off, uint8_t v)
{
	uint8_t *q = at(d, off);

	if (bfail)
		return;
	*q = v;
	s_dirty[s_last] = 1;
}

void dmk_forget(dmk_t *d)
{
	uint8_t k;

	flush(d);
	for (k = 0; k < DMK_WIN; k++)
		if (s_own[k] == d) {
			s_own[k] = 0;
			s_blk[k] = NONE;
		}
	d->cvalid = 0;
}

uint8_t dmk_open(dmk_t *d, const dirent_t *e)
{
	uint8_t flags;

	dmk_forget(d);
	file_open(&d->f, e);
	d->endblk = 0xFFFF;
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
	d->endblk = (uint16_t)((16UL + (uint32_t)d->ntracks * d->nsides * d->tlen - 1) >> 9);
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
static void fill_entry(dmk_t *d, uint8_t i)
{
	uint32_t p, end = d->cbase + d->tlen;
	uint8_t k, m, st, dd;

	d->eseen[i] = 1;
	d->edam[i] = 0;
	p = entry_pos(d, d->cbase, i, &st, &dd);
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
			d->gref = i;
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
	if (d->cvalid && d->ctrack == track && d->cside == side) {
#if DMK_SPAN
		span_load(d, (uint16_t)(d->cbase >> 9), (uint16_t)((d->cbase + d->tlen - 1) >> 9) - (uint16_t)(d->cbase >> 9) + 1);
#endif
		return 1;
	}
	base = track_off(d, track, side);
	d->cbase = base;
	bfail = 0;
#if DMK_SPAN
	span_load(d, (uint16_t)(base >> 9), (uint16_t)((base + d->tlen - 1) >> 9) - (uint16_t)(base >> 9) + 1);
#endif
	d->nent = 0;
	d->gref = 0xFF;
	for (i = 0; i < DMK_ENTRIES; i++)
		d->eseen[i] = 0;
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

static uint8_t matches(dmk_t *d, uint8_t i, uint8_t trkreg, uint8_t sec)
{
	return d->edam[i] && d->ecyl[i] == trkreg && d->esec[i] == sec;
}

/* the entry of the 256-byte sector (trkreg, sec), 0xFF if the track has none */
static uint8_t lookup(dmk_t *d, uint8_t trkreg, uint8_t sec)
{
	uint8_t i;
#if DMK_GUESS
	uint8_t k;
	int16_t g;
#endif

	for (i = 0; i < d->nent; i++)                    /* the ID fields read before */
		if (d->eseen[i] && matches(d, i, trkreg, sec))
			return i;
#if DMK_GUESS
	/* the entry with the sector's number; after a miss, the one at the same distance from the last
	 * usable ID read; each guess costs one block read instead of one per entry scanned */
	g = d->gref == 0xFF ? sec : (int16_t)d->gref + sec - d->esec[d->gref];
	for (k = 0; k < d->nent && g >= 0 && g < d->nent && !d->eseen[g]; k++) {
		fill_entry(d, (uint8_t)g);
		if (matches(d, (uint8_t)g, trkreg, sec))
			return (uint8_t)g;
		if (!d->edam[g])
			break;
		g = (int16_t)g + sec - d->esec[g];
	}
#endif
	for (i = 0; i < d->nent; i++) {                  /* then all the rest, in table order */
		if (d->eseen[i])
			continue;
		fill_entry(d, i);
		if (matches(d, i, trkreg, sec))
			return i;
	}
	return 0xFF;
}

/* find the 256-byte sector; pos/step/dd describe its ID field, dam is the unit offset of the data mark */
static uint8_t find(dmk_t *d, uint8_t track, uint8_t side, uint8_t trkreg, uint8_t sec,
                    uint32_t *pos, uint8_t *step, uint8_t *dd, uint8_t *dam)
{
	uint8_t i;

	if (!load_track(d, track, side))
		return 0;
	i = lookup(d, trkreg, sec);
	if (i == 0xFF)
		return 0;
	*pos = entry_pos(d, d->cbase, i, step, dd);
	*dam = d->edam[i];
	return 1;
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
	uint8_t step, dd, k, mark, v, res, *q;
	uint16_t j, n, rem, crc, stored;

	bfail = 0;
	if (!find(d, track, side, trkreg, sec, &pos, &step, &dd, &k))
		return 0;
	mark = gb(d, UNIT(pos, step, k));
	crc = crc_start(dd, mark);
	p = UNIT(pos, step, k + 1);
	/* the data, a cache slot at a time: no lookup per byte */
	for (j = 0; j < 256; ) {
		q = at(d, p);
		if (bfail)
			return 0;
		rem = 512 - ((uint16_t)p & 511);
		n = step == 2 ? (rem + 1) >> 1 : rem;          /* units that start in this slot */
		if (n > 256 - j)
			n = 256 - j;
		p += step == 2 ? n << 1 : n;
		for (; n; n--) {
			v = *q;
			q += step;
			buf[j++] = v;
			crc = crc_add(crc, v);
		}
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
	uint32_t pos, p;
	uint8_t step, dd, k, mark, v, *q;
	uint16_t j, n, rem, crc, u;

	bfail = 0;
	if (d->readonly || !find(d, track, side, trkreg, sec, &pos, &step, &dd, &k))
		return 0;
	mark = deleted ? 0xF8 : 0xFB;
	crc = crc_start(dd, mark);
	put_unit(d, pos, step, k, mark);
	u = k + 1;
	for (j = 0; j < 256 && !bfail; ) {
		p = UNIT(pos, step, u);
		q = at(d, p);
		if (bfail)
			break;
		rem = 512 - ((uint16_t)p & 511);
		n = step == 2 ? rem >> 1 : rem;                /* units that fit in this slot, doubled bytes whole */
		if (!n) {                                      /* a doubled byte across two slots */
			v = buf[j++];
			crc = crc_add(crc, v);
			put_unit(d, pos, step, u++, v);
			continue;
		}
		if (n > 256 - j)
			n = 256 - j;
		s_dirty[s_last] = 1;
		u += n;
		for (; n; n--) {
			v = buf[j++];
			*q = v;
			if (step == 2)
				q[1] = v;
			q += step;
			crc = crc_add(crc, v);
		}
	}
	put_unit(d, pos, step, u++, crc >> 8);
	put_unit(d, pos, step, u, crc);
	flush(d);
	return !bfail;
}

uint8_t dmk_read_address(dmk_t *d, uint8_t track, uint8_t side, uint8_t *id)
{
	uint32_t p;
	uint8_t i, k, st, dd;

	bfail = 0;
	if (!load_track(d, track, side) || !d->nent)
		return 0;
	i = d->ra_next;
	if (i >= d->nent)
		i = 0;
	d->ra_next = i + 1;
	p = entry_pos(d, d->cbase, i, &st, &dd);
	for (k = 0; k < 6; k++)
		id[k] = gb(d, UNIT(p, st, k + 1));
	return bfail ? 0 : DMK_FOUND;
}
