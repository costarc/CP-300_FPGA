/* CP-300 FPGA IO controller firmware: SD card, ROM loading, on-screen menu.
 *
 * The system ROM (a *.ROM file, 14 or 16 KB, the machine) and the character generator
 * (CHARGEN.BIN, 2 KB) are read from /CP300 on the SD card into the core's ROM RAMs while the
 * CP-300 is held in reset. The machine is chosen in the menu (CP300.ROM, CP500.ROM ...).
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
#include "dmk.h"

#define COLS 32
#define ROWS 16                /* the 16 line OSD: square pixels, 8 x 8 characters */
#define LISTROWS 12            /* file names shown at once */

#define K_UP    1
#define K_DOWN  2
#define K_ENTER 3
#define K_ESC   4
#define K_F12   5
#define K_PGUP  6
#define K_PGDN  7

#define NDRIVES 4
#define MACH    (NDRIVES + 1)          /* slot of the machine ROM file */
#define NSLOT   (NDRIVES + 2)          /* mounted names kept: drives, cassette, machine */
#define NITEMS  (NDRIVES + 3)          /* menu items: slots, then reset */
#define ITEM_RESET (NDRIVES + 2)
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
static char mount_name[NSLOT][11];
static file_t cfg_file;
static uint8_t cfg_ok;

static uint8_t sel;                  /* main menu selection, 0..6 */
/* screen row of the selectable items: drives 0-3, cassette, machine, reset */
static const uint8_t item_row[NITEMS] = { 2, 3, 4, 5, 7, 8, 10 };
static uint8_t browse_target;        /* 0-3 drive, 4 cassette, 5 machine */

/* ROM load state */
static uint8_t rom_ok;
static uint8_t rom_err;              /* 1 no ROM file, 2 SD read error, 3 no CHARGEN.BIN, 4 ROM too small */
static char rom_name[11];
static char list[MAXLIST][11];
static uint8_t nlist;
static uint8_t cursor;
static uint8_t top;

static uint8_t sector[512];

/* floppy drives: the DMK image behind each drive */
static dmk_t drive[NDRIVES];
static uint8_t drive_ok[NDRIVES];

static const char cfg_magic[] = "C3";
static const char ext_dsk[] = "DSK";
static const char ext_cas[] = "CAS";
static const char ext_rom[] = "ROM";
static const char name_rom[] = "CP300   ROM";
static const char name_chargen[] = "CHARGEN BIN";
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
	for (i = 0; i < NSLOT; i++)
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
	for (i = 0; i < NSLOT; i++)
		for (k = 0; k < 11; k++)
			mount_name[i][k] = sector[2 + i * 11 + k] ? sector[2 + i * 11 + k] : ' ';
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
	for (i = 0; i < NSLOT; i++)
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
	dmk_forget(&drive[d]);
	if (have_dir && mount_name[d][0] != ' ' && dir_find(cp300_dir, mount_name[d], &e) &&
	    dmk_open(&drive[d], &e)) {
		drive_ok[d] = 1;
		flags |= 0x04;
		if ((e.attr & 0x01) || drive[d].readonly)
			flags |= 0x08;
	}
	DRV_FLAGS = flags;
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

/* copy size bytes of a file to the core's ROM RAM (target 0) or character generator (1) */
static uint8_t rom_push(const dirent_t *e, uint8_t target, uint16_t size)
{
	file_t f;
	uint16_t i, s;

	file_open(&f, e);
	ROM_CTL = target;
	for (s = 0; s * 512 < size; s++) {
		if (file_read(&f, s, sector))
			return 1;
		for (i = 0; i < 512; i++)
			ROM_DATA = sector[i];
	}
	return 0;
}

/* the machine: the chosen ROM file, else CP300.ROM, else the first *.ROM */
static uint8_t find_rom(dirent_t *e)
{
	dir_t d;
	uint8_t k;

	if (mount_name[MACH][0] != ' ' && dir_find(cp300_dir, mount_name[MACH], e))
		return 1;
	if (dir_find(cp300_dir, name_rom, e))
		return 1;
	dir_open(&d, cp300_dir);
	while (dir_next(&d, e))
		if (!(e->attr & ATTR_DIR) && e->name[8] == ext_rom[0] && e->name[9] == ext_rom[1] && e->name[10] == ext_rom[2])
			return 1;
	for (k = 0; k < 11; k++)
		e->name[k] = ' ';
	return 0;
}

