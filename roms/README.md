# ROMs

ROM images are copyrighted and are not part of this repository.

`boot.hex` is the image synthesized into the FPGA (M9K, 14 KB, 0000-37FF). Create it with:

```
python tools/rom2hex.py              # built-in test ROM: prints a message, no Tandy code
python tools/rom2hex.py <image.rom>  # a real ROM image
```

Then recompile `syn/de0`.

| Phase | ROM to use |
|---|---|
| 1 (HT1080Z port) | The HT-1080Z ROM used by the MiST core (its tape routines read port 04h), or a Model I Level II ROM |
| 2+ (CP-300) | Dumps from a real CP-300: the 14 KB system ROM and the 2 KB character generator |
