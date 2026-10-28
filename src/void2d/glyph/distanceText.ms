import { GlyphBox, Vertex, truncInt } from "../trueType/fontInfo";
import { getGlyphBitmapBoxSubpixel } from "../trueType/rasterize";
import { getGlyphSDF } from "../trueType/sdf";
import {
	GlyphFace,
	PAGE_COVERAGE,
	PAGE_SDF,
	SDF_BAD_HANDLE,
	SDF_BOX_MISMATCH,
	SDF_OK,
	SDF_OUTSIDE_PAGE,
	SDF_WRONG_PAGE_KIND,
	faceAt,
	state,
} from "./state";
import { glyphShape, isSynthetic, needSlots, putBox, validFace, void2dGlyphScale } from "./faces";
import { pageKindName, markDirtyBox, tileOutside, validPage } from "./pages";
import { SDF_DIST_SCALE, SDF_EDGE, SDF_EM, SDF_PAD, distanceFill, flattenCubics } from "./distance";
import { hasCubic, shapeBox } from "./outline";

const EMPTY_BOX: GlyphBox = { x0: 0, y0: 0, x1: 0, y1: 0 };

function paddedBox(box: GlyphBox, pad: int32): GlyphBox {
	if (box.x0 == box.x1 || box.y0 == box.y1) { return EMPTY_BOX; }
	return { x0: box.x0 - pad, y0: box.y0 - pad, x1: box.x1 + pad, y1: box.y1 + pad };
}

function bitmapBox(
	f: GlyphFace, glyph: int32, vertices: Readonly<Span<Vertex>>, scale: float32, shiftX: float32,
): GlyphBox {
	if (isSynthetic(f)) { return shapeBox(vertices, scale, shiftX); }
	return getGlyphBitmapBoxSubpixel(f.info, glyph, scale, scale, shiftX, 0.0);
}

function noTileKind(face: int32): boolean {
	return !validFace(face) || state.faces[face].sprite || state.faces[face].platform != null;
}

function sdfBitmapBox(
	f: GlyphFace, glyph: int32, vertices: Readonly<Span<Vertex>>, scale: float32,
): GlyphBox {
	return paddedBox(bitmapBox(f, glyph, vertices, scale, 0.0), SDF_PAD);
}

function clear5(out: Span<int32>, op: string): void {
	needSlots(op, out.length as int64, 5);
	for (let i: int32 = 0; i < 5; i++) { out[i] = 0; }
}

