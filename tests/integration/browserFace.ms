// The web build draws a codepoint no bundled font covers through the browser's own face.
import { isPlatformFace, glyphIndex, glyphAdvance, pageTexel } from "../../src/void2d/face";
import { GlyphAtlas, GlyphKey, PageKind } from "../../src/void2d/glyphAtlas";
import { DEFAULT_FONT, codepointFaceFor, fontFace, Presentation } from "../../src/void2d/font";
import { voidCaptureExit } from "../capture/capture.h";

const HANZI_BUNDLED_INTER_LACKS: int32 = 0x4F60;
const LATIN_H: int32 = 0x48;
const SIZE_PX: float32 = 32.0;

function check(ok: boolean, what: string): void {
	if (!ok) {
		console.log(`FAIL browser face: ${what}`);
		voidCaptureExit(1);
	}
}

function inkSum(face: int32, glyph: int32): float64 {
	const atlas = GlyphAtlas.create(256, 1);
	const key: GlyphKey = {
		kind: PageKind.Coverage, face: face, glyph: glyph, sizePx: SIZE_PX, variant: 0, outline: 0,
	};
	const placed = atlas.acquire(key);
	if (!placed.ok) { return -1.0; }
	const t = atlas.tile(placed.value);
	let sum: float64 = 0.0;
	for (let y = 0; y < t.height; y++) {
		for (let x = 0; x < t.width; x++) {
			sum = sum + (pageTexel(atlas.pageHandle(t.page), t.x + x, t.y + y) as float64);
		}
	}
	return sum;
}

const bundled: int32 = fontFace(DEFAULT_FONT);
check(glyphIndex(bundled, HANZI_BUNDLED_INTER_LACKS) == 0, "the bundled face already covers 你");
const latin = codepointFaceFor(DEFAULT_FONT, LATIN_H, Presentation.Default);
check(latin.face == bundled, `H left the bundled face for face ${latin.face}`);
const hanzi = codepointFaceFor(DEFAULT_FONT, HANZI_BUNDLED_INTER_LACKS, Presentation.Default);
check(hanzi.face != bundled && isPlatformFace(hanzi.face), `你 resolved to face ${hanzi.face}`);
const advance: float32 = glyphAdvance(hanzi.face, HANZI_BUNDLED_INTER_LACKS, SIZE_PX);
check(advance > SIZE_PX * 0.5, `你 advances ${advance} px at ${SIZE_PX} px`);
const ink: float64 = inkSum(hanzi.face, HANZI_BUNDLED_INTER_LACKS);
check(ink > 0.0, `你 rasterized with ink ${ink}`);
console.log(`PASS browser face: 你 drawn by face ${hanzi.face}, advance ${advance} px, ink ${ink}`);
voidCaptureExit(0);
