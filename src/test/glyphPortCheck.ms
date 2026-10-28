// Pinned from the C glyph.c this module replaced, over the repo fonts only: per face the
// metrics, advances, kerning and boxes at three sizes, and for assets/font.ttf the coverage
// pages, their upload boxes and the synthetic bold and italic faces. The CBDT-only fonts are
// left out: a build with colour emoji off and one with it on box them differently. Handles and global
// counters stay out of the digest, so the order of the other tests does not move it.
import {
	void2dGlyphAdvance,
	void2dGlyphBox,
	void2dGlyphDecoration,
	void2dGlyphEmbolden,
	void2dGlyphFaceHeights,
	void2dGlyphFaceLoad,
	void2dGlyphFaceMetrics,
	void2dGlyphFaceSynthetic,
	void2dGlyphIndex,
	void2dGlyphKern,
	void2dGlyphPageBytes,
	void2dGlyphPageClear,
	void2dGlyphPageCreate,
	void2dGlyphPageKind,
	void2dGlyphPageRelease,
	void2dGlyphPageSize,
	void2dGlyphPageTakeUpload,
	void2dGlyphPageTexel,
	void2dGlyphPageUploadBox,
	void2dGlyphPageUploaded,
	void2dGlyphPagesFrameBegin,
	void2dGlyphPagesMarkDirty,
	void2dGlyphRasterize,
	void2dGlyphScale,
} from "../void2d/glyph";

const PINNED: string[] = [
	"2818068566", // assets/font.ttf
	"3426308802", // tests/fonts/NotoSansSC-subset.ttf
	"943215215", // tests/fonts/cascadiaSubset.ttf
	"1395783799", // tests/fonts/cbdtBroken.ttf
	"102254392", // tests/fonts/cffSynthetic.otf
	"419429650", // tests/fonts/colrForeground.ttf
	"1961728783", // tests/fonts/colrLigature.ttf
	"3878737308", // tests/fonts/colrSynthetic.ttf
	"1129543216", // tests/fonts/colrUnion.ttf
	"452559396", // tests/fonts/colrV1Only.ttf
	"738099101", // tests/fonts/ligatureFeatures.ttf
	"441817958", // tests/fonts/notoSansArabicSubset.ttf
	"1227922014", // tests/fonts/notoSansDevanagariSubset.ttf
	"1485487439", // tests/fonts/notoSansHebrewSubset.ttf
	"502227479", // tests/fonts/notoSansKhmerSubset.ttf
	"596558576", // tests/fonts/notoSansThaiSubset.ttf
	"380855210", // tests/fonts/sbixLoop.ttf
	"1058440669", // tests/fonts/sbixSynthetic.ttf
	"3598383609", // tests/fonts/shapeFixture.ttf
	"3455798458", // tests/fonts/symbolCollection.ttc
	"3524369390", // tests/fonts/textSymbol.ttf
	"1252817645", // tests/fonts/zeroLineHeight.ttf
	"1900485138", // tests/fonts/zeroThickness.ttf
	"1218056867", // tests/fonts/zeroedDecorations.ttf
];
const PATHS: string[] = [
	"assets/font.ttf",
	"tests/fonts/NotoSansSC-subset.ttf",
	"tests/fonts/cascadiaSubset.ttf",
	"tests/fonts/cbdtBroken.ttf",
	"tests/fonts/cffSynthetic.otf",
	"tests/fonts/colrForeground.ttf",
	"tests/fonts/colrLigature.ttf",
	"tests/fonts/colrSynthetic.ttf",
	"tests/fonts/colrUnion.ttf",
	"tests/fonts/colrV1Only.ttf",
	"tests/fonts/ligatureFeatures.ttf",
	"tests/fonts/notoSansArabicSubset.ttf",
	"tests/fonts/notoSansDevanagariSubset.ttf",
	"tests/fonts/notoSansHebrewSubset.ttf",
	"tests/fonts/notoSansKhmerSubset.ttf",
	"tests/fonts/notoSansThaiSubset.ttf",
	"tests/fonts/sbixLoop.ttf",
	"tests/fonts/sbixSynthetic.ttf",
	"tests/fonts/shapeFixture.ttf",
	"tests/fonts/symbolCollection.ttc",
	"tests/fonts/textSymbol.ttf",
	"tests/fonts/zeroLineHeight.ttf",
	"tests/fonts/zeroThickness.ttf",
	"tests/fonts/zeroedDecorations.ttf",
];

