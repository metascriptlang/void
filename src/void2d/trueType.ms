import {
	FontInfo,
	GlyphBox,
	Vertex,
	VERTEX_CURVE,
	VERTEX_LINE,
	VERTEX_MOVE,
	asInt32,
	findTable,
	hasTag,
	i16At,
	i32At,
	newBuf,
	truncInt,
	u16At,
	u32At,
	u8At,
	wrapInt16,
} from "./trueType/fontInfo";
when (voidCff) {
	import {
		dictGetInts,
		get8,
		getGlyphInfoT2,
		getGlyphShapeT2,
		indexGet,
		getSubrs,
		range,
		readIndex,
		seekTo,
		skip,
	} from "./trueType/cff";
}

export {
	Buf,
	FontInfo,
	GlyphBox,
	Vertex,
	VERTEX_CUBIC,
	VERTEX_CURVE,
	VERTEX_LINE,
	VERTEX_MOVE,
	asInt32,
	findTable,
	i16At,
	i32At,
	newBuf,
	u16At,
	u32At,
	u8At,
	truncInt,
	wrapInt16,
} from "./trueType/fontInfo";

const LOW_32: int64 = 0xFFFFFFFF;
const PLATFORM_ID_UNICODE: int32 = 0;
const PLATFORM_ID_MICROSOFT: int32 = 3;
const MS_EID_UNICODE_BMP: int32 = 1;
const MS_EID_UNICODE_FULL: int32 = 10;
const CFF_BUFFER_SIZE: int32 = 512 * 1024 * 1024;

export struct HMetrics {
	advance: int32;
	bearing: int32;
}

export struct VMetrics {
	ascent: int32;
	descent: int32;
	lineGap: int32;
}

function isFont(data: Readonly<Span<uint8>>): boolean {
	if (data.u8At(0) == 0x31 && data.u8At(1) == 0 && data.u8At(2) == 0 && data.u8At(3) == 0) {
		return true;
	}
	if (data.hasTag(0, "typ1") || data.hasTag(0, "OTTO")) { return true; }
	if (data.u8At(0) == 0 && data.u8At(1) == 1 && data.u8At(2) == 0 && data.u8At(3) == 0) {
		return true;
	}
	return data.hasTag(0, "true");
}

// stbtt_GetFontOffsetForIndex: -1 when `index` is not a face of the file.
export function getFontOffsetForIndex(data: Readonly<Span<uint8>>, index: int32): int32 {
	if (isFont(data)) { return index == 0 ? 0 : -1; }
	if (data.hasTag(0, "ttcf")) {
		const version = data.u32At(4);
		if (version == 0x00010000 || version == 0x00020000) {
			const count = data.i32At(8);
			if (index >= count) { return -1; }
			return asInt32(data.u32At(12 + (index as int64) * 4));
		}
	}
	return -1;
}

