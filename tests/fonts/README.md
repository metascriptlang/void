# Test fonts

`NotoSansSC-subset.ttf` is the CJK face the fallback chain is tested against (`text/cjkFallback`,
`src/test/fontFallbackCheck.ms`). It is not a font for applications: void2d loads real CJK and
emoji families from the host on a miss (docs/VOID2D.md "Text").

Built from `ofl/notosanssc/NotoSansSC[wght].ttf` at google/fonts `2894aab31764`, licensed
under the SIL Open Font License 1.1 (`NotoSansSC-OFL.txt`; the reserved name is "Source",
which this subset does not use):

```sh
python tests/fonts/notoSansScChars.py        # writes unicodes.txt: 504 common hanzi,
                                             # ASCII, CJK punctuation, fullwidth forms
python -m fontTools.varLib.instancer "NotoSansSC[wght].ttf" wght=400 --update-name-table -o NotoSansSC-400.ttf
python -m fontTools.subset NotoSansSC-400.ttf --unicodes-file=unicodes.txt \
    --output-file=NotoSansSC-subset.ttf --layout-features='*' --name-IDs='*' --name-legacy --no-hinting
```

The weight axis is pinned because stb_truetype reads the default instance of a variable font,
which for this family is Thin (100).

`zeroedDecorations.ttf` and `zeroThickness.ttf` are two- and three-glyph subsets of Inter
(`assets/font.ttf`, OFL, no reserved name) with their decoration tables broken on purpose, for
the fallback rule in `src/test/faceCheck.ms`: the first has `post` and the `OS/2` strikeout zeroed
and `OS/2` cut to version 1, so the ex height is measured from `x`; the second keeps the
positions, zeroes the thicknesses and the `OS/2` heights, so the estimate starts from the ascent.
`zeroLineHeight.ttf` is an `H`-only subset whose `hhea` ascent, descent and line gap are 0, for
the `sizeAdjust` guard in `src/test/fontCheck.ms`. `python tests/fonts/brokenTables.py` rebuilds
all three from `assets/font.ttf`; fontTools stamps `head.modified`, so a rebuild is not
byte-identical.

`NotoColorEmoji-subset.ttf` (17,172 B) is the colour-emoji face the P6 emoji module is tested
against: a CBDT/CBLC font with no `glyf` or `CFF`, so stb_truetype cannot load it and only the
cmap, metrics and strike tables are read. It is Noto Color Emoji cut to U+1F600, 1F44D, 2764,
1F680, 1F389, 23, FE0F and 200D with the layout features dropped (one 109 ppem strike), from the
10,730,124 B `2D/fonts/NotoColorEmoji.ttf` at googlefonts/noto-emoji `main`, SIL Open Font
License 1.1 (`NotoColorEmoji-OFL.txt`, copyright Google LLC, no reserved font name).

`textSymbol.ttf` (744 B), `cbdtSynthetic.ttf` (1,236 B), `sbixSynthetic.ttf` (1,344 B) and
`colrSynthetic.ttf` (884 B) are synthetic faces with our own art, no third-party licence:
`textSymbol` holds outline boxes for U+1F600 and U+2764 (the text-presentation face);
`cbdtSynthetic` holds two CBDT strikes (8 and 16 ppem, format 17 PNG), a cmap 12 and a cmap 14
with VS16 for both codepoints, and no outlines; `sbixSynthetic` holds 12 and 24 ppem strikes
with origin offsets, a `dupe` glyph, a `jpg ` glyph and an empty glyph; `colrSynthetic` holds a
COLR v0 glyph of three layers over a three-colour CPAL palette.

`symbolCollection.ttc` (1,968 B) holds `textSymbol` then `cbdtSynthetic`: the sfnt peek must read
the first font of a collection, which is the drawable one.

```sh
python tests/fonts/colourEmoji.py NotoColorEmoji.ttf   # rewrites the faces above
```

The generator pins `head.created` and `head.modified`, so a re-run is byte-identical.

`cmap/*.ttf` and `cmap/*.ttc` are byte-built sfnt files with a hand-assembled `cmap` and
placeholder tables, for the sfnt peek (`src/void2d/sfnt.c`): a control per format, cmaps whose
offsets, counts or length run outside their table, truncated cmaps, and a directory entry or
collection offset that wraps 32 bits (`src/test/sfntBoundsCheck.ms`); one font per cmap format
(0, 4, 6, 12, 13 and two it does not read), per record order that decides which subtable is
chosen, and per variation-sequence record shape (`src/test/sfntCmapCheck.ms`).
`cmap/coversButUnloadable.otf` is an OpenType font whose cmap covers U+1F600 and whose `CFF `
holds Type 1 charstrings: the peek calls it drawable and stb_truetype refuses it (`src/test/fontCheck.ms`).

`cmap/joiners.ttf` is a drawable face whose only glyphs are U+200D and U+FE0F, for the rule
that a joiner or selector loads no fallback face of its own (`src/test/fontCheck.ms`).

```sh
python tests/fonts/cmapEdges.py   # rewrites tests/fonts/cmap/; no fontTools needed, byte-identical
```

`cffSynthetic.otf` (692 B) is a synthetic CFF face with our own art, no third-party licence: `A` is one cubic curve, `B` a box of lines, for the SDF regime's cubic fallback (`src/test/labelTextSdfCheck.ms`); `python tests/fonts/cffSynthetic.py` rebuilds it.

`shapeFixture.ttf` (1,548 B) is the face the shaper is pinned against (P6, `docs/VOID2D.md`
"Shaper module"), our own boxes and no third-party licence. Programming-font ligatures are all
`calt`, one glyph in and one out, so only a font built for it exercises the other mechanisms
deterministically: `liga` `f i` to one glyph (many to one), `calt` `a b` to `b.alt` (one to one),
`ccmp` U+00E9 to `e` plus a combining mark (one to many), a `kern` pair `A V` of -100, and `mark`
attaching U+0301 to `e` with a non-zero y offset. `python tests/fonts/shapeFixture.py` rebuilds it
byte for byte (the generator pins `head.created` and `head.modified`).

`cascadiaSubset.ttf` (48,064 B) is Cascadia Code `v2407.24` (microsoft/cascadia-code, the
`ttf/CascadiaCode.ttf` of its release zip) pinned to `wght=400` and cut to U+0020-007E with every
layout feature kept, for the `calt` ligature strings `-> != == => www /*` (`CascadiaCode-OFL.txt`,
SIL Open Font License 1.1, copyright Microsoft, reserved font name "Cascadia Code"). The licence
forbids a modified version under the reserved name, so the generator renames the family to
"Void Code Ligatures"; the filename is a description of where the glyphs come from, not the font
name. Not the copy in `C:/Windows/Fonts`: that one carries Microsoft's own wording on top.

```sh
python tests/fonts/cascadiaSubset.py CascadiaCode.ttf    # rewrites cascadiaSubset.ttf
```