function aLoad(path: string, index: int32): int32 { return void2dGlyphFaceLoad(path, index); }
function aSynthetic(face: int32, bold: int32, italic: int32): int32 { return void2dGlyphFaceSynthetic(face, bold, italic); }
function aScale(face: int32, size: float32): float32 { return void2dGlyphScale(face, size); }
function aIndex(face: int32, cp: int32): int32 { return void2dGlyphIndex(face, cp); }
function aAdvance(face: int32, glyph: int32, size: float32): float32 { return void2dGlyphAdvance(face, glyph, size); }
function aKern(face: int32, l: int32, r: int32, size: float32): float32 { return void2dGlyphKern(face, l, r, size); }
function aEmbolden(face: int32, size: float32): float32 { return void2dGlyphEmbolden(face, size); }
function aMetrics(face: int32, size: float32): Vec<float32> {
	let out: Vec<float32> = [0.0, 0.0, 0.0, 0.0];
	void2dGlyphFaceMetrics(face, size, out);
	return out;
}
function aDecoration(face: int32, size: float32): Vec<float32> {
	let out: Vec<float32> = [0.0, 0.0, 0.0, 0.0];
	void2dGlyphDecoration(face, size, out);
	return out;
}
function aHeights(face: int32): Vec<float32> {
	let out: Vec<float32> = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
	void2dGlyphFaceHeights(face, out);
	return out;
}
function aBox(face: int32, glyph: int32, size: float32, shift: float32): Vec<int32> {
	let out: Vec<int32> = [0, 0, 0, 0];
	void2dGlyphBox(face, glyph, size, shift, out);
	return out;
}
function aPageCreate(size: int32, kind: int32): int32 { return void2dGlyphPageCreate(size, kind); }
function aPageRelease(page: int32): int32 { return void2dGlyphPageRelease(page); }
function aPageKind(page: int32): int32 { return void2dGlyphPageKind(page); }
function aPageSize(page: int32): int32 { return void2dGlyphPageSize(page); }
function aPageBytes(page: int32): int32 { return void2dGlyphPageBytes(page); }
function aPageClear(page: int32): void { void2dGlyphPageClear(page); }
function aRasterize(face: int32, glyph: int32, size: float32, shift: float32, page: int32, x: int32, y: int32, w: int32, h: int32): int32 {
	return void2dGlyphRasterize(face, glyph, size, shift, page, x, y, w, h);
}
function aTexel(page: int32, x: int32, y: int32): int32 { return void2dGlyphPageTexel(page, x, y); }
function aTakeUpload(page: int32): int32 { return void2dGlyphPageTakeUpload(page); }
function aUploadBox(page: int32): Vec<int32> { return void2dGlyphPageUploadBox(page); }
function aUploaded(page: int32): int32 { return void2dGlyphPageUploaded(page); }
function aMarkDirty(): void { void2dGlyphPagesMarkDirty(); }
function aFrameBegin(): void { void2dGlyphPagesFrameBegin(); }


const CPS: int32[] = [
	0x20, 0x21, 0x28, 0x2e, 0x30, 0x31, 0x38, 0x41, 0x42, 0x46, 0x48, 0x4a, 0x4f, 0x51, 0x54, 0x56, 0x57, 0x58, 0x59,
	0x61, 0x62, 0x63, 0x65, 0x66, 0x67, 0x69, 0x6a, 0x6c, 0x6d, 0x6f, 0x70, 0x71, 0x72, 0x73, 0x74, 0x76, 0x77, 0x79, 0x7a,
	0x7b, 0x7e, 0xe9, 0xc5, 0x4e2d, 0x6c34, 0x2603, 0x2764, 0x1f600, 0x1f44d, 0x5d0, 0x627, 0x905, 0x0e01,
];
const SIZES: float32[] = [9.0, 13.5, 24.0];
const SHIFTS: float32[] = [0.0, 0.5];
let lines: int32 = 0;
let running: int64 = 2166136261;

function say(text: string): void {
	for (let i: int32 = 0; i < text.length; i++) { running = ((running ^ (text.charCodeAt(i) as int64)) * 16777619) & 0xFFFFFFFF; }
	lines++;
}

function boxText(b: Vec<int32>): string {
	return b.join(",");
}

function pageHash(page: int32, rgba: boolean): string {
	const size = aPageSize(page);
	let h: int64 = 2166136261;
	for (let y: int32 = 0; y < size; y++) {
		for (let x: int32 = 0; x < size; x++) {
			let v: int64 = 0;
			v = aTexel(page, x, y) as int64;
			h = ((h ^ (v & 0xFFFF)) * 16777619) & 0xFFFFFFFF;
			h = ((h ^ ((v >> 16) & 0xFFFF)) * 16777619) & 0xFFFFFFFF;
		}
	}
	return `${h}`;
}