when (voidSdfText) {
	export function void2dGlyphSdfGenerations(): uint32 {
		return state.sdfGenerations;
	}

	export function void2dGlyphSdfBox(face: int32, glyph: int32, out: Span<int32>): void {
		clear5(out, "void2dGlyphSdfBox");
		if (!validFace(face)) { return; }
		const f = faceAt(face);
		if (f.sprite || f.platform != null) {
			out[4] = 1;
			return;
		}
		const vertices = glyphShape(f, glyph);
		if (vertices.length > 0) {
			if (hasCubic(vertices)) {
				out[4] = 1;
			} else {
				putBox(out, sdfBitmapBox(f, glyph, vertices, void2dGlyphScale(face, SDF_EM)));
			}
		}
	}

	export function void2dGlyphSdfRasterize(
		face: int32, glyph: int32, page: int32, x: int32, y: int32, w: int32, h: int32,
	): int32 {
		if (noTileKind(face) || !validPage(page) || w <= 0 || h <= 0) { return SDF_BAD_HANDLE; }
		const p = state.pages[page];
		if (p.kind != PAGE_SDF) {
			console.error(`void2d: an SDF tile was aimed at a ${pageKindName(p.kind)} page`);
			return SDF_WRONG_PAGE_KIND;
		}
		if (tileOutside(p, x, y, w, h)) {
			console.error(`void2d: SDF tile ${w}x${h} at (${x},${y}) falls outside its ${p.size} page`);
			return SDF_OUTSIDE_PAGE;
		}
		const f = faceAt(face);
		const vertices = glyphShape(f, glyph);
		let box: GlyphBox = EMPTY_BOX;
		if (vertices.length > 0 && !hasCubic(vertices)) {
			box = sdfBitmapBox(f, glyph, vertices, void2dGlyphScale(face, SDF_EM));
		}
		if (box.x1 - box.x0 != w || box.y1 - box.y0 != h) {
			console.error(
				`void2d: SDF tile ${w}x${h} does not match the glyph's ${box.x1 - box.x0}x${box.y1 - box.y0} box`,
			);
			return SDF_BOX_MISMATCH;
		}
		const at: int32 = y * p.size + x;
		distanceFill(
			vertices, void2dGlyphScale(face, SDF_EM), 0.0, box, false, 0.0,
			p.texels[at..p.texels.length], p.size,
		);
		state.sdfGenerations++;
		markDirtyBox(p, x, y, w, h);
		return SDF_OK;
	}

	export function void2dGlyphSdfStbDiff(face: int32, glyph: int32, page: int32, x: int32, y: int32): int32 {
		if (!validFace(face) || !validPage(page) || isSynthetic(state.faces[face]) ||
			state.faces[face].sprite || state.faces[face].platform != null) {
			return -2;
		}
		const p = state.pages[page];
		const reference = getGlyphSDF(
			state.faces[face].info, void2dGlyphScale(face, SDF_EM), glyph, SDF_PAD, SDF_EDGE as uint8,
			SDF_DIST_SCALE,
		);
		if (reference == null) { return -1; }
		let differing: int32 = 0;
		for (let row: int32 = 0; row < reference.height; row++) {
			for (let col: int32 = 0; col < reference.width; col++) {
				const at: int32 = (y + row) * p.size + (x + col);
				if (p.texels[at] != reference.data[row * reference.width + col]) { differing++; }
			}
		}
		let box: Vec<int32> = [0, 0, 0, 0, 0];
		void2dGlyphSdfBox(face, glyph, box);
		if (box[0] != reference.xoff || box[1] != reference.yoff ||
			box[2] - box[0] != reference.width || box[3] - box[1] != reference.height) {
			differing = -3;
		}
		return differing;
	}
}

when (voidTextOutline) {
	function outlinePad(widthPx: float32): int32 {
		return truncInt(Math.ceil(widthPx as float64)) + 1;
	}

	export function void2dGlyphOutlineGenerations(): uint32 {
		return state.outlineGenerations;
	}

	export function void2dGlyphOutlineBox(
		face: int32, glyph: int32, sizePx: float32, shiftX: float32, widthPx: float32,
		out: Span<int32>,
	): void {
		clear5(out, "void2dGlyphOutlineBox");
		if (!validFace(face)) { return; }
		const f = faceAt(face);
		if (f.sprite || f.platform != null) {
			out[4] = 1;
			return;
		}
		const vertices = glyphShape(f, glyph);
		if (vertices.length > 0) {
			putBox(out, paddedBox(
				bitmapBox(f, glyph, vertices, void2dGlyphScale(face, sizePx), shiftX), outlinePad(widthPx),
			));
		}
	}

	export function void2dGlyphOutlineRasterize(
		face: int32, glyph: int32, sizePx: float32, shiftX: float32, widthPx: float32,
		page: int32, x: int32, y: int32, w: int32, h: int32,
	): int32 {
		if (noTileKind(face) || !validPage(page) || w <= 0 || h <= 0) { return SDF_BAD_HANDLE; }
		const p = state.pages[page];
		if (p.kind != PAGE_COVERAGE) {
			console.error(`void2d: an outline tile was aimed at a ${pageKindName(p.kind)} page`);
			return SDF_WRONG_PAGE_KIND;
		}
		if (tileOutside(p, x, y, w, h)) {
			console.error(`void2d: outline tile ${w}x${h} at (${x},${y}) falls outside its ${p.size} page`);
			return SDF_OUTSIDE_PAGE;
		}
		const f = faceAt(face);
		const scale = void2dGlyphScale(face, sizePx);
		const vertices = glyphShape(f, glyph);
		let box: GlyphBox = EMPTY_BOX;
		if (vertices.length > 0) {
			box = paddedBox(bitmapBox(f, glyph, vertices, scale, shiftX), outlinePad(widthPx));
		}
		if (box.x1 - box.x0 != w || box.y1 - box.y0 != h) {
			console.error(
				`void2d: outline tile ${w}x${h} does not match the glyph's ${box.x1 - box.x0}x${box.y1 - box.y0} box`,
			);
			return SDF_BOX_MISMATCH;
		}
		const at: int32 = y * p.size + x;
		if (hasCubic(vertices)) {
			const flat = flattenCubics(vertices, 0.35 / scale);
			distanceFill(
				flat.vertices, scale / (flat.grid as float32), shiftX, box, true, widthPx,
				p.texels[at..p.texels.length], p.size,
			);
		} else {
			distanceFill(
				vertices, scale, shiftX, box, true, widthPx, p.texels[at..p.texels.length], p.size,
			);
		}
		state.outlineGenerations++;
		markDirtyBox(p, x, y, w, h);
		return SDF_OK;
	}
}

