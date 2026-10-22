// The glyph rasterizer's boxes, read into an array each call so they read alike on C and JS.

@include("glyph.h");

extern function void2dGlyphBox(
	face: int32, glyph: int32, sizePx: float32, shiftX: float32, out: Span<int32>,
): void;

export function glyphBox(face: int32, glyph: int32, sizePx: float32, shiftX: float32): Vec<int32> {
	let box: Vec<int32> = [0, 0, 0, 0];
	void2dGlyphBox(face, glyph, sizePx, shiftX, box);
	return box;
}

when (voidSdfText) {
	extern function void2dGlyphSdfBox(face: int32, glyph: int32, out: Span<int32>): void;

	export function glyphSdfBox(face: int32, glyph: int32): Vec<int32> {
		let box: Vec<int32> = [0, 0, 0, 0, 0];
		void2dGlyphSdfBox(face, glyph, box);
		return box;
	}
}

when (voidTextOutline) {
	extern function void2dGlyphOutlineBox(
		face: int32, glyph: int32, sizePx: float32, shiftX: float32, widthPx: float32,
		out: Span<int32>,
	): void;

	export function glyphOutlineBox(
		face: int32, glyph: int32, sizePx: float32, shiftX: float32, widthPx: float32,
	): Vec<int32> {
		let box: Vec<int32> = [0, 0, 0, 0, 0];
		void2dGlyphOutlineBox(face, glyph, sizePx, shiftX, widthPx, box);
		return box;
	}
}

when (voidSdfText && voidTextOutline) {
	extern function void2dGlyphSdfOutlineBox(
		face: int32, glyph: int32, biasTexels: float32, out: Span<int32>,
	): void;

	export function glyphSdfOutlineBox(face: int32, glyph: int32, biasTexels: float32): Vec<int32> {
		let box: Vec<int32> = [0, 0, 0, 0, 0];
		void2dGlyphSdfOutlineBox(face, glyph, biasTexels, box);
		return box;
	}
}
