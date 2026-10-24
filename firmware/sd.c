/* SD card, SPI mode (SDSC and SDHC). */
#include "hw.h"
#include "sd.h"

static uint8_t ctl;      /* shadow of SPI_CTL */
static uint8_t sdhc;

static void set_ctl(uint8_t v)
{
	ctl = v;
	SPI_CTL = v;
}

static uint8_t spi(uint8_t b)
{
	SPI_DATA = b;
	while (SPI_CTL & 1)
		;
	return SPI_DATA;
}

static void deselect(void)
{
	set_ctl(ctl & ~CTL_SD_CS);
	spi(0xFF);
}

static uint8_t select_wait(void)
{
	uint16_t n;

	set_ctl(ctl | CTL_SD_CS);
	spi(0xFF);
	for (n = 0; n < 20000; n++)
		if (spi(0xFF) == 0xFF)
			return 0;
	return 1;
}

/* command with the card already selected; returns R1 */
static uint8_t cmd(uint8_t c, uint32_t arg, uint8_t crc)
{
	uint8_t r, n;

	spi(0x40 | c);
	spi(arg >> 24);
	spi(arg >> 16);
	spi(arg >> 8);
	spi(arg);
	spi(crc);
	for (n = 0; n < 10; n++) {
		r = spi(0xFF);
		if (!(r & 0x80))
			break;
	}
	return r;
}

static uint8_t acmd(uint8_t c, uint32_t arg)
{
	cmd(55, 0, 0x65);
	return cmd(c, arg, 0x77);
}

static uint8_t init_card(void)
{
	uint8_t r, i, v2 = 0;
	uint16_t n;

	sdhc = 0;
	set_ctl(CTL_SLOW);
	for (i = 0; i < 10; i++)
		spi(0xFF);

	if (select_wait()) {
		deselect();
		return 1;
	}
	r = 0xFF;
	for (i = 0; i < 20 && r != 1; i++)
		r = cmd(0, 0, 0x95);
	if (r != 1) {
		deselect();
		return 2;
	}
	if (cmd(8, 0x1AA, 0x87) == 1) {
		uint8_t b[4];
		for (i = 0; i < 4; i++)
			b[i] = spi(0xFF);
		if (b[2] != 0x01 || b[3] != 0xAA) {
			deselect();
			return 3;
		}
		v2 = 1;
	}
	for (n = 0; n < 20000; n++) {
		r = acmd(41, v2 ? 0x40000000UL : 0);
		if (r == 0)
			break;
	}
	if (r != 0) {
		deselect();
		return 4;
	}
	if (v2) {
		if (cmd(58, 0, 0x01) == 0) {
			uint8_t ocr = spi(0xFF);
			spi(0xFF);
			spi(0xFF);
			spi(0xFF);
			sdhc = (ocr & 0x40) != 0;
		}
	}
	if (!sdhc)
		cmd(16, 512, 0x01);
	deselect();
	return 0;
}

uint8_t sd_init(void)
{
	uint8_t r = init_card();

	set_ctl(ctl & ~CTL_SLOW);    /* the OSD runs at full speed even without a card */
	return r;
}

void osd_select(uint8_t on)
{
	set_ctl(on ? ctl | CTL_OSD_SS : ctl & ~CTL_OSD_SS);
}

uint8_t spi_xfer(uint8_t b)
{
	return spi(b);
}

uint8_t sd_read(uint32_t lba, uint8_t *buf)
{
	uint16_t n;
	uint8_t r;

	if (select_wait())
		return 1;
	r = cmd(17, sdhc ? lba : lba << 9, 0x01);
	if (r != 0) {
		deselect();
		return 2;
	}
	for (n = 0; n < 50000; n++) {
		r = spi(0xFF);
		if (r != 0xFF)
			break;
	}
	if (r != 0xFE) {
		deselect();
		return 3;
	}
	for (n = 0; n < 512; n++)
		buf[n] = spi(0xFF);
	spi(0xFF);
	spi(0xFF);
	deselect();
	return 0;
}

uint8_t sd_write(uint32_t lba, const uint8_t *buf)
{
	uint16_t n;
	uint8_t r;

	if (select_wait())
		return 1;
	r = cmd(24, sdhc ? lba : lba << 9, 0x01);
	if (r != 0) {
		deselect();
		return 2;
	}
	spi(0xFF);
	spi(0xFE);
	for (n = 0; n < 512; n++)
		spi(buf[n]);
	spi(0xFF);
	spi(0xFF);
	r = spi(0xFF);
	if ((r & 0x1F) != 0x05) {
		deselect();
		return 3;
	}
	for (n = 0; n < 60000; n++)
		if (spi(0xFF) == 0xFF)
			break;
	deselect();
	return n == 60000 ? 4 : 0;
}
