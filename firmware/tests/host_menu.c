/* Host test of the menu logic in main.c with a scripted keyboard and the card image.
 *   gcc -DHOST_TEST -I.. -o host_menu host_menu.c ../fat.c && ./host_menu card.img */
#include <stdio.h>
#include "hw.h"
static uint8_t host_ctrl, glyph_sel;
static const uint8_t script[] = { 0x07,0xF0,0x07, 0xE0,0x72,0xE0,0xF0,0x72, 0xE0,0x72,0xE0,0xF0,0x72,
                                  0x5A,0xF0,0x5A, 0xE0,0x72,0xE0,0xF0,0x72, 0x5A,0xF0,0x5A, 0x76,0xF0,0x76 };
static unsigned pos;
#define KBD_STAT (pos < sizeof script)
#define KBD_DATA (script[pos++])
#define CTRL host_ctrl
#define GLYPH_SEL glyph_sel
#define GLYPH_ROW 0
static unsigned osd_lines, osd_en;
void osd_select(uint8_t on) { (void)on; }
uint8_t spi_xfer(uint8_t b) { if ((b & 0xF0) == 0x20) osd_lines++; if (b == 0x41) osd_en++; if (b == 0x40) osd_en = 0; return 0; }
#define main app_main
#include "../main.c"
#undef main
#include "../fat.h"

int main(int argc, char **argv)
{
	extern FILE *img_file;
	(void)argc; (void)argv;
	card_start();
	printf("sd_ok=%d have_dir=%d err=%d\n", sd_ok, have_dir, sd_err);
	while (pos < sizeof script) {
		uint8_t k = key_get();
		if (!k) continue;
		printf("key %d state %d -> ", k, state);
		switch (state) {
		case ST_CLOSED: if (k == K_F12) open_menu(); break;
		case ST_MAIN: main_key(k); break;
		default: browse_key(k); break;
		}
		printf("state %d ctrl %d sel %d cursor %d\n", state, host_ctrl, sel, cursor);
	}
	printf("drive1=[%.11s] osd lines drawn %u\n", mount_name[1], osd_lines);
	return 0;
}
