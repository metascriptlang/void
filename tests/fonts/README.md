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
`python tests/fonts/brokenTables.py` rebuilds both from `assets/font.ttf`.
