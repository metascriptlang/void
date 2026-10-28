import { FontInfo } from "../trueType";

export const FACE_UNREADABLE: int32 = -1;
export const FACE_NOT_A_FONT: int32 = -2;
export const FACE_NO_MEMORY: int32 = -3;
export const FACE_NO_BASE: int32 = -4;
export const FACE_BAD_COLOUR: int32 = -5;

export const MAX_GLYPH_PAGES: int32 = 64;

export const PAGE_COVERAGE: int32 = 0;
export const PAGE_SDF: int32 = 1;
export const PAGE_RGBA: int32 = 2;
export const PAGE_MASK: int32 = 3;

export const COVERAGE_RASTER_BAD_HANDLE: int32 = 1;
export const COVERAGE_RASTER_WRONG_PAGE_KIND: int32 = 2;
export const COVERAGE_RASTER_OUTSIDE_PAGE: int32 = 3;
export const COVERAGE_RASTER_BOX_MISMATCH: int32 = 4;

export const BLIT_OK: int32 = 0;
export const BLIT_BAD_HANDLE: int32 = 1;
export const BLIT_WRONG_PAGE_KIND: int32 = 2;
export const BLIT_OUTSIDE_PAGE: int32 = 3;

export const COLOUR_RASTER_OK: int32 = 0;
export const COLOUR_RASTER_BAD_HANDLE: int32 = 1;
export const COLOUR_RASTER_WRONG_PAGE_KIND: int32 = 2;
export const COLOUR_RASTER_OUTSIDE_PAGE: int32 = 3;
export const COLOUR_RASTER_REFUSED: int32 = 4;
export const COLOUR_RASTER_NO_MEMORY: int32 = 5;

export const SDF_OK: int32 = 0;
export const SDF_BAD_HANDLE: int32 = 1;
export const SDF_WRONG_PAGE_KIND: int32 = 2;
export const SDF_OUTSIDE_PAGE: int32 = 3;
export const SDF_BOX_MISMATCH: int32 = 4;
export const SDF_NO_MEMORY: int32 = 5;

export const ITALIC_SKEW: float32 = 0.21255656;

export class FaceBytes {
	readonly data: uint8[];

	constructor(data: uint8[]) {
		this.data = data;
	}
}

export struct FaceHeights {
	cap: float32;
	ex: float32;
	ic: float32;
	capEstimate: float32;
	exEstimate: float32;
	icEstimate: float32;
	lineHeight: float32;
}

export class GlyphFace {
	bytes: FaceBytes;
	info: FontInfo;
	kernLookups: int32[] = [];
	kernUnits: Map<uint64, int32> = new Map<uint64, int32>();
	emboldenUnits: float32 = 0.0;
	skew: float32 = 0.0;
	measured: boolean = false;
	colourHandle: int32 = -1;
	colourOnly: boolean = false;
	sprite: boolean = false;
	platform: Ptr<void> | null = null;
	browser: boolean = false;
	asciiUnits: float32 = 0.0;
	glyphCount: int32 = 0;
	heights: FaceHeights = { cap: 0, ex: 0, ic: 0, capEstimate: 0, exEstimate: 0, icEstimate: 0, lineHeight: 0 };
	underlineTop: float32 = 0.0;
	underlineThickness: float32 = 0.0;
	strikeTop: float32 = 0.0;
	strikeThickness: float32 = 0.0;

	constructor(bytes: FaceBytes, info: FontInfo) {
		this.bytes = bytes;
		this.info = info;
	}
}

export class GlyphPage {
	texels: uint8[] = [];
	size: int32 = 0;
	kind: int32 = 0;
	dirty: boolean = false;
	dirtyBox: int32[] = [0, 0, 0, 0];
	takenBox: int32[] = [0, 0, 0, 0];
	uploaded: boolean = false;
	live: boolean = false;
	generation: uint32 = 0;
}

export class GlyphState {
	faces: GlyphFace[] = [];
	pages: GlyphPage[] = [];
	pageGenerations: uint32 = 0;
	glyphLookups: uint32 = 0;
	sdfGenerations: uint32 = 0;
	outlineGenerations: uint32 = 0;
	cellFace: int32 = -1;
	cellSize: float32 = 0.0;
	cellValue: int32[] = [0, 0, 0, 0];
	cellOk: boolean = false;
}

export const state: GlyphState = new GlyphState();



export function blankInfo(data: Readonly<Span<uint8>>): FontInfo {
	return {
		data: data, fontstart: 0, numGlyphs: 0, loca: 0, head: 0, glyf: 0, hhea: 0, hmtx: 0,
		kern: 0, gpos: 0, svg: 0, indexMap: 0, indexToLocFormat: 0,
		cff: { data: data, base: 0, size: 0, cursor: 0 },
		charstrings: { data: data, base: 0, size: 0, cursor: 0 },
		gsubrs: { data: data, base: 0, size: 0, cursor: 0 },
		subrs: { data: data, base: 0, size: 0, cursor: 0 },
		fontdicts: { data: data, base: 0, size: 0, cursor: 0 },
		fdselect: { data: data, base: 0, size: 0, cursor: 0 },
	};
}

export function faceAt(face: int32): GlyphFace {
	return state.faces[face];
}

export function fixed(value: float32, digits: int32): string {
	const scale: float64 = digits == 1 ? 10.0 : 100.0;
	const magnitude: float64 = Math.abs(value as float64);
	const scaled: int64 = Math.floor(magnitude * scale + 0.5) as int64;
	const whole: int64 = scaled / (scale as int64);
	const part: int64 = scaled - whole * (scale as int64);
	const partText: string = digits == 1 || part >= 10 ? `${part}` : `0${part}`;
	return `${value < 0.0 ? "-" : ""}${whole}.${partText}`;
}
