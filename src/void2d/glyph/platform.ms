import {
	void2dPlatformFaceBox,
	void2dPlatformFaceFill,
	void2dPlatformFaceOpen,
	void2dPlatformFaceUnitsBox,
} from "../platformFace.h";
import { FontInfo, GlyphBox, asInt32, findTable, u16At, u32At, u8At } from "../trueType/fontInfo";

@compile("../platformFaceApple.m", "-fobjc-arc");
@passL("-framework CoreText");
@passL("-framework CoreGraphics");
@passL("-framework CoreFoundation");

const PLATFORM_ID_UNICODE: int32 = 0;
const PLATFORM_ID_MICROSOFT: int32 = 3;
const MS_EID_UNICODE_BMP: int32 = 1;
const MS_EID_UNICODE_FULL: int32 = 10;
const NAME_CAPACITY: int32 = 128;

export class PlatformTable {
	info: FontInfo;
	glyphCount: int32;
	unitsPerEm: int32;

	constructor(info: FontInfo, glyphCount: int32, unitsPerEm: int32) {
		this.info = info;
		this.glyphCount = glyphCount;
		this.unitsPerEm = unitsPerEm;
	}
}

export function platformInfo(bytes: uint8[], offset: int32): PlatformTable | null {
	const data = bytes as Span<uint8>;
	const cmap = findTable(data, offset, "cmap");
	const maxp = findTable(data, offset, "maxp");
	const head = findTable(data, offset, "head");
	const hhea = findTable(data, offset, "hhea");
	const hmtx = findTable(data, offset, "hmtx");
	if (cmap == 0 || maxp == 0 || head == 0 || hhea == 0 || hmtx == 0) { return null; }
	let indexMap: int32 = 0;
	const encodings = data.u16At((cmap as int64) + 2);
	for (let i: int32 = 0; i < encodings; i++) {
		const record: int64 = (cmap as int64) + 4 + 8 * (i as int64);
		const platformId = data.u16At(record);
		const encodingId = data.u16At(record + 2);
		if (platformId == PLATFORM_ID_UNICODE || (platformId == PLATFORM_ID_MICROSOFT &&
			(encodingId == MS_EID_UNICODE_BMP || encodingId == MS_EID_UNICODE_FULL))) {
			indexMap = asInt32((cmap as int64) + data.u32At(record + 4));
		}
	}
	if (indexMap == 0) { return null; }
	const info: FontInfo = {
		data: data,
		fontstart: offset,
		numGlyphs: 0,
		loca: 0,
		head: head,
		glyf: 0,
		hhea: hhea,
		hmtx: hmtx,
		kern: findTable(data, offset, "kern"),
		gpos: findTable(data, offset, "GPOS"),
		svg: 0,
		indexMap: indexMap,
		indexToLocFormat: data.u16At((head as int64) + 50),
		cff: { data: data, base: 0, size: 0, cursor: 0 },
		charstrings: { data: data, base: 0, size: 0, cursor: 0 },
		gsubrs: { data: data, base: 0, size: 0, cursor: 0 },
		subrs: { data: data, base: 0, size: 0, cursor: 0 },
		fontdicts: { data: data, base: 0, size: 0, cursor: 0 },
		fdselect: { data: data, base: 0, size: 0, cursor: 0 },
	};
	return new PlatformTable(info, data.u16At((maxp as int64) + 4), data.u16At((head as int64) + 18));
}

export function postScriptName(bytes: uint8[], offset: int32): string {
	const data = bytes as Span<uint8>;
	const name = findTable(data, offset, "name");
	if (name == 0) { return ""; }
	const count = data.u16At((name as int64) + 2);
	const strings: int64 = (name as int64) + data.u16At((name as int64) + 4);
	for (let i: int32 = 0; i < count; i++) {
		const record: int64 = (name as int64) + 6 + 12 * (i as int64);
		const platformId = data.u16At(record);
		const nameId = data.u16At(record + 6);
		const length = data.u16At(record + 8);
		const text: int64 = strings + data.u16At(record + 10);
		if (nameId != 6 || (platformId != 1 && platformId != 3)) { continue; }
		const step: int32 = platformId == 3 ? 2 : 1;
		let result: string = "";
		let n: int32 = 0;
		for (let k: int32 = step - 1; k < length && n < NAME_CAPACITY - 1; k += step) {
			result += String.fromCharCode(data.u8At(text + (k as int64)));
			n++;
		}
		if (n > 0) { return result; }
	}
	return "";
}

export function platformOpen(
	path: string | null, bytes: uint8[], name: string, glyphCount: int32, unitsPerEm: int32,
): Ptr<void> | null {
	const opened = void2dPlatformFaceOpen(path ?? "", bytes[0], bytes.length, name, glyphCount, unitsPerEm);
	return opened;
}

export function platformUnitsBox(platform: Ptr<void>, glyph: int32): float32[] {
	let box: float32[] = [0.0, 0.0, 0.0, 0.0];
	void2dPlatformFaceUnitsBox(platform, glyph, (box as Span<float32>) as Ptr<float32>);
	return box;
}

export function platformBox(
	platform: Ptr<void>, glyph: int32, sizePx: float32, shiftX: float32, skew: float32, emboldenPx: float32,
): GlyphBox {
	let box: int32[] = [0, 0, 0, 0];
	void2dPlatformFaceBox(platform, glyph, sizePx, shiftX, skew, emboldenPx, (box as Span<int32>) as Ptr<int32>);
	return { x0: box[0], y0: box[1], x1: box[2], y1: box[3] };
}

export function platformFill(
	platform: Ptr<void>, glyph: int32, sizePx: float32, shiftX: float32, skew: float32, emboldenPx: float32,
	at: Span<uint8>, w: int32, h: int32, stride: int32,
): boolean {
	return void2dPlatformFaceFill(
		platform, glyph, sizePx, shiftX, skew, emboldenPx, (at as Span<uint8>) as Ptr<uint8>, w, h, stride,
	) != 0;
}
