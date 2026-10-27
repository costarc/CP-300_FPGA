/* Runs of blocks of an APF data slot, through the ports of io_ctrl_pocket.vhd. */
#include "hw.h"
#include "slotfile.h"

#define TIMEOUT 40000UL      /* x 64 polls: about a second; the framework answers in a few ms */

/* size of the file in a slot; the value crosses clock domains, so read it until it is stable */
static uint32_t slot_size(uint8_t slot)
{
	uint32_t a, b;
	uint8_t i;

	SLOT_NUM = slot;
	b = 0;
	for (i = 0; i < 8; i++) {
		a = (uint32_t)SLOT_SIZE0 | ((uint32_t)SLOT_SIZE1 << 8) | ((uint32_t)SLOT_SIZE2 << 16) |
		    ((uint32_t)SLOT_SIZE3 << 24);
		if (a == b)
			break;
		b = a;
	}
	return a;
}

void file_open(file_t *f, const dirent_t *e)
{
	f->slot = e->slot;
	f->size = slot_size(e->slot);
}

/* start the command and wait for it; 0 = ok */
static uint8_t slot_cmd(file_t *f, uint32_t n, uint16_t cnt, const uint8_t *buf, uint8_t cmd)
{
	uint32_t t, bytes = (uint32_t)cnt << 9;
	uint16_t boff = (uint16_t)(buf - TRACK_RAM);
	uint8_t i;

	if ((uint32_t)(n << 9) >= f->size)
		return 1;
	if (f->size - (n << 9) < bytes)              /* the last block of the file is short */
		bytes = f->size - (n << 9);
	SLOT_NUM = f->slot;
	SLOT_OFF0 = 0;
	SLOT_OFF1 = (uint8_t)(n << 1);
	SLOT_OFF2 = (uint8_t)(n >> 7);
	SLOT_OFF3 = (uint8_t)(n >> 15);
	SLOT_LENL = (uint8_t)bytes;
	SLOT_LENH = (uint8_t)(bytes >> 8);
	SLOT_BOFF0 = (uint8_t)boff;
	SLOT_BOFF1 = (uint8_t)(boff >> 8);
	SLOT_CMD = cmd;
	for (t = 0; t < TIMEOUT; t++) {
		for (i = 0; i < 64; i++)
			if (!(SLOT_CMD & 1))
				return (SLOT_CMD & 2) ? 2 : 0;
	}
	return 1;
}

uint8_t file_read_blocks(file_t *f, uint32_t n, uint16_t cnt, uint8_t *buf)
{
	return slot_cmd(f, n, cnt, buf, 1);
}

uint8_t file_write_blocks(file_t *f, uint32_t n, uint16_t cnt, const uint8_t *buf)
{
	return slot_cmd(f, n, cnt, buf, 2);
}
