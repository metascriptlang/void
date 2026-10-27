// The glyph rasterizer's boxes, read into an array each call so they read alike on C and JS.

import { void2dGlyphBox } from "./glyph";

export function glyphBox(face: int32, glyph: int32, sizePx: float32, shiftX: float32): Vec<int32> {
	let box: Vec<int32> = [0, 0, 0, 0];
	void2dGlyphBox(face, glyph, sizePx, shiftX, box);
	return box;
}

when (voidSdfText) {
	import { void2dGlyphSdfBox } from "./glyph";

	export function glyphSdfBox(face: int32, glyph: int32): Vec<int32> {
		let box: Vec<int32> = [0, 0, 0, 0, 0];
		void2dGlyphSdfBox(face, glyph, box);
		return box;
	}
}

when (voidTextOutline) {
	import { void2dGlyphOutlineBox } from "./glyph";

	export function glyphOutlineBox(
		face: int32, glyph: int32, sizePx: float32, shiftX: float32, widthPx: float32,
	): Vec<int32> {
		let box: Vec<int32> = [0, 0, 0, 0, 0];
		void2dGlyphOutlineBox(face, glyph, sizePx, shiftX, widthPx, box);
		return box;
	}
}

when (voidSdfText && voidTextOutline) {
	import { void2dGlyphSdfOutlineBox } from "./glyph";

	export function glyphSdfOutlineBox(face: int32, glyph: int32, biasTexels: float32): Vec<int32> {
		let box: Vec<int32> = [0, 0, 0, 0, 0];
		void2dGlyphSdfOutlineBox(face, glyph, biasTexels, box);
		return box;
	}
}