function pageState(tag: string, page: int32, rgba: boolean): void {
	say(`${tag} page kind ${aPageKind(page)} size ${aPageSize(page)} bytes ${aPageBytes(page)} hash ${pageHash(page, rgba)}`);
}

function uploadCycle(tag: string, page: int32): void {
	const a = aTakeUpload(page);
	const box = boxText(aUploadBox(page));
	const again = aTakeUpload(page);
	aFrameBegin();
	const b = aTakeUpload(page);
	say(`${tag} upload ${a} ${box} ${again} ${aUploaded(page)} ${b} ${aUploaded(page)}`);
}

function sweepFace(tag: string, face: int32): void {
	const heights = aHeights(face);
	say(`${tag} heights ${heights.join(",")} scale ${aScale(face, 16.0)} embolden ${aEmbolden(face, 16.0)}`);
	for (let s: int32 = 0; s < SIZES.length; s++) {
		const size = SIZES[s];
		say(`${tag} metrics ${size} ${aMetrics(face, size).join(",")} deco ${aDecoration(face, size).join(",")}`);
	}
	let prev: int32 = 0;
	for (let i: int32 = 0; i < CPS.length; i++) {
		const glyph = aIndex(face, CPS[i]);
		let row = `${tag} cp ${CPS[i]} glyph ${glyph}`;
		for (let s: int32 = 0; s < SIZES.length; s++) {
			const size = SIZES[s];
			row += ` adv ${aAdvance(face, glyph, size)} kern ${aKern(face, prev, glyph, size)}`;
			for (let k: int32 = 0; k < SHIFTS.length; k++) {
				row += ` box ${boxText(aBox(face, glyph, size, SHIFTS[k]))}`;
			}
		}
		say(row);
		prev = glyph;
	}
}

function rasterPage(tag: string, face: int32, size: float32, shift: float32): void {
	const page = aPageCreate(256, 0);
	let x: int32 = 0;
	let y: int32 = 0;
	let rowHeight: int32 = 0;
	let codes: string = "";
	for (let i: int32 = 0; i < CPS.length; i++) {
		const glyph = aIndex(face, CPS[i]);
		const b = aBox(face, glyph, size, shift);
		const w = b[2] - b[0];
		const h = b[3] - b[1];
		if (w <= 0 || h <= 0) { continue; }
		if (x + w > 256) {
			x = 0;
			y += rowHeight + 1;
			rowHeight = 0;
		}
		if (y + h > 256) { break; }
		codes += `${aRasterize(face, glyph, size, shift, page, x, y, w, h)},`;
		x += w + 1;
		if (h > rowHeight) { rowHeight = h; }
	}
	say(`${tag} raster ${size} ${shift} codes ${codes}`);
	pageState(`${tag} raster`, page, false);
	uploadCycle(`${tag} raster`, page);
	aMarkDirty();
	uploadCycle(`${tag} dirtied`, page);
	say(`${tag} errors ${aRasterize(face, 0, size, shift, 99, 0, 0, 4, 4)} ${aRasterize(-1, 0, size, shift, page, 0, 0, 4, 4)} ${aRasterize(face, 0, size, shift, page, 250, 250, 20, 20)} ${aRasterize(face, 0, size, shift, page, 0, 0, 0, 4)}`);
	aPageClear(page);
	pageState(`${tag} cleared`, page, false);
	say(`${tag} release ${aPageRelease(page)} ${aPageRelease(page)}`);
}

function digestOf(path: string): string {
	running = 2166136261;
	lines = 0;
	const face = aLoad(path, 0);
	say(`${path} load ${face >= 0}`);
	if (face < 0) { return `${running}`; }
	sweepFace("f", face);
	if (path == "assets/font.ttf") {
		rasterPage("f", face, 24.0, 0.0);
		rasterPage("f", face, 13.5, 0.5);
		const bold = aSynthetic(face, 1, 0);
		const italic = aSynthetic(face, 0, 1);
		const both = aSynthetic(face, 1, 1);
		say(`synthetic ${bold >= 0} ${italic >= 0} ${both >= 0}`);
		sweepFace("bold", bold);
		sweepFace("italic", italic);
		rasterPage("bold", bold, 24.0, 0.0);
		rasterPage("italic", italic, 24.0, 0.25);
		rasterPage("both", both, 13.5, 0.5);
	}
	return `${running}`;
}

test "the glyph port over the repo fonts keeps the digest recorded from glyph.c" {
	assert PATHS.length == PINNED.length;
	for (let f: int32 = 0; f < PATHS.length; f++) {
		const got = digestOf(PATHS[f]);
		if (got != PINNED[f]) { console.error(`glyph port digest moved for ${PATHS[f]}: ${got} != ${PINNED[f]}`); }
		assert got == PINNED[f];
	}
}
