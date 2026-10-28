import {
	FontInfo,
	GlyphBox,
	Vertex,
	findGlyphIndex,
	getFontOffsetForIndex,
	getFontVMetrics,
	getGlyphBox,
	getGlyphHMetrics,
	getGlyphKernInfoAdvance,
	getGlyphShape,
	initFont,
	i16At,
	scaleForMappingEmToPixels,
	u16At,
	u32At,
} from "../trueType";
import { hasTag } from "../trueType/fontInfo";
import { getGlyphBitmapBoxSubpixel } from "../trueType/rasterize";
import { sfntSourceRead, sfntSourceSize } from "../sfntSource";
import {
	FACE_NOT_A_FONT,
	FACE_NO_BASE,
	FACE_UNREADABLE,
	FaceBytes,
	FaceHeights,
	GlyphFace,
	ITALIC_SKEW,
	blankInfo,
	faceAt,
	fixed,
	state,
} from "./state";
import { findKernLookups, gposKern } from "./gpos";
import { applySynthetic, shapeBox } from "./outline";
import { asInt32, truncInt } from "../trueType/fontInfo";

when (voidColourEmoji) {
	import { colourFaceGlyphIndex, colourInfo, colourOpen, colourReason, colourRegister } from "./colour";
	import { COLOUR_NONE, COLOUR_NO_MEMORY, COLOUR_OK } from "../colourEmoji/colourFace";
	import { FACE_BAD_COLOUR, FACE_NO_MEMORY } from "./state";
}

when (voidSprites) {
	import { spriteCanvasInk, spriteIndex } from "../spriteGlyph";
}

when (macos || ios) {
	import {
		platformBox,
		platformInfo,
		platformOpen,
		platformUnitsBox,
		postScriptName,
	} from "./platform";
}

export function needSlots(op: string, count: int64, need: int32): void {
	if (count >= (need as int64)) { return; }
	throw new Error(`void2d: ${op} writes ${need} values into a span of ${count}`);
}

export function validFace(face: int32): boolean {
	return face >= 0 && face < (state.faces.length as int32);
}

export function isSynthetic(face: GlyphFace): boolean {
	return face.emboldenUnits > 0.0 || face.skew != 0.0;
}

function readWholeFile(path: string): uint8[] | null {
	const size = sfntSourceSize(path);
	if (size <= 0) { return null; }
	let bytes: uint8[] = new Array<uint8>(size as int32);
	if (!sfntSourceRead(path, 0, bytes)) { return null; }
	return bytes;
}

struct TableSlice {
	offset: int64;
	length: int32;
}

function findTableSlice(face: GlyphFace, tag: string): TableSlice {
	const data = face.info.data;
	const font: int64 = face.info.fontstart as int64;
	const tables = data.u16At(font + 4);
	for (let i: int32 = 0; i < tables; i++) {
		const record: int64 = font + 12 + 16 * (i as int64);
		if (!data.hasTag(record, tag)) { continue; }
		return { offset: data.u32At(record + 8), length: asInt32(data.u32At(record + 12)) };
	}
	return { offset: -1, length: 0 };
}

export function findGlyph(face: GlyphFace, codepoint: int32): int32 {
	state.glyphLookups++;
	when (voidColourEmoji) {
		if (face.colourOnly) { return colourFaceGlyphIndex(face.colourHandle, face.bytes.data, codepoint); }
	}
	return findGlyphIndex(face.info, codepoint);
}

export function void2dGlyphLookups(): uint32 {
	return state.glyphLookups;
}

struct Ink {
	present: boolean;
	x0: int32;
	y0: int32;
	x1: int32;
	y1: int32;
}

function glyphInk(face: GlyphFace, glyph: int32): Ink {
	when (macos || ios) {
		const platform = face.platform;
		if (platform != null) {
			const box = platformUnitsBox(platform, glyph);
			return {
				present: box[2] > box[0] && box[3] > box[1],
				x0: truncInt(Math.floor(box[0] as float64)),
				y0: truncInt(Math.floor(box[1] as float64)),
				x1: truncInt(Math.ceil(box[2] as float64)),
				y1: truncInt(Math.ceil(box[3] as float64)),
			};
		}
	}
	const box = getGlyphBox(face.info, glyph);
	if (box == null) { return { present: false, x0: 0, y0: 0, x1: 0, y1: 0 }; }
	return { present: true, x0: box.x0, y0: box.y0, x1: box.x1, y1: box.y1 };
}

