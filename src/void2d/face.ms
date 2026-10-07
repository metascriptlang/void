import {
	void2dGlyphFaceLoad,
	void2dGlyphFaceSynthetic,
	void2dGlyphIndex,
	void2dGlyphLookups,
	void2dGlyphAdvance,
	void2dGlyphKern,
	void2dGlyphEmbolden,
	void2dGlyphScale,
	void2dGlyphFaceMetrics,
	void2dGlyphDecoration,
	void2dGlyphFaceHeights,
	void2dGlyphPageTexel,
	void2dGlyphBox,
	void2dGlyphColourBuilt,
	void2dGlyphColourFace,
	void2dGlyphColourOnly,
	void2dGlyphColourBox,
	void2dGlyphColourRasterize,
	void2dGlyphColourLayerCount,
	void2dGlyphColourLayerGlyph,
	void2dGlyphColourLayerRgba,
} from "./glyph.h";
import "./colourEmoji/colourEmoji";

when (voidSprites) {
	import "./spriteSwitch";
	import "./spriteGlyph";
	import {
		void2dGlyphFaceSprite,
		void2dGlyphFaceIsSprite,
		void2dGlyphSpriteCell,
	} from "./glyph.h";
}

import {
	void2dSfntPeek,
	void2dSfntCovers,
	void2dSfntSequence,
	void2dSfntFlags,
	void2dSfntSummariesRead,
} from "./sfnt.h";
import { GlyphPageHandle } from "./glyphAtlas";

export struct FaceMetrics {
	ascent: float32;
	descent: float32;
	lineGap: float32;
}

export struct DecorationMetrics {
	underlineTop: float32;
	underlineThickness: float32;
	strikethroughTop: float32;
	strikethroughThickness: float32;
}

export struct FaceHeights {
	icWidth: float32;
	exHeight: float32;
	capHeight: float32;
	icWidthEstimate: float32;
	exHeightEstimate: float32;
	capHeightEstimate: float32;
	lineHeight: float32;
}

export enum FaceError {
	Unreadable,
	NotAFont,
	OutOfMemory,
	NoBaseFace,
	BadColourTable,
}

function faceResult(code: int32): Result<int32, FaceError> {
	if (code >= 0) { return Result.ok(code); }
	if (code < -5) { unreachable; }
	return match (code) {
		-1 => Result.err(FaceError.Unreadable),
		-2 => Result.err(FaceError.NotAFont),
		-3 => Result.err(FaceError.OutOfMemory),
		-4 => Result.err(FaceError.NoBaseFace),
		_ => Result.err(FaceError.BadColourTable),
	};
}

export enum SfntError {
	Unreadable,
	NotAnSfnt,
	OutOfMemory,
}

export enum SfntSequence {
	None,
	Default,
	Specific,
}

export struct FaceSummary {
	id: int32;
	drawable: boolean;
	colourBitmap: boolean;
	colourLayers: boolean;
}

export function peekFace(path: string): Result<FaceSummary, SfntError> {
	const code: int32 = void2dSfntPeek(path);
	if (code < 0) {
		if (code < -3) { unreachable; }
		return match (code) {
			-1 => Result.err(SfntError.Unreadable),
			-2 => Result.err(SfntError.NotAnSfnt),
			_ => Result.err(SfntError.OutOfMemory),
		};
	}
	const flags: int32 = void2dSfntFlags(code);
	return Result.ok({
		id: code,
		drawable: (flags & 1) != 0,
		colourBitmap: (flags & 2) != 0,
		colourLayers: (flags & 4) != 0,
	});
}

export function summaryCovers(summary: FaceSummary, codepoint: int32): boolean {
	return void2dSfntCovers(summary.id, codepoint) != 0;
}

export function summarySequence(
	summary: FaceSummary, codepoint: int32, selector: int32,
): SfntSequence {
	return void2dSfntSequence(summary.id, codepoint, selector) as SfntSequence;
}

export function faceSummariesRead(): int32 {
	return void2dSfntSummariesRead();
}

export function loadFace(path: string): Result<int32, FaceError> {
	return faceResult(void2dGlyphFaceLoad(path));
}

export function syntheticFace(
	face: int32,
	bold: boolean,
	italic: boolean,
): Result<int32, FaceError> {
	return faceResult(void2dGlyphFaceSynthetic(face, bold ? 1 : 0, italic ? 1 : 0));
}

export function isSpriteFace(face: int32): boolean {
	when (voidSprites) {
		return void2dGlyphFaceIsSprite(face) != 0;
	} else {
		return false;
	}
}