// stbtt_InitFont: null where stb returns 0.
export function initFont(data: Readonly<Span<uint8>>, fontstart: int32): FontInfo | null {
	let info: FontInfo = {
		data: data,
		fontstart: fontstart,
		numGlyphs: 0,
		loca: 0,
		head: 0,
		glyf: 0,
		hhea: 0,
		hmtx: 0,
		kern: 0,
		gpos: 0,
		svg: 0,
		indexMap: 0,
		indexToLocFormat: 0,
		cff: newBuf(data),
		charstrings: newBuf(data),
		gsubrs: newBuf(data),
		subrs: newBuf(data),
		fontdicts: newBuf(data),
		fdselect: newBuf(data),
	};
	const cmap = findTable(data, fontstart, "cmap");
	info.loca = findTable(data, fontstart, "loca");
	info.head = findTable(data, fontstart, "head");
	info.glyf = findTable(data, fontstart, "glyf");
	info.hhea = findTable(data, fontstart, "hhea");
	info.hmtx = findTable(data, fontstart, "hmtx");
	info.kern = findTable(data, fontstart, "kern");
	info.gpos = findTable(data, fontstart, "GPOS");
	if (cmap == 0 || info.head == 0 || info.hhea == 0 || info.hmtx == 0) { return null; }
	if (info.glyf != 0) {
		if (info.loca == 0) { return null; }
	} else {
		when (voidCff) {
			const cffTable = findTable(data, fontstart, "CFF ");
			if (cffTable == 0) { return null; }
			info.cff = { data: data, base: cffTable as int64, size: CFF_BUFFER_SIZE, cursor: 0 };
			let b = info.cff;
			b.skip(2);
			b.seekTo(b.get8() as int64);
			b.readIndex();
			let topdictIndex = b.readIndex();
			let topdict = indexGet(topdictIndex, 0);
			b.readIndex();
			info.gsubrs = b.readIndex();
			let charstrings: int32[] = [0];
			let charstringType: int32[] = [2];
			let fdarrayOffset: int32[] = [0];
			let fdselectOffset: int32[] = [0];
			topdict.dictGetInts(17, charstrings);
			topdict.dictGetInts(0x100 | 6, charstringType);
			topdict.dictGetInts(0x100 | 36, fdarrayOffset);
			topdict.dictGetInts(0x100 | 37, fdselectOffset);
			info.subrs = getSubrs(b, topdict);
			if (charstringType[0] != 2) { return null; }
			if (charstrings[0] == 0) { return null; }
			if (fdarrayOffset[0] != 0) {
				if (fdselectOffset[0] == 0) { return null; }
				b.seekTo(fdarrayOffset[0] as int64);
				info.fontdicts = b.readIndex();
				info.fdselect = b.range(
					fdselectOffset[0],
					asInt32((b.size as int64) - (fdselectOffset[0] as int64)),
				);
			}
			b.seekTo(charstrings[0] as int64);
			info.charstrings = b.readIndex();
		} else {
			return null;
		}
	}
	const maxp = findTable(data, fontstart, "maxp");
	info.numGlyphs = maxp != 0 ? data.u16At((maxp as int64) + 4) : 0xFFFF;
	info.svg = -1;
	const tables = data.u16At((cmap as int64) + 2);
	info.indexMap = 0;
	for (let i: int32 = 0; i < tables; i++) {
		const record: int64 = (cmap as int64) + 4 + 8 * (i as int64);
		const platform = data.u16At(record);
		if (platform == PLATFORM_ID_MICROSOFT) {
			const encoding = data.u16At(record + 2);
			if (encoding == MS_EID_UNICODE_BMP || encoding == MS_EID_UNICODE_FULL) {
				info.indexMap = asInt32((cmap as int64) + data.u32At(record + 4));
			}
		} else if (platform == PLATFORM_ID_UNICODE) {
			info.indexMap = asInt32((cmap as int64) + data.u32At(record + 4));
		}
	}
	if (info.indexMap == 0) { return null; }
	info.indexToLocFormat = data.u16At((info.head as int64) + 50);
	return info;
}