function glyphHeight(face: GlyphFace, codepoint: int32): float32 {
	const glyph = findGlyph(face, codepoint);
	if (glyph == 0) { return 0.0; }
	const ink = glyphInk(face, glyph);
	if (!ink.present) { return 0.0; }
	return (ink.y1 - ink.y0) as float32;
}

struct AsciiExtent {
	height: float32;
	cellWidth: float32;
}

function asciiExtent(face: GlyphFace): AsciiExtent {
	let top: int32 = 0;
	let bottom: int32 = 0;
	let widest: int32 = 0;
	for (let c: int32 = 32; c < 127; c++) {
		const glyph = findGlyph(face, c);
		if (glyph == 0) { continue; }
		const metrics = getGlyphHMetrics(face.info, glyph);
		if (metrics.advance > widest) { widest = metrics.advance; }
		const ink = glyphInk(face, glyph);
		if (ink.present) {
			if (ink.y1 > top) { top = ink.y1; }
			if (ink.y0 < bottom) { bottom = ink.y0; }
		}
	}
	return { height: (top - bottom) as float32, cellWidth: widest as float32 };
}

function ideographWidth(face: GlyphFace): float32 {
	const glyph = findGlyph(face, 0x6C34);
	if (glyph == 0) { return 0.0; }
	const metrics = getGlyphHMetrics(face.info, glyph);
	const ink = glyphInk(face, glyph);
	if (ink.present && ink.x1 - ink.x0 > metrics.advance) { return 0.0; }
	return metrics.advance as float32;
}

function measureHeights(face: GlyphFace): FaceHeights {
	const vertical = getFontVMetrics(face.info);
	const ascent = vertical.ascent;
	const os2 = findTableSlice(face, "OS/2");
	const data = face.info.data;
	let ex: float32 = 0.0;
	let cap: float32 = 0.0;
	if (os2.offset >= 0 && data.u16At(os2.offset) >= 2 && os2.length >= 90) {
		ex = data.i16At(os2.offset + 86) as float32;
		cap = data.i16At(os2.offset + 88) as float32;
	} else {
		ex = glyphHeight(face, 120);
		cap = glyphHeight(face, 72);
	}
	const ic = ideographWidth(face);
	const capEstimate: float32 = cap > 0.0 ? cap : 0.75 * (ascent as float32);
	const exEstimate: float32 = ex > 0.0 ? ex : 0.75 * capEstimate;
	const extent = asciiExtent(face);
	let asciiHeight: float32 = extent.height;
	if (asciiHeight <= 0.0) { asciiHeight = 1.5 * capEstimate; }
	const twoCells: float32 = 2.0 * extent.cellWidth;
	const icEstimate: float32 = ic > 0.0 ? ic : (asciiHeight < twoCells ? asciiHeight : twoCells);
	return {
		cap: cap,
		ex: ex,
		ic: ic,
		capEstimate: capEstimate,
		exEstimate: exEstimate,
		icEstimate: icEstimate,
		lineHeight: (vertical.ascent - vertical.descent + vertical.lineGap) as float32,
	};
}

function measureFace(face: GlyphFace): void {
	if (face.measured) { return; }
	face.heights = measureHeights(face);
	let post = findTableSlice(face, "post");
	let os2 = findTableSlice(face, "OS/2");
	const data = face.info.data;
	const hasPost = post.offset >= 0 && post.length >= 12;
	const hasOs2 = os2.offset >= 0 && os2.length >= 30;
	const exHeight: float32 = face.heights.exEstimate;
	const underlinePosition = hasPost ? data.i16At(post.offset + 8) : 0;
	const underlineSize = hasPost ? data.i16At(post.offset + 10) : 0;
	face.underlineThickness = underlineSize > 0 ? (underlineSize as float32) : 0.15 * exHeight;
	face.underlineTop = hasPost && (underlineSize != 0 || underlinePosition != 0)
		? (underlinePosition as float32) : -face.underlineThickness;
	const strikeSize = hasOs2 ? data.i16At(os2.offset + 26) : 0;
	const strikePosition = hasOs2 ? data.i16At(os2.offset + 28) : 0;
	face.strikeThickness = strikeSize > 0 ? (strikeSize as float32) : face.underlineThickness;
	face.strikeTop = hasOs2 && (strikeSize != 0 || strikePosition != 0)
		? (strikePosition as float32) : (exHeight + face.strikeThickness) * 0.5;
	face.measured = true;
}