when (voidSdfText && voidTextOutline) {
	function sdfOutlineBox(
		f: GlyphFace, glyph: int32, vertices: Readonly<Span<Vertex>>, scale: float32, biasTexels: float32,
	): GlyphBox {
		const box = sdfBitmapBox(f, glyph, vertices, scale);
		if (box.x1 <= box.x0) { return box; }
		const extra: int32 = truncInt(Math.ceil(biasTexels as float64)) + 2;
		return { x0: box.x0 - extra, y0: box.y0 - extra, x1: box.x1 + extra, y1: box.y1 + extra };
	}

	export function void2dGlyphSdfOutlineBox(
		face: int32, glyph: int32, biasTexels: float32, out: Span<int32>,
	): void {
		clear5(out, "void2dGlyphSdfOutlineBox");
		if (!validFace(face)) { return; }
		const f = faceAt(face);
		if (f.sprite || f.platform != null) {
			out[4] = 1;
			return;
		}
		const vertices = glyphShape(f, glyph);
		if (vertices.length > 0) {
			if (hasCubic(vertices)) {
				out[4] = 1;
			} else {
				putBox(out, sdfOutlineBox(f, glyph, vertices, void2dGlyphScale(face, SDF_EM), biasTexels));
			}
		}
	}

	export function void2dGlyphSdfOutlineRasterize(
		face: int32, glyph: int32, biasTexels: float32, page: int32, x: int32, y: int32, w: int32, h: int32,
	): int32 {
		if (noTileKind(face) || !validPage(page) || w <= 0 || h <= 0) { return SDF_BAD_HANDLE; }
		const p = state.pages[page];
		if (p.kind != PAGE_SDF) {
			console.error(`void2d: an SDF outline tile was aimed at a ${pageKindName(p.kind)} page`);
			return SDF_WRONG_PAGE_KIND;
		}
		if (tileOutside(p, x, y, w, h)) {
			console.error(
				`void2d: SDF outline tile ${w}x${h} at (${x},${y}) falls outside its ${p.size} page`,
			);
			return SDF_OUTSIDE_PAGE;
		}
		const f = faceAt(face);
		const vertices = glyphShape(f, glyph);
		let box: GlyphBox = EMPTY_BOX;
		if (vertices.length > 0 && !hasCubic(vertices)) {
			box = sdfOutlineBox(f, glyph, vertices, void2dGlyphScale(face, SDF_EM), biasTexels);
		}
		if (box.x1 - box.x0 != w || box.y1 - box.y0 != h) {
			console.error(
				`void2d: SDF outline tile ${w}x${h} does not match the glyph's ${box.x1 - box.x0}x${box.y1 - box.y0} box`,
			);
			return SDF_BOX_MISMATCH;
		}
		const at: int32 = y * p.size + x;
		distanceFill(
			vertices, void2dGlyphScale(face, SDF_EM), 0.0, box, false, biasTexels,
			p.texels[at..p.texels.length], p.size,
		);
		state.outlineGenerations++;
		markDirtyBox(p, x, y, w, h);
		return SDF_OK;
	}
}