// stbtt_FindGlyphIndex: 0 for an unmapped codepoint or a cmap format stb does not read.
export function findGlyphIndex(info: FontInfo, codepoint: int32): int32 {
	const data = info.data;
	const map: int64 = info.indexMap as int64;
	const unsigned: int64 = (codepoint as int64) & LOW_32;
	const format = data.u16At(map);
	if (format == 0) {
		const bytes = data.u16At(map + 2);
		if (codepoint < bytes - 6) { return data.u8At(map + 6 + (codepoint as int64)); }
		return 0;
	} else if (format == 6) {
		const first = data.u16At(map + 6) as int64;
		const count = data.u16At(map + 8) as int64;
		if (unsigned >= first && unsigned < first + count) {
			return data.u16At(map + 10 + (unsigned - first) * 2);
		}
		return 0;
	} else if (format == 4) {
		const segcount = (data.u16At(map + 6) >> 1) as int64;
		let searchRange = (data.u16At(map + 8) >> 1) as int64;
		let entrySelector = data.u16At(map + 10);
		const rangeShift = (data.u16At(map + 12) >> 1) as int64;
		const endCount: int64 = map + 14;
		let search: int64 = endCount;
		if (codepoint > 0xFFFF) { return 0; }
		if (codepoint >= data.u16At(search + rangeShift * 2)) { search += rangeShift * 2; }
		search -= 2;
		while (entrySelector != 0) {
			searchRange >>= 1;
			const end = data.u16At(search + searchRange * 2);
			if (codepoint > end) { search += searchRange * 2; }
			entrySelector -= 1;
		}
		search += 2;
		const item: int64 = ((search - endCount) >> 1) & 0xFFFF;
		const start = data.u16At(map + 14 + segcount * 2 + 2 + 2 * item);
		const last = data.u16At(endCount + 2 * item);
		if (codepoint < start || codepoint > last) { return 0; }
		const offset = data.u16At(map + 14 + segcount * 6 + 2 + 2 * item) as int64;
		if (offset == 0) {
			return (codepoint + data.i16At(map + 14 + segcount * 4 + 2 + 2 * item)) & 0xFFFF;
		}
		return data.u16At(
			offset + ((codepoint - start) as int64) * 2 + map + 14 + segcount * 6 + 2 + 2 * item,
		);
	} else if (format == 12 || format == 13) {
		let low: int32 = 0;
		let high: int32 = data.i32At(map + 12);
		while (low < high) {
			const mid: int32 = low + ((high - low) >> 1);
			const group: int64 = map + 16 + (mid as int64) * 12;
			const startChar = data.u32At(group);
			const endChar = data.u32At(group + 4);
			if (unsigned < startChar) {
				high = mid;
			} else if (unsigned > endChar) {
				low = mid + 1;
			} else {
				const startGlyph = data.u32At(group + 8);
				if (format == 12) { return asInt32(startGlyph + unsigned - startChar); }
				return asInt32(startGlyph);
			}
		}
		return 0;
	}
	return 0;
}

// stbtt__GetGlyfOffset: -1 for an out-of-range, unknown-format or empty glyph.
function glyfOffset(info: FontInfo, glyphIndex: int32): int32 {
	if (glyphIndex >= info.numGlyphs) { return -1; }
	if (info.indexToLocFormat >= 2) { return -1; }
	const data = info.data;
	const loca: int64 = info.loca as int64;
	const glyf: int64 = info.glyf as int64;
	const at: int64 = glyphIndex as int64;
	let g1: int32 = 0;
	let g2: int32 = 0;
	if (info.indexToLocFormat == 0) {
		g1 = asInt32(glyf + (data.u16At(loca + at * 2) as int64) * 2);
		g2 = asInt32(glyf + (data.u16At(loca + at * 2 + 2) as int64) * 2);
	} else {
		g1 = asInt32(glyf + data.u32At(loca + at * 4));
		g2 = asInt32(glyf + data.u32At(loca + at * 4 + 4));
	}
	return g1 == g2 ? -1 : g1;
}

function sbyteAt(data: Readonly<Span<uint8>>, at: int64): int32 {
	const value = data.u8At(at);
	return value >= 0x80 ? value - 0x100 : value;
}

function vertexOf(kind: uint8, x: int32, y: int32, cx: int32, cy: int32): Vertex {
	return {
		x: wrapInt16(x),
		y: wrapInt16(y),
		cx: wrapInt16(cx),
		cy: wrapInt16(cy),
		cx1: 0,
		cy1: 0,
		kind: kind,
	};
}

function closeShape(
	ref vertices: Vec<Vertex>,
	wasOff: boolean,
	startOff: boolean,
	sx: int32,
	sy: int32,
	scx: int32,
	scy: int32,
	cx: int32,
	cy: int32,
): void {
	if (startOff) {
		if (wasOff) {
			vertices.push(vertexOf(VERTEX_CURVE, (cx + scx) >> 1, (cy + scy) >> 1, cx, cy));
		}
		vertices.push(vertexOf(VERTEX_CURVE, sx, sy, scx, scy));
	} else if (wasOff) {
		vertices.push(vertexOf(VERTEX_CURVE, sx, sy, cx, cy));
	} else {
		vertices.push(vertexOf(VERTEX_LINE, sx, sy, 0, 0));
	}
}

