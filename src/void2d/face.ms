import {
	void2dGlyphFaceLoad,
	void2dGlyphFaceSynthetic,
	void2dGlyphIndex,
	void2dGlyphAdvance,
	void2dGlyphKern,
	void2dGlyphFaceMetrics,
	void2dGlyphDecoration,
	void2dGlyphFaceHeights,
	void2dGlyphPageTexel,
	void2dGlyphBox,
} from "./glyph.h";

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

export function loadFace(path: string): int32 {
	return void2dGlyphFaceLoad(path);
}

export function syntheticFace(face: int32, bold: boolean, italic: boolean): int32 {
	return void2dGlyphFaceSynthetic(face, bold ? 1 : 0, italic ? 1 : 0);
}

export function glyphIndex(face: int32, codepoint: int32): int32 {
	return void2dGlyphIndex(face, codepoint);
}

export function glyphAdvance(face: int32, glyph: int32, sizePx: float32): float32 {
	return void2dGlyphAdvance(face, glyph, sizePx);
}

export function glyphKern(face: int32, left: int32, right: int32, sizePx: float32): float32 {
	return void2dGlyphKern(face, left, right, sizePx);
}

export function glyphInkBox(face: int32, glyph: int32, sizePx: float32): [float32, float32, float32, float32] {
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

export function pageTexel(page: int32, x: int32, y: int32): int32 {
	return void2dGlyphPageTexel(page, x, y);
}
