import { needSlots, validFace } from "./faces";
import { markDirtyBox, pageKindName, tileOutside, validPage } from "./pages";
import {
	COLOUR_RASTER_BAD_HANDLE,
	COLOUR_RASTER_NO_MEMORY,
	COLOUR_RASTER_OK,
	COLOUR_RASTER_OUTSIDE_PAGE,
	COLOUR_RASTER_REFUSED,
	COLOUR_RASTER_WRONG_PAGE_KIND,
	GlyphFace,
	PAGE_RGBA,
	faceAt,
	fixed,
	state,
} from "./state";

when (voidColourEmoji) {
	import {
		ColourBox,
		ColourFace,
		ColourLayer,
		ColourSfnt,
		void2dColourCompose,
		void2dColourFaceGlyphIndex,
		void2dColourFaceHasLayers,
		void2dColourFaceOpen,
		void2dColourFaceReason,
		void2dColourFaceSfnt,
		void2dColourGlyphBox,
		void2dColourGlyphLayers,
		void2dColourGlyphRender,
	} from "../colourEmoji/colourFace.h";
	import { FontInfo, GlyphBox } from "../trueType/fontInfo";
	import { getGlyphBitmapBoxSubpixel, makeGlyphBitmapSubpixel } from "../trueType/rasterize";
	import { scaleForMappingEmToPixels } from "../trueType";
	import { u16At } from "../trueType/fontInfo";

	export const COLOUR_OK: int32 = 0;
	export const COLOUR_NONE: int32 = 1;
	export const COLOUR_BAD_TABLE: int32 = -1;
	export const COLOUR_NO_MEMORY: int32 = -2;

	const COLOUR_ABSENT: int32 = 0;
	const COLOUR_PRESENT: int32 = 1;
	const COLOUR_REFUSED: int32 = -1;
	const MAX_LAYERS: int32 = 256;
	const MAX_TEXELS: int64 = 4096 * 4096;

	export class ColourOpened {
		status: int32 = COLOUR_NONE;
		face: Ptr<void> | null = null;
		numGlyphs: int32 = 0;
		info: FontInfo | null = null;
	}

	export function colourReason(): string {
		return void2dColourFaceReason();
	}

	export function colourFaceGlyphIndex(colour: Ptr<void> | null, codepoint: int32): int32 {
		if (colour == null) { return 0; }
		return void2dColourFaceGlyphIndex(colour as Ptr<ColourFace>, codepoint);
	}

	export function colourOpen(bytes: uint8[], offset: int32): ColourOpened {
		const result = new ColourOpened();
		let opened: Ptr<ColourFace>;
		let status = void2dColourFaceOpen(bytes[0], bytes.length as uint64, offset as uint64, opened);
		let sfnt: ColourSfnt = { head: 0, hhea: 0, hmtx: 0, hmtxLength: 0, numGlyphs: 0, outlines: 0 };
		if (status == COLOUR_OK && void2dColourFaceSfnt(opened, sfnt) != COLOUR_OK) {
			status = COLOUR_BAD_TABLE;
		}
		result.status = status;
		if (status != COLOUR_OK) { return result; }
		result.face = opened as Ptr<void>;
		result.numGlyphs = sfnt.numGlyphs;
		const data = bytes as Span<uint8>;
		result.info = {
			data: data,
			fontstart: offset,
			numGlyphs: 0,
			loca: 0,
			head: sfnt.head as int32,
			glyf: 0,
			hhea: sfnt.hhea as int32,
			hmtx: sfnt.hmtx as int32,
			kern: 0,
			gpos: 0,
			svg: 0,
			indexMap: 0,
			indexToLocFormat: data.u16At((sfnt.head as int64) + 50),
			cff: { data: data, base: 0, size: 0, cursor: 0 },
			charstrings: { data: data, base: 0, size: 0, cursor: 0 },
			gsubrs: { data: data, base: 0, size: 0, cursor: 0 },
			subrs: { data: data, base: 0, size: 0, cursor: 0 },
			fontdicts: { data: data, base: 0, size: 0, cursor: 0 },
			fdselect: { data: data, base: 0, size: 0, cursor: 0 },
		};
		return result;
	}

	function colourPtr(f: GlyphFace): Ptr<ColourFace> {
		const colour = f.colour;
		if (colour == null) { throw new Error("void2d: a colour call reached a face with no colour tables"); }
		return colour as Ptr<ColourFace>;
	}

	function layersOf(f: GlyphFace, glyph: int32, layers: ColourLayer[]): int32 {
		return void2dColourGlyphLayers(
			colourPtr(f), glyph, (layers as Span<ColourLayer>) as Ptr<ColourLayer>, MAX_LAYERS,
		);
	}

	function newLayers(): ColourLayer[] {
		return new Array<ColourLayer>(MAX_LAYERS);
	}

	export function void2dGlyphColourBuilt(): int32 {
		return 1;
	}

	export function void2dGlyphColourFace(face: int32): int32 {
		return validFace(face) && state.faces[face].colour != null ? 1 : 0;
	}

	struct LayerBox {
		status: int32;
		box: GlyphBox;
	}

	function colourLayerBox(f: GlyphFace, glyph: int32, sizePx: float32): LayerBox {
		const layers = newLayers();
		const count = layersOf(f, glyph, layers);
		const none: GlyphBox = { x0: 0, y0: 0, x1: 0, y1: 0 };
		if (count < 0) { return { status: COLOUR_REFUSED, box: none }; }
		const scale = scaleForMappingEmToPixels(f.info, sizePx);
		let box: GlyphBox = none;
		let inked: boolean = false;
		for (let i: int32 = 0; i < count; i++) {
			const b = getGlyphBitmapBoxSubpixel(f.info, layers[i].glyph, scale, scale, 0.0, 0.0);
			if (b.x1 <= b.x0 || b.y1 <= b.y0) { continue; }
			if (!inked || b.x0 < box.x0) { box.x0 = b.x0; }
			if (!inked || b.y0 < box.y0) { box.y0 = b.y0; }
			if (!inked || b.x1 > box.x1) { box.x1 = b.x1; }
			if (!inked || b.y1 > box.y1) { box.y1 = b.y1; }
			inked = true;
		}
		if (!inked) { return { status: COLOUR_ABSENT, box: box }; }
		if (((box.x1 - box.x0) as int64) * ((box.y1 - box.y0) as int64) > MAX_TEXELS) {
			console.error(
				`void2d: colour glyph ${glyph} is ${box.x1 - box.x0}x${box.y1 - box.y0} at ${fixed(sizePx, 1)} px, over the ${MAX_TEXELS} texel limit`,
			);
			return { status: COLOUR_REFUSED, box: box };
		}
		return { status: COLOUR_PRESENT, box: box };
	}

	export function void2dGlyphColourBox(face: int32, glyph: int32, sizePx: float32, box: Span<int32>): void {
		needSlots("void2dGlyphColourBox", box.length as int64, 6);
		for (let i: int32 = 0; i < 6; i++) { box[i] = 0; }
		if (void2dGlyphColourFace(face) == 0) { return; }
		const f = faceAt(face);
		let found: ColourBox = { width: 0, height: 0, bearingX: 0, bearingY: 0, ppem: 0 };
		let status = void2dColourGlyphBox(colourPtr(f), glyph, sizePx, found);
		if (status == COLOUR_PRESENT) {
			box[0] = found.bearingX;
			box[1] = -found.bearingY;
			box[2] = found.bearingX + found.width;
			box[3] = -found.bearingY + found.height;
			box[5] = found.ppem;
		} else if (status == COLOUR_ABSENT && glyph > 0 && sizePx > 0.0 &&
			void2dColourFaceHasLayers(colourPtr(f)) != 0) {
			const layered = colourLayerBox(f, glyph, sizePx);
			status = layered.status;
			if (status == COLOUR_PRESENT) {
				box[0] = layered.box.x0;
				box[1] = layered.box.y0;
				box[2] = layered.box.x1;
				box[3] = layered.box.y1;
			}
		}
		box[4] = status;
	}

	export function void2dGlyphColourLayerCount(face: int32, glyph: int32): int32 {
		if (void2dGlyphColourFace(face) == 0) { return 0; }
		return layersOf(state.faces[face], glyph, newLayers());
	}

	export function void2dGlyphColourLayerGlyph(face: int32, glyph: int32, index: int32): int32 {
		if (void2dGlyphColourFace(face) == 0) { return -1; }
		const layers = newLayers();
		const count = layersOf(state.faces[face], glyph, layers);
		return index >= 0 && index < count ? layers[index].glyph : -1;
	}

	export function void2dGlyphColourLayerRgba(face: int32, glyph: int32, index: int32): uint32 {
		if (void2dGlyphColourFace(face) == 0) { return 0; }
		const layers = newLayers();
		const count = layersOf(state.faces[face], glyph, layers);
		if (index < 0 || index >= count) { return 0; }
		const l = layers[index];
		return (l.r as uint32) | ((l.g as uint32) << 8) | ((l.b as uint32) << 16) | ((l.a as uint32) << 24);
	}

	function colourLayerRasterize(
		f: GlyphFace, glyph: int32, sizePx: float32, at: uint32[], w: int32, h: int32,
	): int32 {
		const layered = colourLayerBox(f, glyph, sizePx);
		const box = layered.box;
		if (layered.status != COLOUR_PRESENT || box.x1 - box.x0 != w || box.y1 - box.y0 != h) {
			console.error(`void2d: colour tile ${w}x${h} does not match glyph ${glyph}'s layer box`);
			return COLOUR_RASTER_REFUSED;
		}
		const layers = newLayers();
		const count = layersOf(f, glyph, layers);
		if (count < 0) { return COLOUR_RASTER_REFUSED; }
		for (let i: int32 = 0; i < w * h; i++) { at[i] = 0; }
		const scale = scaleForMappingEmToPixels(f.info, sizePx);
		for (let i: int32 = 0; i < count; i++) {
			const b = getGlyphBitmapBoxSubpixel(f.info, layers[i].glyph, scale, scale, 0.0, 0.0);
			const lw = b.x1 - b.x0;
			const lh = b.y1 - b.y0;
			if (lw <= 0 || lh <= 0) { continue; }
			const coverage: uint8[] = new Array<uint8>(lw * lh);
			for (let z: int32 = 0; z < lw * lh; z++) { coverage[z] = 0; }
			makeGlyphBitmapSubpixel(f.info, coverage, lw, lh, lw, scale, scale, 0.0, 0.0, layers[i].glyph);
			void2dColourCompose(
				(at as Span<uint32>) as Ptr<uint32>, w, w, h, coverage[0], lw,
				b.x0 - box.x0, b.y0 - box.y0, lw, lh, layers[i],
			);
		}
		return COLOUR_RASTER_OK;
	}

	export function void2dGlyphColourRasterize(
		face: int32, glyph: int32, sizePx: float32, page: int32, x: int32, y: int32, w: int32, h: int32,
	): int32 {
		if (void2dGlyphColourFace(face) == 0 || !validPage(page) || w <= 0 || h <= 0) {
			return COLOUR_RASTER_BAD_HANDLE;
		}
		const p = state.pages[page];
		if (p.kind != PAGE_RGBA) {
			console.error(`void2d: a colour tile was aimed at a ${pageKindName(p.kind)} page`);
			return COLOUR_RASTER_WRONG_PAGE_KIND;
		}
		if (tileOutside(p, x, y, w, h)) {
			console.error(`void2d: colour tile ${w}x${h} at (${x},${y}) falls outside its ${p.size} page`);
			return COLOUR_RASTER_OUTSIDE_PAGE;
		}
		const f = faceAt(face);
		const tile: uint32[] = new Array<uint32>(w * h);
		for (let row: int32 = 0; row < h; row++) {
			for (let col: int32 = 0; col < w; col++) {
				const t: int32 = ((y + row) * p.size + x + col) * 4;
				tile[row * w + col] = (p.texels[t] as uint32) | ((p.texels[t + 1] as uint32) << 8) |
					((p.texels[t + 2] as uint32) << 16) | ((p.texels[t + 3] as uint32) << 24);
			}
		}
		let status = void2dColourGlyphRender(
			colourPtr(f), glyph, sizePx, (tile as Span<uint32>) as Ptr<uint32>, w, w, h,
		);
		let result: int32 = COLOUR_RASTER_OK;
		if (status == COLOUR_ABSENT && void2dColourFaceHasLayers(colourPtr(f)) != 0) {
			result = colourLayerRasterize(f, glyph, sizePx, tile, w, h);
			if (result != COLOUR_RASTER_OK) { return result; }
		} else if (status == COLOUR_NO_MEMORY) {
			return COLOUR_RASTER_NO_MEMORY;
		} else if (status != COLOUR_PRESENT) {
			return COLOUR_RASTER_REFUSED;
		}
		for (let row: int32 = 0; row < h; row++) {
			for (let col: int32 = 0; col < w; col++) {
				const value: uint32 = tile[row * w + col];
				const t: int32 = ((y + row) * p.size + x + col) * 4;
				p.texels[t] = (value & 0xFF) as uint8;
				p.texels[t + 1] = ((value >> 8) & 0xFF) as uint8;
				p.texels[t + 2] = ((value >> 16) & 0xFF) as uint8;
				p.texels[t + 3] = ((value >> 24) & 0xFF) as uint8;
			}
		}
		markDirtyBox(p, x, y, w, h);
		return COLOUR_RASTER_OK;
	}
} else {
	export function void2dGlyphColourBuilt(): int32 {
		return 0;
	}

	export function void2dGlyphColourFace(face: int32): int32 {
		return 0;
	}

	export function void2dGlyphColourBox(face: int32, glyph: int32, sizePx: float32, box: Span<int32>): void {
		needSlots("void2dGlyphColourBox", box.length as int64, 6);
		for (let i: int32 = 0; i < 6; i++) { box[i] = 0; }
	}

	export function void2dGlyphColourRasterize(
		face: int32, glyph: int32, sizePx: float32, page: int32, x: int32, y: int32, w: int32, h: int32,
	): int32 {
		console.error("void2d: a colour tile was asked for but -d:voidColourEmoji is not built");
		return COLOUR_RASTER_REFUSED;
	}

	export function void2dGlyphColourLayerCount(face: int32, glyph: int32): int32 {
		return 0;
	}

	export function void2dGlyphColourLayerGlyph(face: int32, glyph: int32, index: int32): int32 {
		return -1;
	}

	export function void2dGlyphColourLayerRgba(face: int32, glyph: int32, index: int32): uint32 {
		return 0;
	}
}
