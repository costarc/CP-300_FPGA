/* CP-300 FPGA IO controller firmware: SD card, on-screen menu.
 *
 * F12 opens the menu (PS/2 keys go to the menu, not the CP-300), Up/Down
 * move, Enter selects, Esc closes. Disk images and cassette files are the
 * *.DSK and *.CAS files in /CP300 on the SD card; the selection is kept in
 * /CP300/CP300.CFG when that file exists (it must be at least 512 bytes).
 *
 * No global has an initializer: the RAM is cleared at start-up and the
 * ROM does not carry a copy of the initial values.
 */
#include "hw.h"
#include "sd.h"
#include "fat.h"

#define COLS 32
#define ROWS 8

#define K_UP    1
#define K_DOWN  2
#define K_ENTER 3
#define K_ESC   4
#define K_F12   5
#define K_PGUP  6
#define K_PGDN  7

#define NDRIVES 4
#define MAXLIST 40

#define ST_CLOSED 0
#define ST_MAIN   1
#define ST_BROWSE 2

static char scr[ROWS][COLS];
static uint8_t col[256];
static uint8_t inv_row;              /* row drawn inverted, 0xFF = none */

static uint8_t state;
static uint8_t sd_ok;
static uint8_t sd_err;
static uint32_t cp300_dir;
static uint8_t have_dir;

/* mounted images, 8.3 names, blank = empty: drives 0-3, then the cassette */
static char mount_name[NDRIVES + 1][11];
static file_t cfg_file;
static uint8_t cfg_ok;

static uint8_t sel;                  /* main menu selection, 0..5 */
static uint8_t browse_target;        /* 0-3 drive, 4 cassette */
static char list[MAXLIST][11];
static uint8_t nlist;
static uint8_t cursor;
static uint8_t top;

static uint8_t sector[512];

/* floppy drives: the image file behind each drive */
static file_t drive_file[NDRIVES];
static uint8_t drive_ok[NDRIVES];

static const char cfg_magic[] = "C3";
static const char ext_dsk[] = "DSK";
static const char ext_cas[] = "CAS";
static const char dirname_cp300[] = "CP300      ";
static const char cfgname[] = "CP300   CFG";

/* ---- OSD ---------------------------------------------------------- */

static void osd_cmd(uint8_t c)
{
	osd_select(1);
	spi_xfer(c);
	osd_select(0);
}

static void draw_line(uint8_t r)
{
	uint8_t c, x;
	uint8_t *p = col;
	uint8_t flip = (r == inv_row) ? 0xFF : 0;

	for (c = 0; c < COLS; c++) {
		GLYPH_SEL = (uint8_t)scr[r][c];
		for (x = 0; x < 8; x++)
			*p++ = GLYPH_ROW ^ flip;
	}
	osd_select(1);
	spi_xfer(0x20 | r);
	for (c = 0; c < 255; c++)
		spi_xfer(col[c]);
	spi_xfer(col[255]);
	osd_select(0);
}

/* what the OSD currently shows; only changed rows are sent */
static char shown[ROWS][COLS];
static uint8_t shown_inv;
static uint8_t shown_valid;

static void osd_show(void)
{
	uint8_t r, c, same;

	for (r = 0; r < ROWS; r++) {
		same = shown_valid && ((r == inv_row) == (r == shown_inv));
		for (c = 0; same && c < COLS; c++)
			if (scr[r][c] != shown[r][c])
				same = 0;
		if (same)
			continue;
		draw_line(r);
		for (c = 0; c < COLS; c++)
			shown[r][c] = scr[r][c];
	}
	shown_inv = inv_row;
	shown_valid = 1;
	osd_cmd(0x41);
}

static void osd_hide(void)
{
	osd_cmd(0x40);
	shown_valid = 0;
}

static void clear_screen(void)
{
	uint8_t r, c;

	for (r = 0; r < ROWS; r++)
		for (c = 0; c < COLS; c++)
			scr[r][c] = ' ';
	inv_row = 0xFF;
}

static void put(uint8_t r, uint8_t c, const char *s)
{
	while (*s && c < COLS)
		scr[r][c++] = *s++;
}

/* "NAME    EXT" -> "NAME.EXT" */
static void fmt_name(char *dst, const char *n)
{
	uint8_t i, k = 0;

	if (n[0] == ' ') {
		for (i = 0; i < 7; i++)
			dst[i] = "(empty)"[i];
		dst[7] = 0;
		return;
	}
	for (i = 0; i < 8 && n[i] != ' '; i++)
		dst[k++] = n[i];
	if (n[8] != ' ') {
		dst[k++] = '.';
		for (i = 8; i < 11 && n[i] != ' '; i++)
			dst[k++] = n[i];
	}
	dst[k] = 0;
}

/* ---- keyboard ------------------------------------------------------ */

static uint8_t key_ext, key_brk;

