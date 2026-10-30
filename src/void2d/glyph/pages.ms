import { makeGlyphBitmapSubpixel, rasterize } from "../trueType/rasterize";
import {
	BLIT_BAD_HANDLE,
	BLIT_OK,
	BLIT_OUTSIDE_PAGE,
	BLIT_WRONG_PAGE_KIND,
	COVERAGE_RASTER_BAD_HANDLE,
	COVERAGE_RASTER_BOX_MISMATCH,
	COVERAGE_RASTER_OUTSIDE_PAGE,
	COVERAGE_RASTER_WRONG_PAGE_KIND,
	GlyphPage,
	MAX_GLYPH_PAGES,
	PAGE_COVERAGE,
	PAGE_MASK,
	PAGE_RGBA,
	PAGE_SDF,
	faceAt,
	state,
} from "./state";
import { glyphShape, isSynthetic, validFace, void2dGlyphScale } from "./faces";
import { shapeBox } from "./outline";

when (voidSprites) {
	import { spriteInk } from "./faces";
}

when (macos || ios || emcc) {
	import { platformFill } from "./platform";
}

function releasedPage(page: int32): boolean {
	console.error(`void2d: glyph page ${page} was released`);
	return false;
}

export function markDirtyBox(p: GlyphPage, x: int32, y: int32, w: int32, h: int32): void {
	if (!p.dirty) {
		p.dirtyBox[0] = x;
		p.dirtyBox[1] = y;
		p.dirtyBox[2] = x + w;
		p.dirtyBox[3] = y + h;
		p.dirty = true;
		return;
	}
	if (x < p.dirtyBox[0]) { p.dirtyBox[0] = x; }
	if (y < p.dirtyBox[1]) { p.dirtyBox[1] = y; }
	if (x + w > p.dirtyBox[2]) { p.dirtyBox[2] = x + w; }
	if (y + h > p.dirtyBox[3]) { p.dirtyBox[3] = y + h; }
}

function markDirtyWhole(p: GlyphPage): void {
	p.dirty = false;
	markDirtyBox(p, 0, 0, p.size, p.size);
}

export function validPage(page: int32): boolean {
	if (page < 0 || page >= (state.pages.length as int32)) { return false; }
	if (!state.pages[page].live) { return releasedPage(page); }
	return true;
}

export function pageKindName(kind: int32): string {
	return match (kind) {
		0 => "Coverage",
		1 => "Sdf",
		2 => "Rgba",
		3 => "Mask",
		_ => "unknown",
	};
}

function pageKindBuilt(kind: int32): boolean {
	when (voidSdfText) {
		if (kind == PAGE_SDF) { return true; }
	}
	when (voidColourEmoji) {
		if (kind == PAGE_RGBA) { return true; }
	}
	when (voidSvg) {
		if (kind == PAGE_MASK) { return true; }
	}
	return kind == PAGE_COVERAGE;
}

export function void2dGlyphPageKindBuilt(kind: int32): int32 {
	return pageKindBuilt(kind) ? 1 : 0;
}

function texelBytes(kind: int32): int32 {
	return kind == PAGE_RGBA ? 4 : 1;
}

function pageByteCount(p: GlyphPage): int32 {
	return p.size * p.size * texelBytes(p.kind);
}

export function void2dGlyphPageCreate(size: int32, kind: int32): int32 {
	if (size <= 0) { return -1; }
	if (!pageKindBuilt(kind)) {
		console.error(`void2d: glyph page kind ${pageKindName(kind)} (${kind}) is not built`);
		return -1;
	}
	let slot: int32 = 0;
	while (slot < (state.pages.length as int32) && state.pages[slot].live) { slot++; }
	if (slot >= MAX_GLYPH_PAGES) {
		console.error(`void2d: glyph page ${slot} refused, the renderer binds at most ${MAX_GLYPH_PAGES}`);
		return -1;
	}
	if (slot == (state.pages.length as int32)) { state.pages.push(new GlyphPage()); }
	const p = state.pages[slot];
	p.texels = new Array<uint8>(size * size * texelBytes(kind));
	p.size = size;
	p.kind = kind;
	markDirtyWhole(p);
	p.uploaded = false;
	p.live = true;
	state.pageGenerations++;
	p.generation = state.pageGenerations;
	return slot;
}

export function void2dGlyphPageRelease(page: int32): int32 {
	if (!validPage(page)) {
		console.error(`void2d: glyph page ${page} cannot be released, it is not live`);
		return -1;
	}
	state.pages[page].texels = [];
	state.pages[page].live = false;
	return 0;
}