export function void2dGlyphScale(face: int32, sizePx: float32): float32 {
	if (!validFace(face)) { return 0.0; }
	return scaleForMappingEmToPixels(state.faces[face].info, sizePx);
}

export function void2dGlyphFaceHeights(face: int32, out: Span<float32>): void {
	needSlots("void2dGlyphFaceHeights", out.length as int64, 7);
	for (let i: int32 = 0; i < 7; i++) { out[i] = 0.0; }
	if (!validFace(face)) { return; }
	const f = faceAt(face);
	measureFace(f);
	const h = f.heights;
	const perEm = void2dGlyphScale(face, 1.0);
	out[0] = (h.ic > 0.0 ? h.ic : 0.0) * perEm;
	out[1] = (h.ex > 0.0 ? h.ex : 0.0) * perEm;
	out[2] = (h.cap > 0.0 ? h.cap : 0.0) * perEm;
	out[3] = h.icEstimate * perEm;
	out[4] = h.exEstimate * perEm;
	out[5] = h.capEstimate * perEm;
	out[6] = h.lineHeight * perEm;
}

export function void2dGlyphDecoration(face: int32, sizePx: float32, out: Span<float32>): void {
	needSlots("void2dGlyphDecoration", out.length as int64, 4);
	out[0] = 0.0;
	out[1] = 0.0;
	out[2] = 0.0;
	out[3] = 0.0;
	if (!validFace(face)) { return; }
	const f = faceAt(face);
	measureFace(f);
	const scale = void2dGlyphScale(face, sizePx);
	out[0] = -f.underlineTop * scale;
	out[1] = f.underlineThickness * scale;
	out[2] = -f.strikeTop * scale;
	out[3] = f.strikeThickness * scale;
}

export function void2dGlyphFaceLoad(path: string, index: int32): int32 {
	const bytes = readWholeFile(path);
	if (bytes == null) {
		console.error(`void2d: cannot read font file ${path}`);
		return FACE_UNREADABLE;
	}
	const holder = new FaceBytes(bytes);
	const face = new GlyphFace(holder, blankInfo(holder.data));
	const offset = getFontOffsetForIndex(holder.data, index);
	let colourHandle: int32 = -1;
	let colourStatus: int32 = 1;
	let colourGlyphs: int32 = 0;
	let colourHead: int32 = 0;
	let colourHhea: int32 = 0;
	let colourHmtx: int32 = 0;
	when (voidColourEmoji) {
		if (offset >= 0) {
			const opened = colourOpen(holder.data, offset);
			colourStatus = opened.status;
			colourGlyphs = opened.numGlyphs;
			colourHead = opened.head;
			colourHhea = opened.hhea;
			colourHmtx = opened.hmtx;
			colourHandle = colourRegister(opened.face);
		}
	}
	let found: FontInfo | null = offset >= 0 ? initFont(holder.data, offset) : null;
	let colourOnly: boolean = false;
	let glyphCount: int32 = 0;
	let outlines: boolean = found != null;
	when (voidColourEmoji) {
		if (colourStatus == COLOUR_OK) {
			glyphCount = colourGlyphs;
			if (!outlines) {
				found = colourInfo(holder.data, offset, colourHead, colourHhea, colourHmtx);
				colourOnly = true;
				outlines = true;
			}
		} else if (colourStatus != COLOUR_NONE) {
			console.error(`void2d: ${path}: colour tables refused: ${colourReason()}`);
			if (!outlines) {
				return colourStatus == COLOUR_NO_MEMORY ? FACE_NO_MEMORY : FACE_BAD_COLOUR;
			}
		}
	}
	let platform: Ptr<void> | null = null;
	when (macos || ios) {
		if (!outlines && offset >= 0) {
			const table = platformInfo(holder.data, offset);
			if (table != null) {
				found = table.info;
				glyphCount = table.glyphCount;
				const name = postScriptName(holder.data, offset);
				if (name != "") {
					platform = platformOpen(path, holder.data, name, glyphCount, table.unitsPerEm);
				}
				if (platform == null) {
					console.error(
						`void2d: ${path} has no outlines Void reads and the OS does not open face ${index}`,
					);
				}
				outlines = platform != null;
			}
		}
	}
	if (!outlines || found == null) {
		console.error(`void2d: ${path} is not a font stb_truetype can read`);
		return FACE_NOT_A_FONT;
	}
	face.info = found;
	face.colourOnly = colourOnly;
	face.platform = platform;
	face.glyphCount = glyphCount;
	face.kernLookups = findKernLookups(found);
	face.colourHandle = colourHandle;
	state.faces.push(face);
	return (state.faces.length as int32) - 1;
}

