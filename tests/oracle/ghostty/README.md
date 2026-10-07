# Ghostty sprite oracle

`sprite/` holds the 36 reference PNGs of Ghostty's sprite font (78,166 bytes), copied unchanged from
`src/font/sprite/testdata/` at Ghostty commit `a3010543b0c39b98a81ace9f50b1910ae641c8c1`
(2026-09-19). The files are MIT-licensed test data; `LICENSE` is Ghostty's.

Each file is `U+XXXX...U+XXXX-WxH+T.png`: one range of 256 codepoints in a 16x16 grid of padded
cells (padding `W/4` by `H/4` on every side), for a cell of W x H pixels with a line thickness of T.
The four cell sizes are 18x36+4, 12x24+3, 11x21+2 and 9x17+1. A cell is 8-bit gray, 255 where
Ghostty draws ink.

`src/test/spriteOracleCheck.ms` draws the same cells through `src/void2d/spriteGlyph.c` and compares
them. Only the buckets U+2500, U+2800, U+E000, U+1CD00 and U+1FB00 are read: the 16 files of U+1CC00,
U+1CE00, U+F500 and U+F600 (16,894 bytes) back sprites that are not ported and are kept so the
copy of the directory stays whole. Nothing here is linked or read by the renderer. To refresh, copy the directory again from a
Ghostty checkout and record its commit above.
