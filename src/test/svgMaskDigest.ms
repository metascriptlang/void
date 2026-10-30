import { corpusDoc, corpusEdgeCount, corpusFixtureCount } from "./svgCorpus";
import { Digest, mix, mixInt, mixText } from "./colourFaceDigest";
import { maskFree, maskImageOf, maskParse, maskRasterize, maskReason } from "../void2d/svg/mask";

export const RASTER_SIDES: int32[] = [16, 16, 24, 24, 33, 17, 64, 48, 9, 60];
export const GENERATED_DOCS: int32 = 3000;
const RASTER_THREW: int32 = 255;

export function corpusTotal(): int32 {
	return corpusFixtureCount() + corpusEdgeCount() + GENERATED_DOCS;
}

export function docIsSkewed(text: string): boolean {
	return text.indexOf("skew") >= 0;
}

export function mixHead(d: Digest, code: int32, reason: string, width: float32, height: float32): void {
	mixInt(d, code > 0 ? 1 : code);
	mixText(d, reason);
	mixInt(d, (width * 1024.0) as int32);
	mixInt(d, (height * 1024.0) as int32);
}

export function mixAlpha(d: Digest, alpha: Vec<uint8>): void {
	mixInt(d, alpha.length as int32);
	for (let i: int32 = 0; i < alpha.length; i++) { mix(d, alpha[i] as int32); }
}

export function mixThrew(d: Digest): void {
	mix(d, RASTER_THREW);
}

export function digestDoc(d: Digest, text: string): void {
	const code = maskParse(text);
	if (code <= 0) {
		mixHead(d, code, maskReason(), 0.0, 0.0);
		return;
	}
	const image = maskImageOf(code);
	if (image == null) { throw new Error("svg digest: a live handle has no image"); }
	mixHead(d, code, maskReason(), image.width, image.height);
	for (let s: int32 = 0; s < RASTER_SIDES.length / 2; s++) {
		try {
			mixAlpha(d, maskRasterize(image, RASTER_SIDES[s * 2], RASTER_SIDES[s * 2 + 1]));
		} catch (e) {
			mixThrew(d);
		}
	}
	maskFree(code);
}

export function digestRange(from: int32, to: int32, skewed: boolean): uint64 {
	const d = new Digest();
	for (let i: int32 = from; i < to; i++) {
		const text = corpusDoc(i);
		if (docIsSkewed(text) == skewed) { digestDoc(d, text); }
	}
	return d.h;
}
