import {
	void2dGlyphFaceLoad,
	void2dGlyphFaceSynthetic,
	void2dGlyphIndex,
	void2dGlyphLookups,
	void2dGlyphAdvance,
	void2dGlyphKern,
	void2dGlyphEmbolden,
	void2dGlyphScale,
	void2dGlyphPageTexel,
	void2dGlyphColourBuilt,
	void2dGlyphColourFace,
	void2dGlyphColourOnly,
	void2dGlyphColourRasterize,
	void2dGlyphColourLayerCount,
	void2dGlyphColourLayerGlyph,
	void2dGlyphColourLayerRgba,
} from "./glyph.h";
import { glyphBox } from "./glyphBoxes";

extern function void2dGlyphFaceMetrics(face: int32, sizePx: float32, out: Span<float32>): void;
extern function void2dGlyphDecoration(face: int32, sizePx: float32, out: Span<float32>): void;
extern function void2dGlyphFaceHeights(face: int32, out: Span<float32>): void;
extern function void2dGlyphColourBox(
	face: int32, glyph: int32, sizePx: float32, out: Span<int32>,
): void;

let metricSlots: Vec<float32> = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
let boxSlots: Vec<int32> = [0, 0, 0, 0, 0, 0];
import "./colourEmoji/colourEmoji";

when (voidSprites) {
	import "./spriteSwitch";
	import "./spriteGlyph";
	import {
		void2dGlyphFaceSprite,
		void2dGlyphFaceIsSprite,
	} from "./glyph.h";

	extern function void2dGlyphSpriteCell(face: int32, sizePx: float32, out: Span<int32>): void;
}

when (macos || ios) {
	@compile("./platformFaceApple.m", "-fobjc-arc");
	@passL("-framework CoreText");
	@passL("-framework CoreGraphics");
	@passL("-framework CoreFoundation");
	import { void2dGlyphFacePlatform, void2dGlyphFaceIsPlatform } from "./glyph.h";
}

import {
	void2dSfntPeek,
	void2dSfntCovers,
	void2dSfntSequence,
	void2dSfntFlags,
	void2dSfntSummariesRead,
} from "./sfnt.h";
import { void2dFontBytesAdd } from "./fontBytes.h";
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
	NoRasterizerOnJs,
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
	osOutlines: boolean;
}

export enum FaceBytesError {
	Empty,
	NameHeld,
	OutOfMemory,
}

// Holds a face's bytes under `name`, which peekFace and loadFace then read in place of a file.
// The same bytes again are accepted; other bytes under a held name are refused.
export function holdFaceBytes(name: string, bytes: uint8[]): Result<void, FaceBytesError> {
	if (bytes.length == 0) { return Result.err(FaceBytesError.Empty); }
	const code: int32 = void2dFontBytesAdd(name, bytes[0], bytes.length as int32);
	if (code != 0 && code != -3 && code != -4) { unreachable; }
	return match (code) {
		0 => Result.ok(null),
		-4 => Result.err(FaceBytesError.NameHeld),
		_ => Result.err(FaceBytesError.OutOfMemory),
	};
}

export function peekFace(path: string, index: int32 = 0): Result<FaceSummary, SfntError> {
	const code: int32 = void2dSfntPeek(path, index);
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
		osOutlines: (flags & 8) != 0,
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

export function loadFace(path: string, index: int32 = 0): Result<int32, FaceError> {
	when (js) {
		return Result.err(FaceError.NoRasterizerOnJs);
	} else {
		return faceResult(void2dGlyphFaceLoad(path, index));
	}
}

export function syntheticFace(
	face: int32,
	bold: boolean,
	italic: boolean,
): Result<int32, FaceError> {
	return faceResult(void2dGlyphFaceSynthetic(face, bold ? 1 : 0, italic ? 1 : 0));
}

export function platformFacesBuilt(): boolean {
	when (macos || ios) {
		return true;
	} else {
		return false;
	}
}

export function isPlatformFace(face: int32): boolean {
	when (macos || ios) {
		return void2dGlyphFaceIsPlatform(face) != 0;
	} else {
		return false;
	}
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
		void2dGlyphSpriteCell(face, sizePx, boxSlots);
		return {
			width: boxSlots[0],
			height: boxSlots[1],
			topToBaseline: boxSlots[2],
			lineThickness: boxSlots[3],
		};
	}
}

when (macos || ios) {
	export function platformFace(base: int32): Result<int32, FaceError> {
		return faceResult(void2dGlyphFacePlatform(base));
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
	const box = glyphBox(face, glyph, sizePx, 0.0);
	return [box[0] as float32, box[1] as float32, box[2] as float32, box[3] as float32];
}

export function faceMetrics(face: int32, sizePx: float32): FaceMetrics {
	void2dGlyphFaceMetrics(face, sizePx, metricSlots);
	return { ascent: metricSlots[0], descent: metricSlots[1], lineGap: metricSlots[2] };
}

export function decorationMetrics(face: int32, sizePx: float32): DecorationMetrics {
	void2dGlyphDecoration(face, sizePx, metricSlots);
	return {
		underlineTop: metricSlots[0],
		underlineThickness: metricSlots[1],
		strikethroughTop: metricSlots[2],
		strikethroughThickness: metricSlots[3],
	};
}

export function faceHeights(face: int32): FaceHeights {
	void2dGlyphFaceHeights(face, metricSlots);
	return {
		icWidth: metricSlots[0],
		exHeight: metricSlots[1],
		capHeight: metricSlots[2],
		icWidthEstimate: metricSlots[3],
		exHeightEstimate: metricSlots[4],
		capHeightEstimate: metricSlots[5],
		lineHeight: metricSlots[6],
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
	void2dGlyphColourBox(face, glyph, sizePx, boxSlots);
	const status: ColourGlyph = boxSlots[4] == 1
		? ColourGlyph.Present
		: boxSlots[4] == 0 ? ColourGlyph.Absent : ColourGlyph.Refused;
	return {
		left: boxSlots[0],
		top: boxSlots[1],
		right: boxSlots[2],
		bottom: boxSlots[3],
		glyph: status,
		ppem: boxSlots[5],
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