/* load the machine ROM and the character generator; the core must be in reset */
static void rom_load(void)
{
	dirent_t e;
	uint8_t k;

	rom_ok = 0;
	rom_err = 0;
	for (k = 0; k < 11; k++)
		rom_name[k] = ' ';
	if (!have_dir || !find_rom(&e))
		rom_err = 1;
	else if (e.size < 14336)
		rom_err = 4;
	else if (rom_push(&e, 0, e.size < 16384 ? (uint16_t)e.size : 16384))
		rom_err = 2;
	else {
		for (k = 0; k < 11; k++)
			rom_name[k] = e.name[k];
		if (!dir_find(cp300_dir, name_chargen, &e) || e.size < 2048)
			rom_err = 3;
		else if (rom_push(&e, 1, 2048))
			rom_err = 2;
	}
	rom_ok = !rom_err;
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
		put(item_row[i], 1, "DRIVE");
		scr[item_row[i]][7] = '0' + i;
		scr[item_row[i]][8] = ':';
		fmt_name(nm, mount_name[i]);
		put(item_row[i], 10, nm);
	}
	put(item_row[NDRIVES], 1, "CASSETTE:");
	fmt_name(nm, mount_name[NDRIVES]);
	put(item_row[NDRIVES], 11, nm);
	put(item_row[MACH], 1, "MACHINE:");
	if (mount_name[MACH][0] == ' ')
		put(item_row[MACH], 10, "(DEFAULT)");
	else {
		fmt_name(nm, mount_name[MACH]);
		put(item_row[MACH], 10, nm);
	}
	put(item_row[ITEM_RESET], 1, "RESET CP-300");
	if (rom_ok) {
		put(12, 1, "ROM:");
		fmt_name(nm, rom_name);
		put(12, 6, nm);
	}
	if (!sd_ok) {
		put(14, 1, "NO SD CARD, ERROR ");
		scr[14][19] = '0' + sd_err / 10;
		scr[14][20] = '0' + sd_err % 10;
	} else if (!have_dir) {
		put(14, 1, "NO /CP300 DIRECTORY");
	} else if (rom_err) {
		put(14, 1, rom_err == 1 ? "NO .ROM FILE IN /CP300" :
		           rom_err == 3 ? "NO CHARGEN.BIN" :
		           rom_err == 4 ? "ROM FILE TOO SMALL" : "ROM READ ERROR");
	}
	put(15, 1, "ENTER SELECT  ESC CLOSE");
	inv_row = item_row[sel];
	osd_show();
}

static void list_build(uint8_t target)
{
	dir_t d;
	dirent_t e;
	const char *ext = (target == NDRIVES) ? ext_cas : (target == MACH) ? ext_rom : ext_dsk;
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
	if (browse_target == MACH) {
		put(0, 1, "SELECT MACHINE (ROM)");
	} else if (browse_target == NDRIVES) {
		put(0, 1, "SELECT CASSETTE FILE");
	} else {
		put(0, 1, "SELECT DISK FOR DRIVE");
		scr[0][23] = '0' + browse_target;
	}
	for (r = 0; r < LISTROWS; r++) {
		i = top + r;
		if (i >= nlist)
			break;
		if (i == 0)
			put(2 + r, 1, browse_target == MACH ? "(DEFAULT)" : "(EJECT)");
		else {
			fmt_name(nm, list[i]);
			put(2 + r, 1, nm);
		}
	}
	put(15, 1, "ENTER SELECT  ESC BACK");
	inv_row = 2 + (cursor - top);
	osd_show();
}

static void open_menu(void)
{
	if (!sd_ok)
		card_start();
	CTRL = CTRL_MENU | (rom_ok ? 0 : CTRL_RESET);
	state = ST_MAIN;
	draw_main();
}

static void close_menu(void)
{
	osd_hide();
	CTRL = rom_ok ? 0 : CTRL_RESET;      /* without a ROM the CP-300 stays in reset */
	state = ST_CLOSED;
}

static void do_reset(void)
{
	uint16_t n;

	CTRL = CTRL_MENU | CTRL_RESET;
	for (n = 0; n < 60000; n++)
		;
	rom_load();                          /* the machine may have changed */
	CTRL = rom_ok ? 0 : CTRL_RESET;
}

static void main_key(uint8_t k)
{
	switch (k) {
	case K_UP:
		if (sel)
			sel--;
		break;
	case K_DOWN:
		if (sel < ITEM_RESET)
			sel++;
		break;
	case K_ESC:
	case K_F12:
		close_menu();
		return;
	case K_ENTER:
		if (sel == ITEM_RESET) {
			do_reset();
			close_menu();
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
		cursor = cursor > LISTROWS ? cursor - LISTROWS : 0;
		break;
	case K_PGDN:
		cursor = cursor + LISTROWS < nlist ? cursor + LISTROWS : nlist - 1;
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
	if (cursor >= top + LISTROWS)
		top = cursor - LISTROWS + 1;
	draw_browse();
}

void main(void)
{
	uint8_t k;

	DBG = 0x01;
	dmk_init();
	card_start();
	if (have_dir)
		rom_load();
	/* LEDs: b0 card ok, b1 /CP300 found, b2 CP300.CFG found, b7:3 error code (SD, or 16 + ROM) */
	DBG = sd_ok | (have_dir << 1) | (cfg_ok << 2) | ((sd_err ? sd_err : rom_err ? 16 + rom_err : 0) << 3);
	CTRL = rom_ok ? 0 : CTRL_RESET;   /* release the CP-300 (held in reset since power-on) only with a ROM */
	if (!rom_ok)
		open_menu();
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
