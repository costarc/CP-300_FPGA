#ifndef SD_H
#define SD_H

#include <stdint.h>

/* SD card in SPI mode. All return 0 on success. */
uint8_t sd_init(void);
uint8_t sd_read(uint32_t lba, uint8_t *buf);          /* 512 bytes */
uint8_t sd_write(uint32_t lba, const uint8_t *buf);   /* 512 bytes */

/* shared SPI bus: the OSD sits on the same clock and data lines */
void    osd_select(uint8_t on);
uint8_t spi_xfer(uint8_t b);

#endif