export function void2dGlyphPageGeneration(page: int32): uint32 {
	if (page < 0 || page >= (state.pages.length as int32) || !state.pages[page].live) { return 0; }
	return state.pages[page].generation;
}

export function void2dGlyphPageLiveCount(): int32 {
	let live: int32 = 0;
	for (let page: int32 = 0; page < (state.pages.length as int32); page++) {
		if (state.pages[page].live) { live++; }
	}
	return live;
}

export function void2dGlyphPageCount(): int32 {
	return state.pages.length as int32;
}

export function void2dGlyphPageKind(page: int32): int32 {
	return validPage(page) ? state.pages[page].kind : -1;
}

export function void2dGlyphPageSize(page: int32): int32 {
	return validPage(page) ? state.pages[page].size : 0;
}

export function void2dGlyphPageBytes(page: int32): int32 {
	return validPage(page) ? pageByteCount(state.pages[page]) : 0;
}

export function void2dGlyphPageClear(page: int32): void {
	if (!validPage(page)) { return; }
	const p = state.pages[page];
	for (let i: int32 = 0; i < (p.texels.length as int32); i++) { p.texels[i] = 0; }
	markDirtyWhole(p);
}

export function tileOutside(p: GlyphPage, x: int32, y: int32, w: int32, h: int32): boolean {
	return x < 0 || y < 0 || x + w > p.size || y + h > p.size;
}

export function void2dGlyphRasterize(
	face: int32, glyph: int32, sizePx: float32, shiftX: float32,
	page: int32, x: int32, y: int32, w: int32, h: int32,
): int32 {
	if (!validFace(face) || !validPage(page) || w <= 0 || h <= 0) {
		return COVERAGE_RASTER_BAD_HANDLE;
	}
	const p = state.pages[page];
	if (p.kind != PAGE_COVERAGE) {
		console.error(`void2d: a coverage tile was aimed at a ${pageKindName(p.kind)} page`);
		return COVERAGE_RASTER_WRONG_PAGE_KIND;
	}
	if (tileOutside(p, x, y, w, h)) {
		console.error(`void2d: glyph tile ${w}x${h} at (${x},${y}) falls outside its ${p.size} page`);
		return COVERAGE_RASTER_OUTSIDE_PAGE;
	}
	const scale = void2dGlyphScale(face, sizePx);
	const f = faceAt(face);
	const at: int32 = y * p.size + x;
	let handled: boolean = false;
	when (voidSprites) {
		if (f.sprite) {
			handled = true;
			const ink = spriteInk(face, glyph, sizePx);
			if (ink == null || ink.box.x1 - ink.box.x0 != w || ink.box.y1 - ink.box.y0 != h) {
				console.error(`void2d: sprite tile ${w}x${h} does not match glyph ${glyph}'s ink box`);
				return COVERAGE_RASTER_BOX_MISMATCH;
			}
			for (let row: int32 = 0; row < h; row++) {
				for (let k: int32 = 0; k < w; k++) {
					p.texels[at + row * p.size + k] = ink.pixels[ink.origin + row * ink.stride + k];
				}
			}
		}
	}
	when (macos || ios || emcc) {
		const platform = f.platform;
		if (!handled && platform != null) {
			handled = true;
			if (!platformFill(
				platform, glyph, sizePx, shiftX, f.skew, f.emboldenUnits * scale,
				p.texels[at..p.texels.length], w, h, p.size,
			)) {
				console.error(`void2d: platform tile ${w}x${h} does not match glyph ${glyph}'s ink box`);
				return COVERAGE_RASTER_BOX_MISMATCH;
			}
		}
	}
	if (!handled) {
		if (isSynthetic(f)) {
			const vertices = glyphShape(f, glyph);
			const box = shapeBox(vertices, scale, shiftX);
			if (vertices.length > 0) {
				rasterize(
					p.texels[at..p.texels.length], w, h, p.size, 0.35, vertices,
					scale, scale, shiftX, 0.0, box.x0, box.y0, true,
				);
			}
		} else {
			makeGlyphBitmapSubpixel(
				f.info, p.texels[at..p.texels.length], w, h, p.size, scale, scale, shiftX, 0.0, glyph,
			);
		}
	}
	markDirtyBox(p, x, y, w, h);
	return 0;
}

export function void2dGlyphPageTexel(page: int32, x: int32, y: int32): int32 {
	if (!validPage(page)) { return -1; }
	const p = state.pages[page];
	if (x < 0 || y < 0 || x >= p.size || y >= p.size) { return -1; }
	if (p.kind == PAGE_RGBA) {
		console.error(`void2d: page ${page} is Rgba, its texels are read with PageTexelRgba`);
		return -1;
	}
	return p.texels[y * p.size + x] as int32;
}

