/* Blocks of an APF data slot, through the ports of io_ctrl_pocket.vhd. */
#include "hw.h"
#include "slotfile.h"

#define TIMEOUT 40000UL      /* x 64 polls: about a second; the framework answers in a few ms */

void file_open(file_t *f, const dirent_t *e)
{
	f->slot = e->slot;
}

/* start the command and wait for it; 0 = ok */
static uint8_t slot_cmd(uint8_t slot, uint32_t n, uint8_t cmd)
{
	uint32_t t;
	uint8_t i;

	SLOT_NUM = slot;
	SLOT_OFF0 = 0;
	SLOT_OFF1 = (uint8_t)(n << 1);
	SLOT_OFF2 = (uint8_t)(n >> 7);
	SLOT_OFF3 = (uint8_t)(n >> 15);
	SLOT_CMD = cmd;
	for (t = 0; t < TIMEOUT; t++) {
		for (i = 0; i < 64; i++)
			if (!(SLOT_CMD & 1))
				return (SLOT_CMD & 2) ? 2 : 0;
	}
	return 1;
}

uint8_t file_read(file_t *f, uint32_t n, uint8_t *buf)
{
	uint16_t i;
	uint8_t r;

	r = slot_cmd(f->slot, n, 1);
	if (r)
		return r;
	SLOT_PTR = 0;
	for (i = 0; i < 512; i++)
		buf[i] = SLOT_RX;
	return 0;
}

uint8_t file_write(file_t *f, uint32_t n, const uint8_t *buf)
{
	uint16_t i;

	SLOT_PTR = 0;
	for (i = 0; i < 512; i++)
		SLOT_TX = buf[i];
	return slot_cmd(f->slot, n, 2);
}