when (voidSprites) {
	export function spriteFace(base: int32): Result<int32, FaceError> {
		return faceResult(void2dGlyphFaceSprite(base));
	}

	export struct SpriteCell {
		width: int32;
		height: int32;
		topToBaseline: int32;
		lineThickness: int32;
	}

	export function spriteCell(face: int32, sizePx: float32): SpriteCell {
		const c: Ptr<int32> = void2dGlyphSpriteCell(face, sizePx);
		return { width: c[0], height: c[1], topToBaseline: c[2], lineThickness: c[3] };
	}
}

export function glyphLookups(): uint32 {
	return void2dGlyphLookups();
}

export function glyphIndex(face: int32, codepoint: int32): int32 {
	return void2dGlyphIndex(face, codepoint);
}

export function glyphAdvance(face: int32, glyph: int32, sizePx: float32): float32 {
	return void2dGlyphAdvance(face, glyph, sizePx);
}

export function glyphScale(face: int32, sizePx: float32): float32 {
	return void2dGlyphScale(face, sizePx);
}

export function glyphEmbolden(face: int32, sizePx: float32): float32 {
	return void2dGlyphEmbolden(face, sizePx);
}

export function glyphKern(face: int32, left: int32, right: int32, sizePx: float32): float32 {
	return void2dGlyphKern(face, left, right, sizePx);
}

export function glyphInkBox(
	face: int32,
	glyph: int32,
	sizePx: float32,
): [float32, float32, float32, float32] {
	const box: Ptr<int32> = void2dGlyphBox(face, glyph, sizePx, 0.0);
	return [box[0] as float32, box[1] as float32, box[2] as float32, box[3] as float32];
}

export function faceMetrics(face: int32, sizePx: float32): FaceMetrics {
	const m: Ptr<float32> = void2dGlyphFaceMetrics(face, sizePx);
	return { ascent: m[0], descent: m[1], lineGap: m[2] };
}

export function decorationMetrics(face: int32, sizePx: float32): DecorationMetrics {
	const m: Ptr<float32> = void2dGlyphDecoration(face, sizePx);
	return {
		underlineTop: m[0],
		underlineThickness: m[1],
		strikethroughTop: m[2],
		strikethroughThickness: m[3],
	};
}

export function faceHeights(face: int32): FaceHeights {
	const m: Ptr<float32> = void2dGlyphFaceHeights(face);
	return {
		icWidth: m[0],
		exHeight: m[1],
		capHeight: m[2],
		icWidthEstimate: m[3],
		exHeightEstimate: m[4],
		capHeightEstimate: m[5],
		lineHeight: m[6],
	};
}

export enum ColourGlyph {
	Absent,
	Present,
	Refused,
}

export struct ColourTileBox {
	left: int32;
	top: int32;
	right: int32;
	bottom: int32;
	glyph: ColourGlyph;
	ppem: int32;
}

export function colourBuilt(): boolean {
	return void2dGlyphColourBuilt() != 0;
}

export function hasColourTables(face: int32): boolean {
	return void2dGlyphColourFace(face) != 0;
}

export function isColourOnly(face: int32): boolean {
	return void2dGlyphColourOnly(face) != 0;
}

export function colourTileBox(face: int32, glyph: int32, sizePx: float32): ColourTileBox {
	const b: Ptr<int32> = void2dGlyphColourBox(face, glyph, sizePx);
	const status: ColourGlyph = b[4] == 1
		? ColourGlyph.Present
		: b[4] == 0 ? ColourGlyph.Absent : ColourGlyph.Refused;
	return {
		left: b[0],
		top: b[1],
		right: b[2],
		bottom: b[3],
		glyph: status,
		ppem: b[5],
	};
}

export function colourRasterize(
	face: int32,
	glyph: int32,
	sizePx: float32,
	page: GlyphPageHandle,
	x: int32,
	y: int32,
	width: int32,
	height: int32,
): int32 {
	return void2dGlyphColourRasterize(face, glyph, sizePx, page as int32, x, y, width, height);
}

export function colourLayerCount(face: int32, glyph: int32): int32 {
	return void2dGlyphColourLayerCount(face, glyph);
}

export function colourLayerGlyph(face: int32, glyph: int32, index: int32): int32 {
	return void2dGlyphColourLayerGlyph(face, glyph, index);
}

export function colourLayerRgba(face: int32, glyph: int32, index: int32): uint32 {
	return void2dGlyphColourLayerRgba(face, glyph, index);
}

export function pageTexel(page: GlyphPageHandle, x: int32, y: int32): int32 {
	return void2dGlyphPageTexel(page as int32, x, y);
}