function simpleGlyphShape(info: FontInfo, g: int32, contours: int32): Vec<Vertex> {
	const data = info.data;
	let vertices: Vec<Vertex> = [];
	const endPoints: int64 = (g as int64) + 10;
	const instructions = data.u16At(endPoints + (contours as int64) * 2);
	let points: int64 = endPoints + (contours as int64) * 2 + 2 + (instructions as int64);
	const n: int32 = 1 + data.u16At(endPoints + (contours as int64) * 2 - 2);
	let flagsOf: int32[] = new Array<int32>(n + 1);
	let xs: int32[] = new Array<int32>(n + 1);
	let ys: int32[] = new Array<int32>(n + 1);
	let flags: int32 = 0;
	let flagCount: int32 = 0;
	for (let i: int32 = 0; i < n; i++) {
		if (flagCount == 0) {
			flags = data.u8At(points);
			points += 1;
			if ((flags & 8) != 0) {
				flagCount = data.u8At(points);
				points += 1;
			}
		} else {
			flagCount -= 1;
		}
		flagsOf[i] = flags;
	}
	let x: int32 = 0;
	for (let i: int32 = 0; i < n; i++) {
		flags = flagsOf[i];
		if ((flags & 2) != 0) {
			const dx = data.u8At(points);
			points += 1;
			x += (flags & 16) != 0 ? dx : -dx;
		} else if ((flags & 16) == 0) {
			x += data.i16At(points);
			points += 2;
		}
		xs[i] = wrapInt16(x) as int32;
	}
	let y: int32 = 0;
	for (let i: int32 = 0; i < n; i++) {
		flags = flagsOf[i];
		if ((flags & 4) != 0) {
			const dy = data.u8At(points);
			points += 1;
			y += (flags & 32) != 0 ? dy : -dy;
		} else if ((flags & 32) == 0) {
			y += data.i16At(points);
			points += 2;
		}
		ys[i] = wrapInt16(y) as int32;
	}
	let nextMove: int32 = 0;
	let contour: int32 = 0;
	let wasOff = false;
	let startOff = false;
	let sx: int32 = 0;
	let sy: int32 = 0;
	let cx: int32 = 0;
	let cy: int32 = 0;
	let scx: int32 = 0;
	let scy: int32 = 0;
	for (let i: int32 = 0; i < n; i++) {
		flags = flagsOf[i];
		x = xs[i];
		y = ys[i];
		if (nextMove == i) {
			if (i != 0) { closeShape(vertices, wasOff, startOff, sx, sy, scx, scy, cx, cy); }
			startOff = (flags & 1) == 0;
			if (startOff) {
				scx = x;
				scy = y;
				if ((flagsOf[i + 1] & 1) == 0) {
					sx = (x + xs[i + 1]) >> 1;
					sy = (y + ys[i + 1]) >> 1;
				} else {
					sx = xs[i + 1];
					sy = ys[i + 1];
					i += 1;
				}
			} else {
				sx = x;
				sy = y;
			}
			vertices.push(vertexOf(VERTEX_MOVE, sx, sy, 0, 0));
			wasOff = false;
			nextMove = 1 + data.u16At(endPoints + (contour as int64) * 2);
			contour += 1;
		} else if ((flags & 1) == 0) {
			if (wasOff) {
				vertices.push(vertexOf(VERTEX_CURVE, (cx + x) >> 1, (cy + y) >> 1, cx, cy));
			}
			cx = x;
			cy = y;
			wasOff = true;
		} else {
			if (wasOff) {
				vertices.push(vertexOf(VERTEX_CURVE, x, y, cx, cy));
			} else {
				vertices.push(vertexOf(VERTEX_LINE, x, y, 0, 0));
			}
			wasOff = false;
		}
	}
	closeShape(vertices, wasOff, startOff, sx, sy, scx, scy, cx, cy);
	return vertices;
}

