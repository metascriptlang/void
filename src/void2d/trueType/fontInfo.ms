export const VERTEX_MOVE: uint8 = 1;
export const VERTEX_LINE: uint8 = 2;
export const VERTEX_CURVE: uint8 = 3;
export const VERTEX_CUBIC: uint8 = 4;

const LOW_32: int64 = 0xFFFFFFFF;
const SIGN_32: int64 = 0x80000000;

export struct Vertex {
	x: int16;
	y: int16;
	cx: int16;
	cy: int16;
	cx1: int16;
	cy1: int16;
	kind: uint8;
}

export struct GlyphBox {
	x0: int32;
	y0: int32;
	x1: int32;
	y1: int32;
}

export struct Buf {
	data: Readonly<Span<uint8>>;
	base: int64;
	size: int32;
	cursor: int32;
}

export struct FontInfo {
	data: Readonly<Span<uint8>>;
	fontstart: int32;
	numGlyphs: int32;
	loca: int32;
	head: int32;
	glyf: int32;
	hhea: int32;
	hmtx: int32;
	kern: int32;
	gpos: int32;
	svg: int32;
	indexMap: int32;
	indexToLocFormat: int32;
	cff: Buf;
	charstrings: Buf;
	gsubrs: Buf;
	subrs: Buf;
	fontdicts: Buf;
	fdselect: Buf;
}

@inline export function asInt32(value: int64): int32 {
	return (((value & LOW_32) ^ SIGN_32) - SIGN_32) as int32;
}

export function wrapInt16(value: int32): int16 {
	return ((((value & 0xFFFF) ^ 0x8000) - 0x8000) as int16);
}

// The x86 float-to-int conversion the C casts compile to: an unrepresentable value is INT_MIN.
export function truncInt(value: float64): int32 {
	if (!(value > -2147483649.0 && value < 2147483648.0)) { return -2147483647 - 1; }
	return value as int32;
}

@inline export function u8At(this data: Readonly<Span<uint8>>, at: int64): int32 {
	return at >= 0 && at < (data.length as int64) ? (data[at] as int32) : 0;
}

@inline export function u16At(this data: Readonly<Span<uint8>>, at: int64): int32 {
	return data.u8At(at) * 256 + data.u8At(at + 1);
}

@inline export function i16At(this data: Readonly<Span<uint8>>, at: int64): int32 {
	const value = data.u16At(at);
	return value >= 0x8000 ? value - 0x10000 : value;
}

@inline export function u32At(this data: Readonly<Span<uint8>>, at: int64): int64 {
	return ((data.u8At(at) as int64) << 24) + ((data.u8At(at + 1) as int64) << 16) +
		((data.u8At(at + 2) as int64) << 8) + (data.u8At(at + 3) as int64);
}

@inline export function i32At(this data: Readonly<Span<uint8>>, at: int64): int32 {
	return asInt32(data.u32At(at));
}

export function newBuf(data: Readonly<Span<uint8>>): Buf {
	return { data: data, base: 0, size: 0, cursor: 0 };
}

@inline export function hasTag(this data: Readonly<Span<uint8>>, at: int64, tag: string): boolean {
	return data.u8At(at) == tag.charCodeAt(0) && data.u8At(at + 1) == tag.charCodeAt(1) &&
		data.u8At(at + 2) == tag.charCodeAt(2) && data.u8At(at + 3) == tag.charCodeAt(3);
}

// stbtt__find_table: the table's offset from the start of the file, 0 when absent.
export function findTable(data: Readonly<Span<uint8>>, fontstart: int32, tag: string): int32 {
	const tables = data.u16At((fontstart as int64) + 4);
	const directory: int64 = (fontstart as int64) + 12;
	for (let i: int32 = 0; i < tables; i++) {
		const at: int64 = directory + 16 * (i as int64);
		if (data.hasTag(at, tag)) { return asInt32(data.u32At(at + 8)); }
	}
	return 0;
}
