// expect: void2d glyph atlas: a key of size 1100 px and outline lane 0 does not fit the packed key
import { GlyphKey, PageKind } from "../../src/void2d/glyphAtlas";

const key: GlyphKey = {
	kind: PageKind.Coverage, face: 0, glyph: 36, sizePx: 1100.0, variant: 0, outline: 0,
};
console.log(`the key packed to ${key.packed()}`);
