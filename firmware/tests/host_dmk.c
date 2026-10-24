/* Host test of dmk.c on real DMK images inside a FAT image:
 *   HOST_IMG=card.img ./host_dmk NAME11 [NAME11 ...]
 * Prints "T S ID flags sum" for every 256-byte sector found (trkreg = track), then the
 * READ ADDRESS sequence of track 5 side 0 ("RA c h r n"). tools/test_dmk.py compares this with
 * its own decoding of the same files.
 */
#include <stdio.h>
#include <string.h>
#include "dmk.h"
#include "sd.h"

static dmk_t d;
extern unsigned sd_reads, sd_writes;

int main(int argc, char **argv)
{
	uint8_t buf[512];
	dirent_t e;
	uint32_t dir;
	int i, t, s, sec;

	dmk_init();
	if (sd_init() || fat_mount()) { puts("mount failed"); return 1; }
	if (!dir_find(fat_root(), "CP300      ", &e)) { puts("no /CP300"); return 1; }
	dir = e.clus;
	for (i = 1; i < argc; i++) {
		if (!dir_find(dir, argv[i], &e)) { printf("FILE %s missing\n", argv[i]); continue; }
		if (!dmk_open(&d, &e)) { printf("FILE %s not a DMK\n", argv[i]); continue; }
		printf("FILE %s tracks %d sides %d tlen %d doubled %d\n", argv[i], d.ntracks, d.nsides, d.tlen, d.doubled);
		for (t = 0; t < d.ntracks; t++)
			for (s = 0; s < d.nsides; s++)
				for (sec = 0; sec < 40; sec++) {
					uint8_t fl = dmk_read_sector(&d, t, s, t, sec, buf);
					if (fl) {
						unsigned sum = 0;
						int j;
						for (j = 0; j < 256; j++) sum += buf[j];
						printf("%d %d %d %d %u\n", t, s, sec, fl, sum);
					}
				}
		/* write a pattern into the first sector of tracks 0 and 5 (single and double density), as
		 * normal and as deleted data, and read it back with its CRC checked */
		for (t = 0; t < 6; t += 5) {
			uint8_t id[6], w[256], r[256];
			int j, ok;
			d.cvalid = 0; d.ra_next = 0;
			if (!dmk_read_address(&d, t, 0, id)) continue;
			if (!dmk_read_sector(&d, t, 0, id[0], id[2], r)) continue;   /* a 256-byte sector only */
			for (ok = 0; ok < 2; ok++) {
				uint8_t fl;
				for (j = 0; j < 256; j++) w[j] = (uint8_t)(j * 7 + t + ok);
				fl = dmk_write_sector(&d, t, 0, id[0], id[2], w, ok) ? 1 : 0;
				dmk_forget(&d);                      /* drop the cache: read it back from the image file */
				fl = fl ? dmk_read_sector(&d, t, 0, id[0], id[2], r) : 0;
				printf("WRITE t%d id%d deleted%d -> flags %d data %s\n", t, id[2], ok, fl,
				       (fl & 1) && !memcmp(w, r, 256) ? "same" : "DIFFERENT");
			}
		}
		{
			uint8_t r[256];
			unsigned a;
			d.cvalid = 0; dmk_forget(&d);
			a = sd_reads; dmk_read_sector(&d, 5, 0, 5, 3, r);
			printf("COST first read of track 5 sector 3: %u SD reads\n", sd_reads - a);
			a = sd_reads; dmk_read_sector(&d, 5, 0, 5, 3, r);
			printf("COST same sector again: %u SD reads\n", sd_reads - a);
			a = sd_reads; dmk_read_sector(&d, 5, 0, 5, 10, r);
			printf("COST sector 10 of the same track: %u SD reads\n", sd_reads - a);
			a = sd_reads; dmk_read_sector(&d, 20, 0, 20, 2, r);
			printf("COST sector 2 of track 20: %u SD reads\n", sd_reads - a);
		}
		for (t = 0; t < 8; t++) {
			uint8_t id[6];
			if (dmk_read_address(&d, 5, 0, id))
				printf("RA %d %d %d %d\n", id[0], id[1], id[2], id[3]);
		}
	}
	return 0;
}
