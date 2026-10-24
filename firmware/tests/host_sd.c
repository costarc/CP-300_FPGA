#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include "sd.h"
FILE *img_file;
unsigned sd_reads, sd_writes;
uint8_t sd_init(void) { img_file = fopen(getenv("HOST_IMG") ? getenv("HOST_IMG") : "card_host.img", "r+b"); return img_file ? 0 : 1; }
uint8_t sd_read(uint32_t lba, uint8_t *buf) { sd_reads++; return fseek(img_file, (long)lba * 512, SEEK_SET) || fread(buf, 1, 512, img_file) != 512; }
uint8_t sd_write(uint32_t lba, const uint8_t *buf) { sd_writes++; return fseek(img_file, (long)lba * 512, SEEK_SET) || fwrite(buf, 1, 512, img_file) != 512; }