function copyFace(base: GlyphFace): GlyphFace {
	const face = new GlyphFace(base.bytes, base.info);
	face.kernLookups = base.kernLookups;
	face.emboldenUnits = base.emboldenUnits;
	face.skew = base.skew;
	face.measured = base.measured;
	face.colourHandle = base.colourHandle;
	face.colourOnly = base.colourOnly;
	face.sprite = base.sprite;
	face.platform = base.platform;
	face.asciiUnits = base.asciiUnits;
	face.glyphCount = base.glyphCount;
	face.heights = base.heights;
	face.underlineTop = base.underlineTop;
	face.underlineThickness = base.underlineThickness;
	face.strikeTop = base.strikeTop;
	face.strikeThickness = base.strikeThickness;
	return face;
}

export function void2dGlyphFaceSynthetic(face: int32, bold: int32, italic: int32): int32 {
	if (!validFace(face)) { return FACE_NO_BASE; }
	const synthetic = copyFace(faceAt(face));
	if (bold != 0) {
		const vertical = getFontVMetrics(synthetic.info);
		synthetic.emboldenUnits = ((vertical.ascent - vertical.descent + vertical.lineGap) as float32) / 32.0;
	}
	if (italic != 0) { synthetic.skew = ITALIC_SKEW; }
	state.faces.push(synthetic);
	return (state.faces.length as int32) - 1;
}

export function void2dGlyphFaceIsPlatform(face: int32): int32 {
	return validFace(face) && state.faces[face].platform != null ? 1 : 0;
}

export function void2dGlyphFaceCount(): int32 {
	return state.faces.length as int32;
}

export function void2dGlyphColourOnly(face: int32): int32 {
	return validFace(face) && state.faces[face].colourOnly ? 1 : 0;
}

when (macos || ios) {
	export function void2dGlyphFacePlatform(base: int32): int32 {
		if (!validFace(base)) { return FACE_NO_BASE; }
		const f = faceAt(base);
		if (f.sprite || f.colourOnly || f.platform != null || isSynthetic(f)) { return FACE_NO_BASE; }
		const table = platformInfo(f.bytes.data, f.info.fontstart);
		if (table == null) { return FACE_NOT_A_FONT; }
		const name = postScriptName(f.bytes.data, f.info.fontstart);
		if (name == "") { return FACE_NOT_A_FONT; }
		const platform = platformOpen(null, f.bytes.data, name, table.glyphCount, table.unitsPerEm);
		if (platform == null) { return FACE_NOT_A_FONT; }
		const face = copyFace(f);
		face.info = table.info;
		face.platform = platform;
		face.glyphCount = table.glyphCount;
		face.measured = false;
		state.faces.push(face);
		return (state.faces.length as int32) - 1;
	}
}

export function glyphFaceBytes(face: int32): FaceBytes | null {
	if (!validFace(face) || state.faces[face].sprite) { return null; }
	return state.faces[face].bytes;
}

export function void2dGlyphIndex(face: int32, codepoint: int32): int32 {
	if (!validFace(face)) { return 0; }
	when (voidSprites) {
		if (state.faces[face].sprite) { return spriteIndex(codepoint); }
	}
	return findGlyph(state.faces[face], codepoint);
}