when (voidColourEmoji) {
	export function void2dGlyphPageTexelRgba(page: int32, x: int32, y: int32): uint32 {
		if (!validPage(page)) { return 0; }
		const p = state.pages[page];
		if (p.kind != PAGE_RGBA) {
			console.error(`void2d: page ${page} is ${pageKindName(p.kind)}, not Rgba`);
			return 0;
		}
		if (x < 0 || y < 0 || x >= p.size || y >= p.size) { return 0; }
		const t: int32 = (y * p.size + x) * 4;
		return (p.texels[t] as uint32) | ((p.texels[t + 1] as uint32) << 8) |
			((p.texels[t + 2] as uint32) << 16) | ((p.texels[t + 3] as uint32) << 24);
	}

	export function void2dGlyphPageBlitRgba(
		page: int32, x: int32, y: int32, w: int32, h: int32,
		texels: Readonly<Span<uint32>>, stride: int32,
	): int32 {
		if (!validPage(page) || w <= 0 || h <= 0 || stride < w ||
			(texels.length as int64) < ((h - 1) as int64) * (stride as int64) + (w as int64)) {
			return BLIT_BAD_HANDLE;
		}
		const p = state.pages[page];
		if (p.kind != PAGE_RGBA) {
			console.error(`void2d: an Rgba tile was aimed at a ${pageKindName(p.kind)} page`);
			return BLIT_WRONG_PAGE_KIND;
		}
		if (tileOutside(p, x, y, w, h)) {
			console.error(`void2d: Rgba tile ${w}x${h} at (${x},${y}) falls outside its ${p.size} page`);
			return BLIT_OUTSIDE_PAGE;
		}
		for (let row: int32 = 0; row < h; row++) {
			for (let col: int32 = 0; col < w; col++) {
				const value: uint32 = texels[row * stride + col];
				const t: int32 = ((y + row) * p.size + x + col) * 4;
				p.texels[t] = (value & 0xFF) as uint8;
				p.texels[t + 1] = ((value >> 8) & 0xFF) as uint8;
				p.texels[t + 2] = ((value >> 16) & 0xFF) as uint8;
				p.texels[t + 3] = ((value >> 24) & 0xFF) as uint8;
			}
		}
		markDirtyBox(p, x, y, w, h);
		return BLIT_OK;
	}
}

when (voidSvg) {
	export function void2dGlyphPageBlitMask(
		page: int32, x: int32, y: int32, w: int32, h: int32,
		alpha: Readonly<Span<uint8>>, stride: int32,
	): int32 {
		if (!validPage(page) || w <= 0 || h <= 0 || stride < w ||
			(alpha.length as int64) < ((h - 1) as int64) * (stride as int64) + (w as int64)) {
			return BLIT_BAD_HANDLE;
		}
		const p = state.pages[page];
		if (p.kind != PAGE_MASK) {
			console.error(`void2d: a mask tile was aimed at a ${pageKindName(p.kind)} page`);
			return BLIT_WRONG_PAGE_KIND;
		}
		if (tileOutside(p, x, y, w, h)) {
			console.error(`void2d: mask tile ${w}x${h} at (${x},${y}) falls outside its ${p.size} page`);
			return BLIT_OUTSIDE_PAGE;
		}
		for (let row: int32 = 0; row < h; row++) {
			for (let col: int32 = 0; col < w; col++) {
				p.texels[(y + row) * p.size + x + col] = alpha[row * stride + col];
			}
		}
		markDirtyBox(p, x, y, w, h);
		return BLIT_OK;
	}
}

export function void2dGlyphPageUploaded(page: int32): int32 {
	return validPage(page) && state.pages[page].uploaded ? 1 : 0;
}

export function void2dGlyphPageTakeUpload(page: int32): int32 {
	if (!validPage(page) || !state.pages[page].dirty || state.pages[page].uploaded) { return 0; }
	const p = state.pages[page];
	for (let k: int32 = 0; k < 4; k++) { p.takenBox[k] = p.dirtyBox[k]; }
	p.dirty = false;
	p.uploaded = true;
	return 1;
}

export function void2dGlyphPageUploadBox(page: int32): Vec<int32> {
	const taken = state.pages[page].takenBox;
	return [taken[0], taken[1], taken[2], taken[3]];
}

export function void2dGlyphPagesMarkDirty(): void {
	for (let page: int32 = 0; page < (state.pages.length as int32); page++) {
		if (state.pages[page].live) { markDirtyWhole(state.pages[page]); }
	}
}

export function void2dGlyphPagesFrameBegin(): void {
	for (let page: int32 = 0; page < (state.pages.length as int32); page++) {
		state.pages[page].uploaded = false;
	}
}
