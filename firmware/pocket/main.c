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
#define NHD     2
#define HD_SLOT 6                        /* data slots of the HDV images */
#define HDBUF   (TRACK_RAM + 0x3E00)     /* the last 512 bytes of the track RAM (the DMK cache stops short of it) */

static uint8_t sector[512];

static dmk_t drive[NDRIVES];
static uint8_t drive_ok[NDRIVES];
static file_t hdf[NHD];
static uint8_t hd_ok[NHD];
static uint8_t hd_prot[NHD];             /* write protect flag of the image header */
static uint16_t hd_cyls[NHD];
static uint16_t hd_spc[NHD];             /* sectors per cylinder */
static uint8_t wp_shown;                 /* the "write protect all" option the drive flags were built with */
static uint8_t eject_shown;              /* the "eject all disks" option the drives were mounted with */
static uint8_t ejected;                  /* it is on: no disk is mounted */

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
	if (!ejected && ((SLOT_PRES >> d) & 1))
		drive_ok[d] = dmk_open(&drive[d], &e);
	set_flags(d);
}

/* tell the hard disk controller what is in hard disk d (an HDV image: 256-byte header, then 256-byte sectors) */
static void set_hd_flags(uint8_t d)
{
	uint8_t flags = 0x10 | d;

	if (hd_ok[d]) {
		flags |= 0x04;
		if (hd_prot[d] || (SLOT_OPT & OPT_WP))
			flags |= 0x08;
	}
	DRV_FLAGS = flags;
}

static void mount_hd(uint8_t d)
{
	dirent_t e;
	uint8_t *h = HDBUF;

	e.slot = HD_SLOT + d;
	hd_ok[d] = 0;
	if (!ejected && ((SLOT_PRES >> (HD_SLOT + d)) & 1)) {
		file_open(&hdf[d], &e);
		if (!file_read_blocks(&hdf[d], 0, 1, h) && h[0] == 0x56 && h[1] == 0xCB && h[2] == 0x10 && !(h[29] & 31)) {
			hd_ok[d] = 1;
			hd_prot[d] = h[7] >> 7;
			hd_cyls[d] = h[28] ? h[28] : 256;
			hd_spc[d] = h[29] ? h[29] : 256;
		}
	}
	set_hd_flags(d);
}

/* answer a request of the hard disk controller: read or write the sector (cylinder, head, sector) */
static void hd_service(uint8_t req)
{
	uint8_t d = (req >> 4) & 1, head = (FDC_TRKREG >> 2) & 7, sec = FDC_SEC, res = 0;
	uint16_t cyl = ((uint16_t)(FDC_TRKREG & 3) << 8) | FDC_TRK, x, n, blk = 0;
	uint8_t *p = HDBUF;

	if (hd_ok[d] && cyl < hd_cyls[d] && head < (hd_spc[d] >> 5) && sec <= 32) {
		/* sector index x in the image; its file offset is 256 * (x + 1) */
		x = cyl * hd_spc[d] + ((uint16_t)head << 5) + (sec & 31);
		blk = (x >> 1) + (x & 1);
		if (!(x & 1))
			p += 256;
		res = !file_read_blocks(&hdf[d], blk, 1, HDBUF);
	}
	if (req & 1) {
		FDC_RES = res;
		FDC_ACK = 1;
		if (res)
			for (n = 0; n < 256; n++)
				FDC_BUF = p[n];
	} else {
		FDC_ACK = 1;                    /* the controller holds the data; the write is done under ACK */
		for (n = 0; n < 256; n++)
			p[n] = FDC_BUF;
		FDC_RES = res && !file_write_blocks(&hdf[d], blk, 1, HDBUF);
	}
	FDC_ACK = 0;
}

/* answer a request of the floppy controller: read or write a sector, or the next ID field */
static void fdc_service(void)
{
	uint8_t req = FDC_REQ;
	uint8_t d, side, trk, reg, sec, res;
	uint16_t n;

	if (!(req & 7))
		return;
	if (req & 0x80) {
		hd_service(req);
		return;
	}
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
	for (d = 0; d < NHD; d++)
		mount_hd(d);
	SLOT_CHG = 0xCF;
	eject_shown = SLOT_OPT & OPT_EJECT;
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
			for (d = 0; d < NHD; d++)
				if (chg & (1 << (HD_SLOT + d))) {
					SLOT_CHG = 1 << (HD_SLOT + d);
					mount_hd(d);
				}
			show_status();
		}
		opt = SLOT_OPT & OPT_EJECT;
		if (opt != eject_shown) {
			eject_shown = opt;
			ejected = opt != 0;
			for (d = 0; d < NDRIVES; d++)
				mount_drive(d);
			for (d = 0; d < NHD; d++)
				mount_hd(d);
			show_status();
		}
		opt = SLOT_OPT & OPT_WP;
		if (opt != wp_shown) {
			wp_shown = opt;
			for (d = 0; d < NDRIVES; d++)
				set_flags(d);
			for (d = 0; d < NHD; d++)
				set_hd_flags(d);
		}
	}
}
