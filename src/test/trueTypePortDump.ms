import {
	FontInfo, VERTEX_CUBIC, findGlyphIndex, getFontOffsetForIndex, getFontVMetrics, getGlyphBox,
	getGlyphHMetrics, getGlyphKernInfoAdvance, getGlyphShape, initFont, scaleForMappingEmToPixels,
	truncInt,
} from "../void2d/trueType";
import { getGlyphBitmapBoxSubpixel, makeGlyphBitmapSubpixel } from "../void2d/trueType/rasterize";
import { getGlyphSDF } from "../void2d/trueType/sdf";

export const CATEGORIES: int32 = 7;
export const MAX_FACES: int32 = 64;

const SIZES: float32[] = [9.0, 17.5, 64.0];
const SHIFTS_X: float32[] = [0.0, 0.37];
const SHIFTS_Y: float32[] = [0.0, 0.61];
const EXTRA_CODEPOINTS: int32[] = [-1, 0xFFFF, 0x1FFFF, 0xE0100, 0xFE0F, 0x10FFFF, 0x110000, 0x7FFFFFFF];

let digests: uint32[] = new Array<uint32>(CATEGORIES);
export let shapeHashes: uint32[] = [];
export let shapeGlyphs: int32[] = [];

export function faceDigest(cat: int32): uint32 {
	return digests[cat];
}

function mix(cat: int32, value: int32): void {
	digests[cat] = (digests[cat] ^ (value as uint32)) * 16777619;
}

function mixScale(s: float32): void {
	if (!(s < 255.0)) {
		mix(0, -1);
	} else {
		mix(0, truncInt((s * 4194304.0) as float64));
	}
}

export function fontOffsets(data: Readonly<Span<uint8>>): int32[] {
	let offsets: int32[] = [];
	for (let index: int32 = 0; index < MAX_FACES; index++) {
		const offset = getFontOffsetForIndex(data, index);
		offsets.push(offset);
		if (offset < 0) { break; }
	}
	return offsets;
}

function mixGlyph(info: FontInfo, g: int32): void {
	const n = info.numGlyphs;
	const metrics = getGlyphHMetrics(info, g);
	mix(2, metrics.advance);
	mix(2, metrics.bearing);
	const box = getGlyphBox(info, g);
	if (box == null) {
		mix(2, 0);
		mix(2, 0);
		mix(2, 0);
		mix(2, 0);
		mix(2, 0);
	} else {
		mix(2, 1);
		mix(2, box.x0);
		mix(2, box.y0);
		mix(2, box.x1);
		mix(2, box.y1);
	}
	if (n > 0) {
		mix(2, getGlyphKernInfoAdvance(info, g, (g * 7 + 3) % n));
		mix(2, getGlyphKernInfoAdvance(info, g, g + 1));
	}

	const verts = getGlyphShape(info, g);
	let h: uint32 = 2166136261;
	h = (h ^ (verts.length as uint32)) * 16777619;
	mix(3, verts.length as int32);
	for (let i: int32 = 0; i < (verts.length as int32); i++) {
		const v = verts[i];
		h = (h ^ (v.kind as uint32)) * 16777619;
		h = (h ^ ((v.x as int32) as uint32)) * 16777619;
		h = (h ^ ((v.y as int32) as uint32)) * 16777619;
		h = (h ^ ((v.cx as int32) as uint32)) * 16777619;
		h = (h ^ ((v.cy as int32) as uint32)) * 16777619;
		mix(3, v.kind as int32);
		mix(3, v.x as int32);
		mix(3, v.y as int32);
		mix(3, v.cx as int32);
		mix(3, v.cy as int32);
		if (v.kind == VERTEX_CUBIC) {
			mix(3, v.cx1 as int32);
			mix(3, v.cy1 as int32);
		}
	}

	shapeHashes.push(h);
	shapeGlyphs.push(g);
	for (let s: int32 = 0; s < 3; s++) {
		const scale = scaleForMappingEmToPixels(info, SIZES[s]);
		if (!(scale <= 10000000.0)) {
			mix(4, -7);
			continue;
		}
		for (let h: int32 = 0; h < 2; h++) {
			const b = getGlyphBitmapBoxSubpixel(info, g, scale, scale, SHIFTS_X[h], SHIFTS_Y[h]);
			mix(4, b.x0);
			mix(4, b.y0);
			mix(4, b.x1);
			mix(4, b.y1);
			const w = (b.x1 as int64) - (b.x0 as int64);
			const hh = (b.y1 as int64) - (b.y0 as int64);
			if (w > 0 && hh > 0 && w * hh <= 262144) {
				const pixels: uint8[] = new Array<uint8>((w * hh) as int32);
				makeGlyphBitmapSubpixel(
					info, pixels, w as int32, hh as int32, w as int32, scale, scale, SHIFTS_X[h], SHIFTS_Y[h], g,
				);
				for (let i: int32 = 0; i < pixels.length; i++) { mix(5, pixels[i] as int32); }
			}
		}
	}

	const scale32 = scaleForMappingEmToPixels(info, 32.0);
	if (!(scale32 <= 10000000.0)) {
		mix(6, -7);
		return;
	}
	const sdf = getGlyphSDF(info, scale32, g, 4, 191, 255.0 / 8.0);
	if (sdf == null) {
		mix(6, -1);
	} else {
		mix(6, sdf.width);
		mix(6, sdf.height);
		mix(6, sdf.xoff);
		mix(6, sdf.yoff);
		for (let i: int32 = 0; i < sdf.data.length; i++) { mix(6, sdf.data[i] as int32); }
	}
}

