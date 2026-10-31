import { needSlots, validFace } from "./faces";
import { pageKindName, tileOutside, validPage } from "./pages";
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
		COLOUR_ABSENT,
		COLOUR_BAD_TABLE,
		COLOUR_MAX_LAYERS,
		COLOUR_MAX_TEXELS,
		COLOUR_NO_MEMORY,
		COLOUR_NONE,
		COLOUR_OK,
		COLOUR_PRESENT,
		COLOUR_REFUSED,
		ColourBox,
		ColourFace,
		ColourLayer,
		ColourSfnt,
		colourCompose,
		colourFaceGlyphIndex as faceGlyphIndex,
		colourFaceHasLayers,
		colourFaceOpen,
		colourFaceSfnt,
		colourGlyphBox,
		colourGlyphLayers,
		colourGlyphRender,
	} from "../colourEmoji/colourFace";
	import { FontInfo, GlyphBox } from "../trueType/fontInfo";
	import {
		getGlyphBitmapBoxSubpixel,
		makeGlyphBitmapSubpixel,
	} from "../trueType/rasterize";
	import { scaleForMappingEmToPixels } from "../trueType";
	import { u16At } from "../trueType/fontInfo";
	import { rgbaTexelAt, writeRgbaTile } from "./pages";
	import { blankInfo } from "./state";

	export class ColourOpened {
		status: int32 = COLOUR_NONE;
		face: ColourFace | null = null;
		numGlyphs: int32 = 0;
		head: int32 = 0;
		hhea: int32 = 0;
		hmtx: int32 = 0;
	}

	export function colourFaceGlyphIndex(
		handle: int32,
		bytes: uint8[],
		codepoint: int32,
	): int32 {
		return faceGlyphIndex(
			handle < 0 ? null : colourTable[handle],
			bytes,
			codepoint,
		);
	}

	const colourTable: ColourFace[] = [];

	export function colourRegister(face: ColourFace | null): int32 {
		if (face == null) {
			return -1;
		}
		colourTable.push(face);
		return (colourTable.length as int32) - 1;
	}

	export function colourOpen(bytes: uint8[], offset: int32): ColourOpened {
		const result = new ColourOpened();
		const opened = colourFaceOpen(bytes, offset as int64);
		let status = opened.status;
		const sfnt = new ColourSfnt();
		const face = opened.face;
		if (
			status == COLOUR_OK &&
			face != null &&
			colourFaceSfnt(face, bytes, sfnt) != COLOUR_OK
		) {
			status = COLOUR_BAD_TABLE;
		}
		result.status = status;
		if (status != COLOUR_OK) {
			return result;
		}
		result.face = face;
		result.numGlyphs = sfnt.numGlyphs;
		result.head = sfnt.head as int32;
		result.hhea = sfnt.hhea as int32;
		result.hmtx = sfnt.hmtx as int32;
		return result;
	}

	// The metrics-only face of a colour font with no outlines.
	export function colourInfo(
		bytes: uint8[],
		offset: int32,
		head: int32,
		hhea: int32,
		hmtx: int32,
	): FontInfo {
		const data = bytes as Span<uint8>;
		let info = blankInfo(data);
		info.fontstart = offset;
		info.head = head;
		info.hhea = hhea;
		info.hmtx = hmtx;
		info.indexToLocFormat = data.u16At((head as int64) + 50);
		return info;
	}

	function colourOf(f: GlyphFace): ColourFace {
		if (f.colourHandle < 0) {
			throw new Error(
				"void2d: a colour call reached a face with no colour tables",
			);
		}
		return colourTable[f.colourHandle];
	}

	function layersOf(f: GlyphFace, glyph: int32, layers: ColourLayer[]): int32 {
		return colourGlyphLayers(
			colourOf(f),
			f.bytes.data,
			glyph,
			layers,
			COLOUR_MAX_LAYERS,
		);
	}

	function newLayers(): ColourLayer[] {
		return new Array<ColourLayer>(COLOUR_MAX_LAYERS);
	}

	export function void2dGlyphColourBuilt(): int32 {
		return 1;
	}

	export function void2dGlyphColourFace(face: int32): int32 {
		return validFace(face) && state.faces[face].colourHandle >= 0 ? 1 : 0;
	}

	struct LayerBox {
		status: int32;
		box: GlyphBox;
	}

	function colourLayerBox(
		f: GlyphFace,
		glyph: int32,
		sizePx: float32,
	): LayerBox {
		const layers = newLayers();
		const count = layersOf(f, glyph, layers);
		const none: GlyphBox = { x0: 0, y0: 0, x1: 0, y1: 0 };
		if (count < 0) {
			return { status: COLOUR_REFUSED, box: none };
		}
		const scale = scaleForMappingEmToPixels(f.info, sizePx);
		let box: GlyphBox = none;
		let inked: boolean = false;
		for (let i: int32 = 0; i < count; i++) {
			const ink = getGlyphBitmapBoxSubpixel(
				f.info,
				layers[i].glyph,
				scale,
				scale,
				0.0,
				0.0,
			);
			if (ink.x1 <= ink.x0 || ink.y1 <= ink.y0) {
				continue;
			}
			if (!inked || ink.x0 < box.x0) {
				box.x0 = ink.x0;
			}
			if (!inked || ink.y0 < box.y0) {
				box.y0 = ink.y0;
			}
			if (!inked || ink.x1 > box.x1) {
				box.x1 = ink.x1;
			}
			if (!inked || ink.y1 > box.y1) {
				box.y1 = ink.y1;
			}
			inked = true;
		}
		if (!inked) {
			return { status: COLOUR_ABSENT, box: box };
		}
		if (
			((box.x1 - box.x0) as int64) * ((box.y1 - box.y0) as int64) >
			COLOUR_MAX_TEXELS
		) {
			console.error(
				`void2d: colour glyph ${glyph} is ${box.x1 - box.x0}x${box.y1 - box.y0} at ${fixed(sizePx, 1)} px, over the ${COLOUR_MAX_TEXELS} texel limit`,
			);
			return { status: COLOUR_REFUSED, box: box };
		}
		return { status: COLOUR_PRESENT, box: box };
	}

	export function void2dGlyphColourBox(
		face: int32,
		glyph: int32,
		sizePx: float32,
		box: Span<int32>,
	): void {
		needSlots("void2dGlyphColourBox", box.length as int64, 6);
		for (let i: int32 = 0; i < 6; i++) {
			box[i] = 0;
		}
		if (void2dGlyphColourFace(face) == 0) {
			return;
		}
		const f = faceAt(face);
		const found = new ColourBox();
		let status = colourGlyphBox(
			colourOf(f),
			f.bytes.data,
			glyph,
			sizePx,
			found,
		);
		if (status == COLOUR_PRESENT) {
			box[0] = found.bearingX;
			box[1] = -found.bearingY;
			box[2] = found.bearingX + found.width;
			box[3] = -found.bearingY + found.height;
			box[5] = found.ppem;
		} else if (
			status == COLOUR_ABSENT &&
			glyph > 0 &&
			sizePx > 0.0 &&
			colourFaceHasLayers(colourOf(f))
		) {
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

	export function void2dGlyphColourLayerCount(
		face: int32,
		glyph: int32,
	): int32 {
		if (void2dGlyphColourFace(face) == 0) {
			return 0;
		}
		return layersOf(state.faces[face], glyph, newLayers());
	}

	export function void2dGlyphColourLayerGlyph(
		face: int32,
		glyph: int32,
		index: int32,
	): int32 {
		if (void2dGlyphColourFace(face) == 0) {
			return -1;
		}
		const layers = newLayers();
		const count = layersOf(state.faces[face], glyph, layers);
		return index >= 0 && index < count ? layers[index].glyph : -1;
	}

	export function void2dGlyphColourLayerRgba(
		face: int32,
		glyph: int32,
		index: int32,
	): uint32 {
		if (void2dGlyphColourFace(face) == 0) {
			return 0;
		}
		const layers = newLayers();
		const count = layersOf(state.faces[face], glyph, layers);
		if (index < 0 || index >= count) {
			return 0;
		}
		const layer = layers[index];
		return (
			(layer.r as uint32) |
			((layer.g as uint32) << 8) |
			((layer.b as uint32) << 16) |
			((layer.a as uint32) << 24)
		);
	}

	function colourLayerRasterize(
		f: GlyphFace,
		glyph: int32,
		sizePx: float32,
		tile: uint32[],
		w: int32,
		h: int32,
	): int32 {
		const layered = colourLayerBox(f, glyph, sizePx);
		const box = layered.box;
		if (
			layered.status != COLOUR_PRESENT ||
			box.x1 - box.x0 != w ||
			box.y1 - box.y0 != h
		) {
			console.error(
				`void2d: colour tile ${w}x${h} does not match glyph ${glyph}'s layer box`,
			);
			return COLOUR_RASTER_REFUSED;
		}
		const layers = newLayers();
		const count = layersOf(f, glyph, layers);
		if (count < 0) {
			return COLOUR_RASTER_REFUSED;
		}
		for (let i: int32 = 0; i < w * h; i++) {
			tile[i] = 0;
		}
		const scale = scaleForMappingEmToPixels(f.info, sizePx);
		for (let i: int32 = 0; i < count; i++) {
			const ink = getGlyphBitmapBoxSubpixel(
				f.info,
				layers[i].glyph,
				scale,
				scale,
				0.0,
				0.0,
			);
			const inkWidth = ink.x1 - ink.x0;
			const inkHeight = ink.y1 - ink.y0;
			if (inkWidth <= 0 || inkHeight <= 0) {
				continue;
			}
			const coverage: uint8[] = new Array<uint8>(inkWidth * inkHeight);
			for (let texel: int32 = 0; texel < inkWidth * inkHeight; texel++) {
				coverage[texel] = 0;
			}
			makeGlyphBitmapSubpixel(
				f.info,
				coverage,
				inkWidth,
				inkHeight,
				inkWidth,
				scale,
				scale,
				0.0,
				0.0,
				layers[i].glyph,
			);
			colourCompose(
				tile,
				w,
				w,
				h,
				coverage,
				inkWidth,
				ink.x0 - box.x0,
				ink.y0 - box.y0,
				inkWidth,
				inkHeight,
				layers[i],
			);
		}
		return COLOUR_RASTER_OK;
	}

	export function void2dGlyphColourRasterize(
		face: int32,
		glyph: int32,
		sizePx: float32,
		page: int32,
		x: int32,
		y: int32,
		w: int32,
		h: int32,
	): int32 {
		if (
			void2dGlyphColourFace(face) == 0 || !validPage(page) || w <= 0 || h <= 0
		) {
			return COLOUR_RASTER_BAD_HANDLE;
		}
		const p = state.pages[page];
		if (p.kind != PAGE_RGBA) {
			console.error(
				`void2d: a colour tile was aimed at a ${pageKindName(p.kind)} page`,
			);
			return COLOUR_RASTER_WRONG_PAGE_KIND;
		}
		if (tileOutside(p, x, y, w, h)) {
			console.error(
				`void2d: colour tile ${w}x${h} at (${x},${y}) falls outside its ${p.size} page`,
			);
			return COLOUR_RASTER_OUTSIDE_PAGE;
		}
		const f = faceAt(face);
		const tile: uint32[] = new Array<uint32>(w * h);
		for (let row: int32 = 0; row < h; row++) {
			for (let col: int32 = 0; col < w; col++) {
				tile[row * w + col] = rgbaTexelAt(p, x + col, y + row);
			}
		}
		const status = colourGlyphRender(
			colourOf(f),
			f.bytes.data,
			glyph,
			sizePx,
			tile,
			w,
			w,
			h,
		);
		if (status == COLOUR_ABSENT && colourFaceHasLayers(colourOf(f))) {
			const layered = colourLayerRasterize(f, glyph, sizePx, tile, w, h);
			if (layered != COLOUR_RASTER_OK) {
				return layered;
			}
		} else if (status == COLOUR_NO_MEMORY) {
			return COLOUR_RASTER_NO_MEMORY;
		} else if (status != COLOUR_PRESENT) {
			return COLOUR_RASTER_REFUSED;
		}
		writeRgbaTile(p, x, y, w, h, tile, w);
		return COLOUR_RASTER_OK;
	}
} else {
	export function void2dGlyphColourBuilt(): int32 {
		return 0;
	}

	export function void2dGlyphColourFace(face: int32): int32 {
		return 0;
	}

	export function void2dGlyphColourBox(
		face: int32,
		glyph: int32,
		sizePx: float32,
		box: Span<int32>,
	): void {
		needSlots("void2dGlyphColourBox", box.length as int64, 6);
		for (let i: int32 = 0; i < 6; i++) {
			box[i] = 0;
		}
	}

	export function void2dGlyphColourRasterize(
		face: int32,
		glyph: int32,
		sizePx: float32,
		page: int32,
		x: int32,
		y: int32,
		w: int32,
		h: int32,
	): int32 {
		console.error(
			"void2d: a colour tile was asked for but -d:voidColourEmoji is not built",
		);
		return COLOUR_RASTER_REFUSED;
	}

	export function void2dGlyphColourLayerCount(
		face: int32,
		glyph: int32,
	): int32 {
		return 0;
	}

	export function void2dGlyphColourLayerGlyph(
		face: int32,
		glyph: int32,
		index: int32,
	): int32 {
		return -1;
	}

	export function void2dGlyphColourLayerRgba(
		face: int32,
		glyph: int32,
		index: int32,
	): uint32 {
		return 0;
	}
}