export function void2dGlyphAdvance(face: int32, glyph: int32, sizePx: float32): float32 {
	if (!validFace(face)) { return 0.0; }
	const f = faceAt(face);
	when (voidSprites) {
		if (f.sprite) {
			if (glyph <= 0) { return 0.0; }
			return spriteAsciiUnits(f) * void2dGlyphScale(face, sizePx);
		}
	}
	if ((f.colourOnly || f.platform != null) && (glyph < 0 || glyph >= f.glyphCount)) {
		return 0.0;
	}
	const metrics = getGlyphHMetrics(f.info, glyph);
	return ((metrics.advance as float32) + f.emboldenUnits) * void2dGlyphScale(face, sizePx);
}

export function void2dGlyphEmbolden(face: int32, sizePx: float32): float32 {
	if (!validFace(face)) { return 0.0; }
	return state.faces[face].emboldenUnits * void2dGlyphScale(face, sizePx);
}

export function void2dGlyphKern(face: int32, left: int32, right: int32, sizePx: float32): float32 {
	if (!validFace(face)) { return 0.0; }
	const f = faceAt(face);
	if (f.sprite) { return 0.0; }
	const units = f.kernLookups.length > 0
		? gposKern(f.info, f.kernLookups, left, right)
		: getGlyphKernInfoAdvance(f.info, left, right);
	return (units as float32) * void2dGlyphScale(face, sizePx);
}

export function void2dGlyphFaceMetrics(face: int32, sizePx: float32, out: Span<float32>): void {
	needSlots("void2dGlyphFaceMetrics", out.length as int64, 3);
	out[0] = 0.0;
	out[1] = 0.0;
	out[2] = 0.0;
	if (!validFace(face)) { return; }
	const vertical = getFontVMetrics(state.faces[face].info);
	const scale = void2dGlyphScale(face, sizePx);
	out[0] = (vertical.ascent as float32) * scale;
	out[1] = ((-vertical.descent) as float32) * scale;
	out[2] = (vertical.lineGap as float32) * scale;
}

export function glyphShape(face: GlyphFace, glyph: int32): Vec<Vertex> {
	let vertices = getGlyphShape(face.info, glyph);
	applySynthetic(vertices, face.emboldenUnits, face.skew);
	return vertices;
}

export function putBox(out: Span<int32>, box: GlyphBox): void {
	out[0] = box.x0;
	out[1] = box.y0;
	out[2] = box.x1;
	out[3] = box.y1;
}