function compositeGlyphShape(info: FontInfo, g: int32): Vec<Vertex> {
	const data = info.data;
	let vertices: Vec<Vertex> = [];
	let comp: int64 = (g as int64) + 10;
	let more = true;
	while (more) {
		const flags = data.u16At(comp);
		const glyph = data.u16At(comp + 2);
		comp += 4;
		let mtx: float32[] = [1, 0, 0, 1, 0, 0];
		if ((flags & 2) != 0) {
			if ((flags & 1) != 0) {
				mtx[4] = data.i16At(comp) as float32;
				mtx[5] = data.i16At(comp + 2) as float32;
				comp += 4;
			} else {
				mtx[4] = sbyteAt(data, comp) as float32;
				mtx[5] = sbyteAt(data, comp + 1) as float32;
				comp += 2;
			}
		}
		if ((flags & 8) != 0) {
			mtx[0] = (data.i16At(comp) as float32) / 16384.0;
			mtx[3] = mtx[0];
			mtx[1] = 0;
			mtx[2] = 0;
			comp += 2;
		} else if ((flags & 64) != 0) {
			mtx[0] = (data.i16At(comp) as float32) / 16384.0;
			mtx[1] = 0;
			mtx[2] = 0;
			mtx[3] = (data.i16At(comp + 2) as float32) / 16384.0;
			comp += 4;
		} else if ((flags & 128) != 0) {
			mtx[0] = (data.i16At(comp) as float32) / 16384.0;
			mtx[1] = (data.i16At(comp + 2) as float32) / 16384.0;
			mtx[2] = (data.i16At(comp + 4) as float32) / 16384.0;
			mtx[3] = (data.i16At(comp + 6) as float32) / 16384.0;
			comp += 8;
		}
		const m = Math.sqrt((mtx[0] * mtx[0] + mtx[1] * mtx[1]) as float64) as float32;
		const n = Math.sqrt((mtx[2] * mtx[2] + mtx[3] * mtx[3]) as float64) as float32;
		const part = getGlyphShape(info, glyph);
		for (let i: int32 = 0; i < (part.length as int32); i++) {
			let v = part[i];
			const x = v.x as float32;
			const y = v.y as float32;
			const cx = v.cx as float32;
			const cy = v.cy as float32;
			v.x = wrapInt16(truncInt((m * (mtx[0] * x + mtx[2] * y + mtx[4])) as float64));
			v.y = wrapInt16(truncInt((n * (mtx[1] * x + mtx[3] * y + mtx[5])) as float64));
			v.cx = wrapInt16(truncInt((m * (mtx[0] * cx + mtx[2] * cy + mtx[4])) as float64));
			v.cy = wrapInt16(truncInt((n * (mtx[1] * cx + mtx[3] * cy + mtx[5])) as float64));
			vertices.push(v);
		}
		more = (flags & 32) != 0;
	}
	return vertices;
}

// stbtt_GetGlyphShape: the outline in font units; empty where stb returns 0 vertices.
export function getGlyphShape(info: FontInfo, glyphIndex: int32): Vec<Vertex> {
	when (voidCff) {
		if (info.cff.size != 0) { return getGlyphShapeT2(info, glyphIndex); }
	}
	const g = glyfOffset(info, glyphIndex);
	if (g < 0) { return []; }
	const contours = info.data.i16At(g);
	if (contours > 0) { return simpleGlyphShape(info, g, contours); }
	if (contours < 0) { return compositeGlyphShape(info, g); }
	return [];
}

// stbtt_GetGlyphBox: null where stb returns 0 (an empty glyph, e.g. a space).
export function getGlyphBox(info: FontInfo, glyphIndex: int32): GlyphBox | null {
	when (voidCff) {
		if (info.cff.size != 0) { return getGlyphInfoT2(info, glyphIndex); }
	}
	const g = glyfOffset(info, glyphIndex);
	if (g < 0) { return null; }
	const data = info.data;
	return {
		x0: data.i16At((g as int64) + 2),
		y0: data.i16At((g as int64) + 4),
		x1: data.i16At((g as int64) + 6),
		y1: data.i16At((g as int64) + 8),
	};
}

export function getGlyphHMetrics(info: FontInfo, glyphIndex: int32): HMetrics {
	const data = info.data;
	const hmtx: int64 = info.hmtx as int64;
	const at: int64 = glyphIndex as int64;
	const longMetrics = data.u16At((info.hhea as int64) + 34);
	if (glyphIndex < longMetrics) {
		return { advance: data.i16At(hmtx + 4 * at), bearing: data.i16At(hmtx + 4 * at + 2) };
	}
	const longs: int64 = longMetrics as int64;
	return {
		advance: data.i16At(hmtx + 4 * (longs - 1)),
		bearing: data.i16At(hmtx + 4 * longs + 2 * (at - longs)),
	};
}

