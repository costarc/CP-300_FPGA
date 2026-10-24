/* Host test for fat.c: the SD card is an image file made by tools/mkfat.py.
 *
 *   gcc -DHOST_TEST -I.. -o host_fat host_fat.c ../fat.c && ./host_fat card.img 7
 *
 * The last argument is the salt-independent check: it recomputes the
 * deterministic test file contents (tools/mkfat.py test_files()).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "fat.h"
#include "sd.h"

static FILE *img;

uint8_t sd_init(void) { return 0; }

uint8_t sd_read(uint32_t lba, uint8_t *buf)
{
	if (fseek(img, (long)lba * 512, SEEK_SET) || fread(buf, 1, 512, img) != 512)
		return 1;
	return 0;
}

uint8_t sd_write(uint32_t lba, const uint8_t *buf)
{
	if (fseek(img, (long)lba * 512, SEEK_SET) || fwrite(buf, 1, 512, img) != 512)
		return 1;
	fflush(img);
	return 0;
}

static int fails;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); fails++; } } while (0)

static void check_file(uint32_t cp300, const char *name11, uint32_t size, uint8_t salt)
{
	dirent_t e;
	file_t f;
	uint8_t buf[512];
	uint32_t n, i, nsec;

	CHECK(dir_find(cp300, name11, &e));
	CHECK(e.size == size);
	file_open(&f, &e);
	nsec = (size + 511) / 512;
	/* forward, then jump back and around to exercise the cluster cache */
	for (n = 0; n < nsec; n++) {
		uint32_t sec = (n % 2) ? nsec - 1 - n / 2 : n / 2;
		if (file_read(&f, sec, buf)) { printf("FAIL read %s sec %u\n", name11, sec); fails++; return; }
		for (i = 0; i < 512 && sec * 512 + i < size; i++)
			if (buf[i] != (uint8_t)((sec * 512 + i) * 7 + salt)) {
				printf("FAIL %s sec %u byte %u\n", name11, sec, i);
				fails++;
				return;
			}
	}
}

int main(int argc, char **argv)
{
	dir_t d;
	dirent_t e, c;
	uint32_t cp300;
	int n = 0;
	uint8_t buf[512], back[512];
	file_t f;

	img = fopen(argv[1], "r+b");
	CHECK(img != NULL);
	CHECK(fat_mount() == 0);

	CHECK(dir_find(fat_root(), "CP300      ", &c));
	CHECK(c.attr & ATTR_DIR);
	cp300 = c.clus;

	dir_open(&d, cp300);
	while (dir_next(&d, &e)) {
		printf("  %.11s attr %02X clus %u size %u\n", e.name, e.attr, e.clus, e.size);
		n++;
	}
	CHECK(n == 6);          /* "." + 5 files; the LFN and deleted entries are skipped */

	check_file(cp300, "TRSDOS13DSK", 40 * 18 * 256, 1);
	check_file(cp300, "LDOS    DSK", 40 * 18 * 256 + 512, 2);
	check_file(cp300, "GAME    CAS", 5000, 3);

	/* in-place write and read back */
	CHECK(dir_find(cp300, "CP300   CFG", &e));
	file_open(&f, &e);
	memset(buf, 0, sizeof buf);
	strcpy((char *)buf, "hello");
	CHECK(file_write(&f, 0, buf) == 0);
	CHECK(file_read(&f, 0, back) == 0);
	CHECK(memcmp(buf, back, 512) == 0);

	printf(fails ? "%d FAILED\n" : "all ok\n", fails);
	return fails != 0;
}