static uint8_t key_get(void)
{
	uint8_t b, k;

	while (KBD_STAT & 1) {
		b = KBD_DATA;
		DBG = b;                 /* last raw PS/2 byte on the LEDs */
		if (b == 0xE0) { key_ext = 1; continue; }
		if (b == 0xF0) { key_brk = 1; continue; }
		k = 0;
		if (!key_brk) {
			if (key_ext) {
				if (b == 0x75) k = K_UP;
				else if (b == 0x72) k = K_DOWN;
				else if (b == 0x7D) k = K_PGUP;
				else if (b == 0x7A) k = K_PGDN;
				else if (b == 0x5A) k = K_ENTER;      /* keypad enter */
			} else {
				if (b == 0x5A) k = K_ENTER;
				else if (b == 0x76) k = K_ESC;
				else if (b == 0x07) k = K_F12;
			}
		}
		key_ext = 0;
		key_brk = 0;
		if (k)
			return k;
	}
	return 0;
}

/* ---- SD card and configuration ------------------------------------ */

static void cfg_load(void)
{
	uint8_t i, k;
	dirent_t e;

	cfg_ok = 0;
	for (i = 0; i <= NDRIVES; i++)
		for (k = 0; k < 11; k++)
			mount_name[i][k] = ' ';
	if (!dir_find(cp300_dir, cfgname, &e) || e.size < 512)
		return;
	file_open(&cfg_file, &e);
	cfg_ok = 1;
	if (file_read(&cfg_file, 0, sector))
		return;
	if (sector[0] != cfg_magic[0] || sector[1] != cfg_magic[1])
		return;
	for (i = 0; i <= NDRIVES; i++)
		for (k = 0; k < 11; k++)
			mount_name[i][k] = sector[2 + i * 11 + k];
}

static void cfg_save(void)
{
	uint8_t i, k;
	uint16_t n;

	if (!cfg_ok)
		return;
	for (n = 0; n < 512; n++)
		sector[n] = 0;
	sector[0] = cfg_magic[0];
	sector[1] = cfg_magic[1];
	for (i = 0; i <= NDRIVES; i++)
		for (k = 0; k < 11; k++)
			sector[2 + i * 11 + k] = mount_name[i][k];
	file_write(&cfg_file, 0, sector);
}

/* tell the floppy controller what is in drive d */
static void mount_drive(uint8_t d)
{
	dirent_t e;
	uint8_t flags = d;

	drive_ok[d] = 0;
	if (have_dir && mount_name[d][0] != ' ' && dir_find(cp300_dir, mount_name[d], &e)) {
		file_open(&drive_file[d], &e);
		drive_ok[d] = 1;
		flags |= 0x04;
		if (e.attr & 0x01)
			flags |= 0x08;
		if (e.size > 368640UL)          /* more than 80 x 18 x 256: two sided */
			flags |= 0x10;
	}
	DRV_FLAGS = flags;
}

/* answer a block request of the floppy controller */
static void fdc_service(void)
{
	uint8_t req = FDC_REQ;
	uint8_t d;
	uint16_t n;
	uint32_t blk;

	if (!(req & 3))
		return;
	d = (req >> 3) & 3;
	blk = FDC_LBA_HI;
	blk = (blk << 8) | FDC_LBA_LO;
	if (req & 1) {
		if (!drive_ok[d] || file_read(&drive_file[d], blk, sector))
			for (n = 0; n < 512; n++)
				sector[n] = 0;
		FDC_ACK = 1;
		for (n = 0; n < 512; n++)
			FDC_BUF = sector[n];
		FDC_ACK = 0;
	} else {
		FDC_ACK = 1;
		for (n = 0; n < 512; n++)
			sector[n] = FDC_BUF;
		FDC_ACK = 0;
		if (drive_ok[d] && !(drive_file[d].size == 0))
			file_write(&drive_file[d], blk, sector);
	}
}

static void card_start(void)
{
	dirent_t e;
	uint8_t i;

	sd_ok = 0;
	have_dir = 0;
	sd_err = sd_init();
	if (sd_err)
		return;
	sd_err = fat_mount();
	if (sd_err) {
		sd_err += 10;
		return;
	}
	sd_ok = 1;
	if (dir_find(fat_root(), dirname_cp300, &e) && (e.attr & ATTR_DIR)) {
		cp300_dir = e.clus;
		have_dir = 1;
		cfg_load();
		for (i = 0; i < NDRIVES; i++)
			mount_drive(i);
	}
}

/* ---- screens -------------------------------------------------------- */