// Digests of one face per category, read with faceDigest; the same sweep the C reference ran.
export function runFace(
	data: Readonly<Span<uint8>>,
	offset: int32,
	glyphStride: int32,
	cpStride: int32,
): boolean {
	for (let i: int32 = 0; i < CATEGORIES; i++) { digests[i] = 2166136261; }
	shapeHashes = [];
	shapeGlyphs = [];
	const info = initFont(data, offset);
	if (info == null) {
		mix(0, 0);
		return false;
	}
	mix(0, 1);
	mix(0, info.numGlyphs);
	const vm = getFontVMetrics(info);
	mix(0, vm.ascent);
	mix(0, vm.descent);
	mix(0, vm.lineGap);
	mixScale(scaleForMappingEmToPixels(info, 32.0));
	mixScale(scaleForMappingEmToPixels(info, 17.5));

	if (cpStride > 0) {
		for (let cp: int32 = 0; cp <= 0x10FFFF; cp += cpStride) { mix(1, findGlyphIndex(info, cp)); }
		for (const cp of EXTRA_CODEPOINTS) { mix(1, findGlyphIndex(info, cp)); }
	}

	for (let g: int32 = 0; g < info.numGlyphs; g += glyphStride) { mixGlyph(info, g); }
	for (let cp: int32 = 0x20; cp <= 0x17F; cp++) {
		const g = cpStride > 0 ? findGlyphIndex(info, cp) : 0;
		if (g > 0) { mixGlyph(info, g); }
	}
	return true;
}

export function mixCombined(acc: uint32, value: uint32): uint32 {
	return (acc ^ value) * 16777619;
}

export function glyphStrideOf(data: Readonly<Span<uint8>>, offset: int32): int32 {
	const info = initFont(data, offset);
	return (info == null ? 0 : info.numGlyphs) / 200 + 1;
}

// The digest the pins record: the category digests of every face of the file, folded in order.
export function combineFont(data: Readonly<Span<uint8>>, acc: uint32, cpStride: int32): uint32 {
	let result = acc;
	for (const offset of fontOffsets(data)) {
		if (offset < 0) { continue; }
		runFace(data, offset, glyphStrideOf(data, offset), cpStride);
		for (let cat: int32 = 0; cat < CATEGORIES; cat++) { result = mixCombined(result, digests[cat]); }
	}
	return result;
}
