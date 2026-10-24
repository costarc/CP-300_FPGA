; Start-up for the CP-300 IO controller (Z80, ROM at 0000, RAM at 4000-5FFF)
	.module crt0
	.globl	_main

	.area	_HEADER (ABS)
	.org	0x0000
	di
	ld	sp,#0x6000
	jp	init

	.org	0x0100
	.area	_CODE
init:
	; clear _DATA, then copy the initial values of _INITIALIZED
	ld	hl,#s__DATA
	ld	bc,#l__DATA
	ld	a,b
	or	a,c
	jr	Z,noclear
	ld	(hl),#0
	dec	bc
	ld	a,b
	or	a,c
	jr	Z,noclear
	ld	d,h
	ld	e,l
	inc	de
	ldir
noclear:
	ld	bc,#l__INITIALIZER
	ld	a,b
	or	a,c
	jr	Z,noinit
	ld	de,#s__INITIALIZED
	ld	hl,#s__INITIALIZER
	ldir
noinit:
	call	_main
halt_loop:
	halt
	jr	halt_loop

	.area	_CODE
	.area	_HOME
	.area	_INITIALIZER
	.area	_GSINIT
	.area	_GSFINAL

	.area	_DATA
	.area	_INITIALIZED
	.area	_BSEG
	.area	_BSS
	.area	_HEAP