static void draw_main(void)
{
	uint8_t i;
	char nm[13];

	clear_screen();
	put(0, 1, "CP-300 FPGA");
	for (i = 0; i < NDRIVES; i++) {
		scr[1 + i][1] = 'D';
		scr[1 + i][2] = 'R';
		scr[1 + i][3] = 'I';
		scr[1 + i][4] = 'V';
		scr[1 + i][5] = 'E';
		scr[1 + i][7] = '0' + i;
		scr[1 + i][8] = ':';
		fmt_name(nm, mount_name[i]);
		put(1 + i, 10, nm);
	}
	put(5, 1, "CASSETTE:");
	fmt_name(nm, mount_name[NDRIVES]);
	put(5, 11, nm);
	put(6, 1, "RESET CP-300");
	if (!sd_ok) {
		put(7, 1, "NO SD CARD, ERROR ");
		scr[7][19] = '0' + sd_err / 10;
		scr[7][20] = '0' + sd_err % 10;
	} else if (!have_dir) {
		put(7, 1, "NO /CP300 DIRECTORY");
	} else {
		put(7, 1, "ENTER SELECT  ESC CLOSE");
	}
	inv_row = 1 + sel;
	osd_show();
}

static void list_build(uint8_t target)
{
	dir_t d;
	dirent_t e;
	const char *ext = (target == NDRIVES) ? ext_cas : ext_dsk;
	uint8_t k;

	nlist = 0;
	for (k = 0; k < 11; k++)
		list[0][k] = ' ';
	nlist = 1;                           /* entry 0 ejects */
	if (!have_dir)
		return;
	dir_open(&d, cp300_dir);
	while (nlist < MAXLIST && dir_next(&d, &e)) {
		if ((e.attr & ATTR_DIR) || e.name[8] != ext[0] || e.name[9] != ext[1] || e.name[10] != ext[2])
			continue;
		for (k = 0; k < 11; k++)
			list[nlist][k] = e.name[k];
		nlist++;
	}
}

static void draw_browse(void)
{
	uint8_t r, i;
	char nm[13];

	clear_screen();
	if (browse_target == NDRIVES) {
		put(0, 1, "SELECT CASSETTE FILE");
	} else {
		put(0, 1, "SELECT DISK FOR DRIVE");
		scr[0][23] = '0' + browse_target;
	}
	for (r = 0; r < 6; r++) {
		i = top + r;
		if (i >= nlist)
			break;
		if (i == 0)
			put(1 + r, 1, "(EJECT)");
		else {
			fmt_name(nm, list[i]);
			put(1 + r, 1, nm);
		}
	}
	put(7, 1, "ENTER SELECT  ESC BACK");
	inv_row = 1 + (cursor - top);
	osd_show();
}

static void open_menu(void)
{
	if (!sd_ok)
		card_start();
	CTRL = CTRL_MENU;
	state = ST_MAIN;
	draw_main();
}

static void close_menu(void)
{
	osd_hide();
	CTRL = 0;
	state = ST_CLOSED;
}

static void do_reset(void)
{
	uint16_t n;

	CTRL = CTRL_MENU | CTRL_RESET;
	for (n = 0; n < 60000; n++)
		;
	CTRL = 0;
}

static void main_key(uint8_t k)
{
	switch (k) {
	case K_UP:
		if (sel)
			sel--;
		break;
	case K_DOWN:
		if (sel < NDRIVES + 1)
			sel++;
		break;
	case K_ESC:
	case K_F12:
		close_menu();
		return;
	case K_ENTER:
		if (sel == NDRIVES + 1) {
			close_menu();
			do_reset();
			return;
		}
		if (!have_dir)
			break;
		browse_target = sel;
		list_build(sel);
		cursor = 0;
		top = 0;
		state = ST_BROWSE;
		draw_browse();
		return;
	}
	draw_main();
}

static void browse_key(uint8_t k)
{
	uint8_t j;

	switch (k) {
	case K_UP:
		if (cursor)
			cursor--;
		break;
	case K_DOWN:
		if (cursor + 1 < nlist)
			cursor++;
		break;
	case K_PGUP:
		cursor = cursor > 6 ? cursor - 6 : 0;
		break;
	case K_PGDN:
		cursor = cursor + 6 < nlist ? cursor + 6 : nlist - 1;
		break;
	case K_F12:
		close_menu();
		return;
	case K_ESC:
		state = ST_MAIN;
		draw_main();
		return;
	case K_ENTER:
		for (j = 0; j < 11; j++)
			mount_name[browse_target][j] = list[cursor][j];
		if (browse_target < NDRIVES)
			mount_drive(browse_target);
		cfg_save();
		state = ST_MAIN;
		draw_main();
		return;
	}
	if (cursor < top)
		top = cursor;
	if (cursor >= top + 6)
		top = cursor - 5;
	draw_browse();
}

void main(void)
{
	uint8_t k;

	DBG = 0x01;
	card_start();
	/* LEDs: b0 card ok, b1 /CP300 found, b2 CP300.CFG found, b7:3 error code */
	DBG = sd_ok | (have_dir << 1) | (cfg_ok << 2) | (sd_err << 3);
	CTRL = 0;                /* release the CP-300, it has been held in reset since power-on */
	for (;;) {
		fdc_service();
		k = key_get();
		if (!k)
			continue;
		switch (state) {
		case ST_CLOSED:
			if (k == K_F12)
				open_menu();
			break;
		case ST_MAIN:
			main_key(k);
			break;
		default:
			browse_key(k);
			break;
		}
	}
}
