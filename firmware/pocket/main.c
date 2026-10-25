/* CP-300 FPGA IO controller firmware for the Analogue Pocket.
 *
 * The four floppy drives are the data slots 0-3 of the core (deferload): the Pocket's own menu loads
 * a DMK image into a slot. This program mounts what the slots hold, serves the sector requests of the
 * floppy controller from the DMK images (dmk.c) and writes changed sectors back through the same
 * slot. There is no menu, no SD card and no keyboard code here.
 *
 * No global has an initializer: the RAM is cleared at start-up and the ROM does not carry a copy
 * of the initial values.
 */
#include "hw.h"
#include "slotfile.h"
#include "../dmk.h"

#define NDRIVES 4

static uint8_t sector[512];

static dmk_t drive[NDRIVES];
static uint8_t drive_ok[NDRIVES];
static uint8_t wp_shown;                 /* the "write protect all" option the drive flags were built with */

/* tell the floppy controller what is in drive d */
static void set_flags(uint8_t d)
{
	uint8_t flags = d;

	if (drive_ok[d]) {
		flags |= 0x04;
		if (drive[d].readonly || (SLOT_OPT & OPT_WP))
			flags |= 0x08;
	}
	DRV_FLAGS = flags;
}

static void mount_drive(uint8_t d)
{
	dirent_t e;

	e.slot = d;
	drive_ok[d] = 0;
	dmk_forget(&drive[d]);
	if ((SLOT_PRES >> d) & 1)
		drive_ok[d] = dmk_open(&drive[d], &e);
	set_flags(d);
}

/* answer a request of the floppy controller: read or write a sector, or the next ID field */
static void fdc_service(void)
{
	uint8_t req = FDC_REQ;
	uint8_t d, side, trk, reg, sec, res;
	uint16_t n;

	if (!(req & 7))
		return;
	d = (req >> 4) & 3;
	side = (req >> 3) & 1;
	trk = FDC_TRK;
	reg = FDC_TRKREG;
	sec = FDC_SEC;
	if (req & 1) {
		res = drive_ok[d] ? dmk_read_sector(&drive[d], trk, side, reg, sec, sector) : 0;
		FDC_RES = res;
		FDC_ACK = 1;
		if (res & DMK_FOUND)
			for (n = 0; n < 256; n++)
				FDC_BUF = sector[n];
		FDC_ACK = 0;
	} else if (req & 2) {
		FDC_ACK = 1;                    /* the controller holds the data; the write is done under ACK */
		for (n = 0; n < 256; n++)
			sector[n] = FDC_BUF;
		res = drive_ok[d] ? dmk_write_sector(&drive[d], trk, side, reg, sec, sector, (req >> 6) & 1) : 0;
		FDC_RES = res ? DMK_FOUND : 0;
		FDC_ACK = 0;
	} else {
		res = drive_ok[d] ? dmk_read_address(&drive[d], trk, side, sector) : 0;
		FDC_RES = res;
		FDC_ACK = 1;
		if (res & DMK_FOUND)
			for (n = 0; n < 6; n++)
				FDC_BUF = sector[n];
		FDC_ACK = 0;
	}
}

/* status byte for the interact menu: b3:0 drive mounted, b7 running */
static void show_status(void)
{
	uint8_t d, s = 0x80;

	for (d = 0; d < NDRIVES; d++)
		if (drive_ok[d])
			s |= 1 << d;
	DBG = s;
}

void main(void)
{
	uint8_t d, chg, opt;

	DBG = 0x01;
	dmk_init();
	while (!(SLOT_OPT & OPT_SCANNED))
		;                        /* the slot table is read once the framework has filled it */
	for (d = 0; d < NDRIVES; d++)
		mount_drive(d);
	SLOT_CHG = 0x0F;
	wp_shown = SLOT_OPT & OPT_WP;
	show_status();
	CTRL = 0;                    /* release the CP-300, it has been held in reset since power-on */
	for (;;) {
		fdc_service();
		chg = SLOT_CHG;
		if (chg) {
			for (d = 0; d < NDRIVES; d++)
				if (chg & (1 << d)) {
					SLOT_CHG = 1 << d;
					mount_drive(d);
				}
			show_status();
		}
		opt = SLOT_OPT & OPT_WP;
		if (opt != wp_shown) {
			wp_shown = opt;
			for (d = 0; d < NDRIVES; d++)
				set_flags(d);
		}
	}
}
