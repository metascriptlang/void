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