export function getFontVMetrics(info: FontInfo): VMetrics {
	const hhea: int64 = info.hhea as int64;
	return {
		ascent: info.data.i16At(hhea + 4),
		descent: info.data.i16At(hhea + 6),
		lineGap: info.data.i16At(hhea + 8),
	};
}

export function scaleForMappingEmToPixels(info: FontInfo, pixels: float32): float32 {
	const unitsPerEm = info.data.u16At((info.head as int64) + 18);
	return pixels / (unitsPerEm as float32);
}

// stbtt__GetGlyphKernInfoAdvance: the first horizontal format-0 `kern` subtable.
export function getGlyphKernInfoAdvance(info: FontInfo, glyph1: int32, glyph2: int32): int32 {
	if (info.kern == 0) { return 0; }
	const data = info.data;
	const table: int64 = info.kern as int64;
	if (data.u16At(table + 2) < 1) { return 0; }
	if (data.u16At(table + 8) != 1) { return 0; }
	let l: int32 = 0;
	let r: int32 = data.u16At(table + 10) - 1;
	const needle: int64 = ((((glyph1 as int64) << 16) | (glyph2 as int64)) & LOW_32);
	while (l <= r) {
		const m: int32 = (l + r) >> 1;
		const straw = data.u32At(table + 18 + (m as int64) * 6);
		if (needle < straw) {
			r = m - 1;
		} else if (needle > straw) {
			l = m + 1;
		} else {
			return data.i16At(table + 22 + (m as int64) * 6);
		}
	}
	return 0;
}

// stbtt__GetCoverageIndex: `table` is the offset of an OpenType Coverage table; -1 if absent.
export function getCoverageIndex(
	data: Readonly<Span<uint8>>,
	table: int64,
	glyph: int32,
): int32 {
	const format = data.u16At(table);
	if (format == 1) {
		let l: int32 = 0;
		let r: int32 = data.u16At(table + 2) - 1;
		while (l <= r) {
			const m: int32 = (l + r) >> 1;
			const straw = data.u16At(table + 4 + 2 * (m as int64));
			if (glyph < straw) {
				r = m - 1;
			} else if (glyph > straw) {
				l = m + 1;
			} else {
				return m;
			}
		}
	} else if (format == 2) {
		let l: int32 = 0;
		let r: int32 = data.u16At(table + 2) - 1;
		while (l <= r) {
			const m: int32 = (l + r) >> 1;
			const record: int64 = table + 4 + 6 * (m as int64);
			const strawStart = data.u16At(record);
			const strawEnd = data.u16At(record + 2);
			if (glyph < strawStart) {
				r = m - 1;
			} else if (glyph > strawEnd) {
				l = m + 1;
			} else {
				return data.u16At(record + 4) + glyph - strawStart;
			}
		}
	} else {
		return -1;
	}
	return -1;
}

// stbtt__GetGlyphClass: `table` is the offset of a ClassDef table; -1 for an unknown format.
export function getGlyphClass(data: Readonly<Span<uint8>>, table: int64, glyph: int32): int32 {
	const format = data.u16At(table);
	if (format == 1) {
		const startGlyph = data.u16At(table + 2);
		const count = data.u16At(table + 4);
		if (glyph >= startGlyph && glyph < startGlyph + count) {
			return data.u16At(table + 6 + 2 * ((glyph - startGlyph) as int64));
		}
	} else if (format == 2) {
		let l: int32 = 0;
		let r: int32 = data.u16At(table + 2) - 1;
		while (l <= r) {
			const m: int32 = (l + r) >> 1;
			const record: int64 = table + 4 + 6 * (m as int64);
			const strawStart = data.u16At(record);
			const strawEnd = data.u16At(record + 2);
			if (glyph < strawStart) {
				r = m - 1;
			} else if (glyph > strawEnd) {
				l = m + 1;
			} else {
				return data.u16At(record + 4);
			}
		}
	} else {
		return -1;
	}
	return 0;
}