when (voidSprites) {
	function spriteAsciiUnits(face: GlyphFace): float32 {
		if (face.asciiUnits > 0.0) { return face.asciiUnits; }
		let widest: int32 = 0;
		for (let c: int32 = 32; c < 127; c++) {
			const glyph = findGlyphIndex(face.info, c);
			if (glyph == 0) { continue; }
			const metrics = getGlyphHMetrics(face.info, glyph);
			if (metrics.advance > widest) { widest = metrics.advance; }
		}
		face.asciiUnits = widest as float32;
		return face.asciiUnits;
	}

	function spriteCellCompute(face: int32, sizePx: float32, cell: int32[]): boolean {
		const f = faceAt(face);
		const scale = void2dGlyphScale(face, sizePx);
		const vertical = getFontVMetrics(f.info);
		const faceHeight: float64 = ((vertical.ascent - vertical.descent + vertical.lineGap) as float64) * (scale as float64);
		const faceWidth: float64 = (spriteAsciiUnits(f) as float64) * (scale as float64);
		if (!(faceHeight > 0.0) || !(faceWidth > 0.0)) { return false; }
		const cellHeight: float64 = Math.floor(faceHeight + 0.5);
		const halfGap: float64 = (vertical.lineGap as float64) * (scale as float64) / 2.0;
		const faceBaseline: float64 = halfGap + ((-vertical.descent) as float64) * (scale as float64);
		const cellBaseline: float64 = Math.floor(faceBaseline - (cellHeight - faceHeight) / 2.0 + 0.5);
		let decoration: Vec<float32> = [0.0, 0.0, 0.0, 0.0];
		void2dGlyphDecoration(face, sizePx, decoration);
		const thickness: float64 = Math.ceil(decoration[1] as float64);
		cell[0] = truncInt(Math.floor(faceWidth + 0.5));
		cell[1] = truncInt(cellHeight);
		cell[2] = truncInt(cellHeight) - truncInt(cellBaseline);
		cell[3] = thickness > 1.0 ? truncInt(thickness) : 1;
		if (cell[0] < 1) { cell[0] = 1; }
		if (cell[1] < 1) { cell[1] = 1; }
		return true;
	}

	function spriteCell(face: int32, sizePx: float32, cell: int32[]): boolean {
		if (face != state.cellFace || sizePx != state.cellSize) {
			state.cellOk = spriteCellCompute(face, sizePx, state.cellValue);
			state.cellFace = face;
			state.cellSize = sizePx;
		}
		for (let k: int32 = 0; k < 4; k++) { cell[k] = state.cellValue[k]; }
		return state.cellOk;
	}

	export function void2dGlyphFaceSprite(base: int32): int32 {
		if (!validFace(base)) { return FACE_NO_BASE; }
		if (state.faces[base].sprite || state.faces[base].colourOnly) { return FACE_NO_BASE; }
		const sprite = copyFace(faceAt(base));
		sprite.emboldenUnits = 0.0;
		sprite.skew = 0.0;
		sprite.colourHandle = -1;
		sprite.sprite = true;
		sprite.platform = null;
		sprite.asciiUnits = 0.0;
		state.faces.push(sprite);
		return (state.faces.length as int32) - 1;
	}

	export function void2dGlyphFaceIsSprite(face: int32): int32 {
		return validFace(face) && state.faces[face].sprite ? 1 : 0;
	}

	export function void2dGlyphSpriteCell(face: int32, sizePx: float32, out: Span<int32>): void {
		needSlots("void2dGlyphSpriteCell", out.length as int64, 4);
		out[0] = 0;
		out[1] = 0;
		out[2] = 0;
		out[3] = 0;
		if (void2dGlyphFaceIsSprite(face) == 0 || !(sizePx > 0.0)) { return; }
		let cell: int32[] = [0, 0, 0, 0];
		if (spriteCell(face, sizePx, cell)) {
			for (let k: int32 = 0; k < 4; k++) { out[k] = cell[k]; }
		}
	}

	export struct SpriteRows {
		box: GlyphBox;
		pixels: uint8[];
		origin: int32;
		stride: int32;
	}

	export function spriteInk(face: int32, glyph: int32, sizePx: float32): SpriteRows | null {
		let cell: int32[] = [0, 0, 0, 0];
		if (!spriteCell(face, sizePx, cell)) {
			console.error(
				`void2d: sprite face ${face} has no cell at ${fixed(sizePx, 2)} px, its glyph is not drawn`,
			);
			return null;
		}
		const ink = spriteCanvasInk(glyph, cell[0], cell[1], cell[3]);
		if (!ink.ok) {
			console.error(
				`void2d: sprite glyph ${glyph} at ${fixed(sizePx, 2)} px (cell ${cell[0]}x${cell[1]}, line ${cell[3]}) ` +
				`is refused with ${ink.error.toString()}, it is not drawn`,
			);
			return null;
		}
		return {
			box: {
				x0: ink.value.left,
				y0: ink.value.top - cell[2],
				x1: ink.value.right,
				y1: ink.value.bottom - cell[2],
			},
			pixels: ink.value.pixels,
			origin: ink.value.origin,
			stride: ink.value.stride,
		};
	}
}

export function void2dGlyphBox(
	face: int32, glyph: int32, sizePx: float32, shiftX: float32, out: Span<int32>,
): void {
	needSlots("void2dGlyphBox", out.length as int64, 4);
	out[0] = 0;
	out[1] = 0;
	out[2] = 0;
	out[3] = 0;
	if (!validFace(face)) { return; }
	const scale = void2dGlyphScale(face, sizePx);
	const f = faceAt(face);
	when (voidSprites) {
		if (f.sprite) {
			const ink = spriteInk(face, glyph, sizePx);
			if (ink != null) { putBox(out, ink.box); }
			return;
		}
	}
	when (macos || ios) {
		const platform = f.platform;
		if (platform != null) {
			putBox(out, platformBox(platform, glyph, sizePx, shiftX, f.skew, f.emboldenUnits * scale));
			return;
		}
	}
	if (isSynthetic(f)) {
		const vertices = glyphShape(f, glyph);
		putBox(out, shapeBox(vertices, scale, shiftX));
		return;
	}
	putBox(out, getGlyphBitmapBoxSubpixel(f.info, glyph, scale, scale, shiftX, 0.0));
}
