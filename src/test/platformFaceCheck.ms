import {
	loadFace,
	peekFace,
	platformFace,
	isPlatformFace,
	glyphIndex,
	glyphAdvance,
	faceMetrics,
	pageTexel,
} from "../void2d/face";
import { glyphBox } from "../void2d/glyphBoxes";
import { GlyphAtlas, GlyphKey, PageKind } from "../void2d/glyphAtlas";
import {
	addFont, setFaceResolver, codepointFaceFor, fontFace, FaceQuery, FaceCandidate, Presentation,
} from "../void2d/font";

const PING_FANG: string = "/System/Library/PrivateFrameworks/FontServices.framework/Versions/A/" +
	"Resources/Reserved/PingFangUI.ttc";
const ST_HEITI: string = "/System/Library/Fonts/STHeiti Light.ttc";
const SAMPLE: string = "Hgjy@&Q";
const SIZES: float32[] = [11.0, 13.0, 16.0, 32.0];
const SHIFTS: float32[] = [0.0, 0.25, 0.5, 0.75];

let fileFace: int32 = -1;
let osFace: int32 = -1;

function faces(): boolean {
	if (fileFace < 0) {
		fileFace = try loadFace("assets/font.ttf") catch -1;
		osFace = try platformFace(fileFace) catch -1;
	}
	return fileFace >= 0 && osFace >= 0;
}

interface Ink {
	sum: float64;
	x: float64;
	y: float64;
}

function inkOf(atlas: GlyphAtlas, face: int32, glyph: int32, sizePx: float32, variant: int32): Ink {
	const key: GlyphKey = {
		kind: PageKind.Coverage, face: face, glyph: glyph, sizePx: sizePx, variant: variant, outline: 0,
	};
	const ink: Ink = { sum: -1.0, x: 0.0, y: 0.0 };
	const placed = atlas.acquire(key);
	if (!placed.ok) { return ink; }
	ink.sum = 0.0;
	const t = atlas.tile(placed.value);
	for (let y = 0; y < t.height; y++) {
		for (let x = 0; x < t.width; x++) {
			const v: float64 = pageTexel(atlas.pageHandle(t.page), t.x + x, t.y + y) as float64;
			ink.sum = ink.sum + v;
			ink.x = ink.x + v * ((t.left + x) as float64 + 0.5);
			ink.y = ink.y + v * ((t.top + y) as float64 + 0.5);
		}
	}
	if (ink.sum > 0.0) {
		ink.x = ink.x / ink.sum;
		ink.y = ink.y / ink.sum;
	}
	return ink;
}

test "a platform face keeps the file's cmap, advances and line metrics" {
	assert faces();
	for (let i = 0; i < SAMPLE.length; i++) {
		const codepoint: int32 = SAMPLE.charCodeAt(i) as int32;
		const glyph: int32 = glyphIndex(fileFace, codepoint);
		assert glyph != 0;
		assert glyphIndex(osFace, codepoint) == glyph;
		assert glyphAdvance(osFace, glyph, 16.0) == glyphAdvance(fileFace, glyph, 16.0);
	}
	const file = faceMetrics(fileFace, 13.0);
	const os = faceMetrics(osFace, 13.0);
	assert os.ascent == file.ascent;
	assert os.descent == file.descent;
	assert os.lineGap == file.lineGap;
}

test "an OS ink box lands within a pixel of stb_truetype's at every size and shift" {
	assert faces();
	for (let i = 0; i < SAMPLE.length; i++) {
		const glyph: int32 = glyphIndex(fileFace, SAMPLE.charCodeAt(i) as int32);
		for (const size of SIZES) {
			for (const shift of SHIFTS) {
				const file = glyphBox(fileFace, glyph, size, shift);
				const os = glyphBox(osFace, glyph, size, shift);
				for (let k = 0; k < 4; k++) {
					const apart: int32 = os[k] - file[k];
					if (apart > 1 || apart < -1) {
						console.log(`platformFace: '${SAMPLE.charAt(i)}' at ${size} px shift ${shift}: ` +
							`box [${os[0]}, ${os[1]}, ${os[2]}, ${os[3]}] against stb ` +
							`[${file[0]}, ${file[1]}, ${file[2]}, ${file[3]}]`);
					}
					assert apart <= 1 && apart >= -1;
				}
			}
		}
	}
}

test "OS coverage has stb_truetype's ink, centred on it across and within half a pixel down" {
	assert faces();
	const atlas = GlyphAtlas.create(512, 2);
	defer atlas.dispose();
	let misses: int32 = 0;
	for (let i = 0; i < SAMPLE.length; i++) {
		const glyph: int32 = glyphIndex(fileFace, SAMPLE.charCodeAt(i) as int32);
		for (const size of SIZES) {
			for (let variant = 0; variant < 4; variant++) {
				const file = inkOf(atlas, fileFace, glyph, size, variant);
				const os = inkOf(atlas, osFace, glyph, size, variant);
				assert file.sum > 0.0 && os.sum >= 0.0;
				const ratio: float64 = os.sum / file.sum;
				const dx: float64 = os.x - file.x;
				const dy: float64 = os.y - file.y;
				const near: boolean = ratio > 0.9 && ratio < 1.1 && dx > -0.2 && dx < 0.2 &&
					dy > -0.5 && dy < 0.5;
				if (!near) {
					misses = misses + 1;
					console.log(`platformFace: '${SAMPLE.charAt(i)}' at ${size} px variant ${variant}: ` +
						`ink ${ratio} of stb's, centre off by (${dx}, ${dy})`);
				}
			}
		}
	}
	assert misses == 0;
}

test "a face whose outlines only the OS draws loads, and its glyphs carry ink" {
	const summary = peekFace(PING_FANG, 0);
	if (!summary.ok) {
		console.log(`platformFace: ${PING_FANG} is not on this Mac; its check did not run`);
		return;
	}
	assert !summary.value.drawable;
	assert summary.value.osOutlines;
	const face = try loadFace(PING_FANG, 0) catch -1;
	assert face >= 0;
	const glyph: int32 = glyphIndex(face, 0x4F60);
	assert glyph != 0;
	const em: float32 = glyphAdvance(face, glyph, 16.0);
	assert em > 15.0 && em < 17.0;
	const atlas = GlyphAtlas.create(256, 1);
	defer atlas.dispose();
	const ink = inkOf(atlas, face, glyph, 16.0, 0);
	assert ink.sum > 255.0 * 20.0;
	assert ink.y < 0.0;
}

test "a resolver's face whose outlines only the OS draws wins over a file face after it" {
	if (!peekFace(PING_FANG, 0).ok || !peekFace(ST_HEITI, 0).ok) {
		console.log(`platformFace: PingFang or STHeiti is not on this Mac; the resolver check did not run`);
		return;
	}
	setFaceResolver((q: FaceQuery): FaceCandidate[] =>
		[{ path: PING_FANG, index: 0 }, { path: ST_HEITI, index: 0 }]);
	const added = addFont("assets/font.ttf");
	assert added.ok;
	if (!added.ok) { return; }
	const latin = added.value;
	const chosen: int32 = codepointFaceFor(latin, 0x4F60, Presentation.Text).face;
	assert chosen != fontFace(latin);
	assert isPlatformFace(chosen);
	assert !isPlatformFace(fontFace(latin));
	setFaceResolver(null);
}
