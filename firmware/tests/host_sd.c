#include <stdio.h>
#include <stdint.h>
#include "sd.h"
FILE *img_file;
uint8_t sd_init(void) { img_file = fopen("card_host.img", "r+b"); return img_file ? 0 : 1; }
uint8_t sd_read(uint32_t lba, uint8_t *buf) { return fseek(img_file, (long)lba * 512, SEEK_SET) || fread(buf, 1, 512, img_file) != 512; }
uint8_t sd_write(uint32_t lba, const uint8_t *buf) { return fseek(img_file, (long)lba * 512, SEEK_SET) || fwrite(buf, 1, 512, img_file) != 512; }
