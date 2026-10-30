import {
	Buf,
	FontInfo,
	GlyphBox,
	Vertex,
	VERTEX_CUBIC,
	VERTEX_LINE,
	VERTEX_MOVE,
	asInt32,
	newBuf,
	truncInt,
	u8At,
	wrapInt16,
} from "./fontInfo";

const MAX_SUBR_DEPTH: int32 = 10;
const MAX_STACK: int32 = 48;

export function get8(this ref b: Buf): int32 {
	if (b.cursor >= b.size) { return 0; }
	const value = b.data.u8At(b.base + (b.cursor as int64));
	b.cursor += 1;
	return value;
}

export function peek8(this b: Buf): int32 {
	if (b.cursor >= b.size) { return 0; }
	return b.data.u8At(b.base + (b.cursor as int64));
}

export function seekTo(this ref b: Buf, offset: int64): void {
	b.cursor = (offset > (b.size as int64) || offset < 0) ? b.size : (offset as int32);
}

export function skip(this ref b: Buf, offset: int32): void {
	b.seekTo((b.cursor as int64) + (offset as int64));
}

// stbtt__buf_get: n big-endian bytes as an unsigned value.
export function getBytes(this ref b: Buf, n: int32): int64 {
	let value: int64 = 0;
	for (let i: int32 = 0; i < n; i++) {
		value = ((value << 8) | (b.get8() as int64)) & 0xFFFFFFFF;
	}
	return value;
}

function get16(this ref b: Buf): int32 {
	return b.getBytes(2) as int32;
}

export function range(this b: Buf, offset: int32, size: int32): Buf {
	if (offset < 0 || size < 0 || offset > b.size || size > b.size - offset) {
		return newBuf(b.data);
	}
	return { data: b.data, base: b.base + (offset as int64), size: size, cursor: 0 };
}

export function readIndex(this ref b: Buf): Buf {
	const start = b.cursor;
	const count = b.get16();
	if (count != 0) {
		const offsetSize = b.get8();
		b.skip(offsetSize * count);
		b.skip(asInt32(b.getBytes(offsetSize) - 1));
	}
	return b.range(start, b.cursor - start);
}

export function readInt(this ref b: Buf): int32 {
	const b0 = b.get8();
	if (b0 >= 32 && b0 <= 246) { return b0 - 139; }
	if (b0 >= 247 && b0 <= 250) { return (b0 - 247) * 256 + b.get8() + 108; }
	if (b0 >= 251 && b0 <= 254) { return -(b0 - 251) * 256 - b.get8() - 108; }
	if (b0 == 28) { return b.get16(); }
	if (b0 == 29) { return asInt32(b.getBytes(4)); }
	return 0;
}

function skipOperand(this ref b: Buf): void {
	const b0 = b.peek8();
	if (b0 == 30) {
		b.skip(1);
		while (b.cursor < b.size) {
			const v = b.get8();
			if ((v & 0xF) == 0xF || (v >> 4) == 0xF) { break; }
		}
	} else {
		b.readInt();
	}
}

function dictGet(this ref b: Buf, key: int32): Buf {
	b.seekTo(0);
	while (b.cursor < b.size) {
		const start = b.cursor;
		while (b.peek8() >= 28) { b.skipOperand(); }
		const end = b.cursor;
		let op = b.get8();
		if (op == 12) { op = b.get8() | 0x100; }
		if (op == key) { return b.range(start, end - start); }
	}
	return b.range(0, 0);
}

// Fills out[0..] with the operands of `key`, leaving the entries the dict lacks untouched.
export function dictGetInts(this ref b: Buf, key: int32, out: int32[]): void {
	let operands = b.dictGet(key);
	for (let i: int32 = 0; i < (out.length as int32) && operands.cursor < operands.size; i++) {
		out[i] = operands.readInt();
	}
}

function indexCount(this ref b: Buf): int32 {
	b.seekTo(0);
	return b.get16();
}

export function indexGet(index: Buf, i: int32): Buf {
	let b = index;
	b.seekTo(0);
	const count = b.get16();
	const offsetSize = b.get8();
	b.skip(i * offsetSize);
	const start = asInt32(b.getBytes(offsetSize));
	const end = asInt32(b.getBytes(offsetSize));
	return b.range(
		asInt32(2 + ((count + 1) as int64) * (offsetSize as int64) + (start as int64)),
		asInt32((end as int64) - (start as int64)),
	);
}

export function getSubrs(cff: Buf, fontdict: Buf): Buf {
	let dict = fontdict;
	let privateLoc: int32[] = [0, 0];
	dict.dictGetInts(18, privateLoc);
	if (privateLoc[1] == 0 || privateLoc[0] == 0) { return newBuf(cff.data); }
	let privateDict = cff.range(privateLoc[1], privateLoc[0]);
	let subrsOffset: int32[] = [0];
	privateDict.dictGetInts(19, subrsOffset);
	if (subrsOffset[0] == 0) { return newBuf(cff.data); }
	let source = cff;
	source.seekTo(asInt32((privateLoc[1] as int64) + (subrsOffset[0] as int64)) as int64);
	return source.readIndex();
}

function getSubr(index: Buf, n: int32): Buf {
	let b = index;
	const count = b.indexCount();
	let bias: int64 = 107;
	if (count >= 33900) {
		bias = 32768;
	} else if (count >= 1240) {
		bias = 1131;
	}
	const biased: int64 = (n as int64) + bias;
	if (biased < 0 || biased >= (count as int64)) { return newBuf(index.data); }
	return indexGet(index, biased as int32);
}

function cidGetGlyphSubrs(info: FontInfo, glyphIndex: int32): Buf {
	let fdselect = info.fdselect;
	let fdselector: int32 = -1;
	fdselect.seekTo(0);
	const format = fdselect.get8();
	if (format == 0) {
		fdselect.skip(glyphIndex);
		fdselector = fdselect.get8();
	} else if (format == 3) {
		const ranges = fdselect.get16();
		let start = fdselect.get16();
		for (let i: int32 = 0; i < ranges; i++) {
			const v = fdselect.get8();
			const end = fdselect.get16();
			if (glyphIndex >= start && glyphIndex < end) {
				fdselector = v;
				break;
			}
			start = end;
		}
	}
	return getSubrs(info.cff, indexGet(info.fontdicts, fdselector));
}

struct CsCtx {
	bounds: boolean;
	started: boolean;
	firstX: float32;
	firstY: float32;
	x: float32;
	y: float32;
	minX: int32;
	maxX: int32;
	minY: int32;
	maxY: int32;
	vertices: Vec<Vertex>;
	numVertices: int32;
}

function newCtx(bounds: boolean): CsCtx {
	return {
		bounds: bounds,
		started: false,
		firstX: 0,
		firstY: 0,
		x: 0,
		y: 0,
		minX: 0,
		maxX: 0,
		minY: 0,
		maxY: 0,
		vertices: [],
		numVertices: 0,
	};
}

function trackVertex(this ref c: CsCtx, x: int32, y: int32): void {
	if (x > c.maxX || !c.started) { c.maxX = x; }
	if (y > c.maxY || !c.started) { c.maxY = y; }
	if (x < c.minX || !c.started) { c.minX = x; }
	if (y < c.minY || !c.started) { c.minY = y; }
	c.started = true;
}

function addVertex(
	this ref c: CsCtx,
	kind: uint8,
	x: int32,
	y: int32,
	cx: int32,
	cy: int32,
	cx1: int32,
	cy1: int32,
): void {
	if (c.bounds) {
		c.trackVertex(x, y);
		if (kind == VERTEX_CUBIC) {
			c.trackVertex(cx, cy);
			c.trackVertex(cx1, cy1);
		}
	} else {
		c.vertices.push({
			x: wrapInt16(x),
			y: wrapInt16(y),
			cx: wrapInt16(cx),
			cy: wrapInt16(cy),
			cx1: wrapInt16(cx1),
			cy1: wrapInt16(cy1),
			kind: kind,
		});
	}
	c.numVertices += 1;
}

function closeShape(this ref c: CsCtx): void {
	if (c.firstX != c.x || c.firstY != c.y) {
		c.addVertex(VERTEX_LINE, truncInt(c.firstX as float64), truncInt(c.firstY as float64), 0, 0, 0, 0);
	}
}

function rMoveTo(this ref c: CsCtx, dx: float32, dy: float32): void {
	c.closeShape();
	c.x = c.x + dx;
	c.y = c.y + dy;
	c.firstX = c.x;
	c.firstY = c.y;
	c.addVertex(VERTEX_MOVE, truncInt(c.x as float64), truncInt(c.y as float64), 0, 0, 0, 0);
}

function rLineTo(this ref c: CsCtx, dx: float32, dy: float32): void {
	c.x += dx;
	c.y += dy;
	c.addVertex(VERTEX_LINE, truncInt(c.x as float64), truncInt(c.y as float64), 0, 0, 0, 0);
}

function rCurveTo(
	this ref c: CsCtx,
	dx1: float32,
	dy1: float32,
	dx2: float32,
	dy2: float32,
	dx3: float32,
	dy3: float32,
): void {
	const cx1: float32 = c.x + dx1;
	const cy1: float32 = c.y + dy1;
	const cx2: float32 = cx1 + dx2;
	const cy2: float32 = cy1 + dy2;
	c.x = cx2 + dx3;
	c.y = cy2 + dy3;
	c.addVertex(
		VERTEX_CUBIC,
		truncInt(c.x as float64),
		truncInt(c.y as float64),
		truncInt(cx1 as float64),
		truncInt(cy1 as float64),
		truncInt(cx2 as float64),
		truncInt(cy2 as float64),
	);
}

// stbtt__run_charstring; false is every STBTT__CSERR (a charstring stb refuses).
function runCharstring(info: FontInfo, glyphIndex: int32, ref c: CsCtx): boolean {
	let inHeader = true;
	let maskbits: int32 = 0;
	let subrStackHeight: int32 = 0;
	let sp: int32 = 0;
	let hasSubrs = false;
	let s: float32[] = new Array<float32>(MAX_STACK);
	let subrStack: Buf[] = new Array<Buf>(MAX_SUBR_DEPTH);
	let subrs = info.subrs;
	let b = indexGet(info.charstrings, glyphIndex);
	while (b.cursor < b.size) {
		let i: int32 = 0;
		let clearStack = true;
		const b0 = b.get8();
		if (b0 == 0x13 || b0 == 0x14) {
			if (inHeader) { maskbits += sp / 2; }
			inHeader = false;
			b.skip((maskbits + 7) / 8);
		} else if (b0 == 0x01 || b0 == 0x03 || b0 == 0x12 || b0 == 0x17) {
			maskbits += sp / 2;
		} else if (b0 == 0x15) {
			inHeader = false;
			if (sp < 2) { return false; }
			c.rMoveTo(s[sp - 2], s[sp - 1]);
		} else if (b0 == 0x04) {
			inHeader = false;
			if (sp < 1) { return false; }
			c.rMoveTo(0, s[sp - 1]);
		} else if (b0 == 0x16) {
			inHeader = false;
			if (sp < 1) { return false; }
			c.rMoveTo(s[sp - 1], 0);
		} else if (b0 == 0x05) {
			if (sp < 2) { return false; }
			while (i + 1 < sp) {
				c.rLineTo(s[i], s[i + 1]);
				i += 2;
			}
		} else if (b0 == 0x06 || b0 == 0x07) {
			if (sp < 1) { return false; }
			let vertical = b0 == 0x07;
			while (true) {
				if (!vertical) {
					if (i >= sp) { break; }
					c.rLineTo(s[i], 0);
					i++;
				}
				vertical = false;
				if (i >= sp) { break; }
				c.rLineTo(0, s[i]);
				i++;
			}
		} else if (b0 == 0x1E || b0 == 0x1F) {
			if (sp < 4) { return false; }
			let horizontal = b0 == 0x1F;
			while (true) {
				if (!horizontal) {
					if (i + 3 >= sp) { break; }
					c.rCurveTo(0, s[i], s[i + 1], s[i + 2], s[i + 3], (sp - i == 5) ? s[i + 4] : 0.0);
					i += 4;
				}
				horizontal = false;
				if (i + 3 >= sp) { break; }
				c.rCurveTo(s[i], 0, s[i + 1], s[i + 2], (sp - i == 5) ? s[i + 4] : 0.0, s[i + 3]);
				i += 4;
			}
		} else if (b0 == 0x08) {
			if (sp < 6) { return false; }
			while (i + 5 < sp) {
				c.rCurveTo(s[i], s[i + 1], s[i + 2], s[i + 3], s[i + 4], s[i + 5]);
				i += 6;
			}
		} else if (b0 == 0x18) {
			if (sp < 8) { return false; }
			while (i + 5 < sp - 2) {
				c.rCurveTo(s[i], s[i + 1], s[i + 2], s[i + 3], s[i + 4], s[i + 5]);
				i += 6;
			}
			if (i + 1 >= sp) { return false; }
			c.rLineTo(s[i], s[i + 1]);
		} else if (b0 == 0x19) {
			if (sp < 8) { return false; }
			while (i + 1 < sp - 6) {
				c.rLineTo(s[i], s[i + 1]);
				i += 2;
			}
			if (i + 5 >= sp) { return false; }
			c.rCurveTo(s[i], s[i + 1], s[i + 2], s[i + 3], s[i + 4], s[i + 5]);
		} else if (b0 == 0x1A || b0 == 0x1B) {
			if (sp < 4) { return false; }
			let f: float32 = 0;
			if ((sp & 1) != 0) {
				f = s[i];
				i++;
			}
			while (i + 3 < sp) {
				if (b0 == 0x1B) {
					c.rCurveTo(s[i], f, s[i + 1], s[i + 2], s[i + 3], 0);
				} else {
					c.rCurveTo(f, s[i], s[i + 1], s[i + 2], 0, s[i + 3]);
				}
				f = 0;
				i += 4;
			}
		} else if (b0 == 0x0A || b0 == 0x1D) {
			if (b0 == 0x0A && !hasSubrs) {
				if (info.fdselect.size != 0) { subrs = cidGetGlyphSubrs(info, glyphIndex); }
				hasSubrs = true;
			}
			if (sp < 1) { return false; }
			sp -= 1;
			const v = truncInt(s[sp] as float64);
			if (subrStackHeight >= MAX_SUBR_DEPTH) { return false; }
			subrStack[subrStackHeight] = b;
			subrStackHeight += 1;
			b = getSubr(b0 == 0x0A ? subrs : info.gsubrs, v);
			if (b.size == 0) { return false; }
			b.cursor = 0;
			clearStack = false;
		} else if (b0 == 0x0B) {
			if (subrStackHeight <= 0) { return false; }
			subrStackHeight -= 1;
			b = subrStack[subrStackHeight];
			clearStack = false;
		} else if (b0 == 0x0E) {
			c.closeShape();
			return true;
		} else if (b0 == 0x0C) {
			const b1 = b.get8();
			if (b1 == 0x22) {
				if (sp < 7) { return false; }
				c.rCurveTo(s[0], 0, s[1], s[2], s[3], 0);
				c.rCurveTo(s[4], 0, s[5], -s[2], s[6], 0);
			} else if (b1 == 0x23) {
				if (sp < 13) { return false; }
				c.rCurveTo(s[0], s[1], s[2], s[3], s[4], s[5]);
				c.rCurveTo(s[6], s[7], s[8], s[9], s[10], s[11]);
			} else if (b1 == 0x24) {
				if (sp < 9) { return false; }
				c.rCurveTo(s[0], s[1], s[2], s[3], s[4], 0);
				c.rCurveTo(s[5], 0, s[6], s[7], s[8], -(s[1] + s[3] + s[7]));
			} else if (b1 == 0x25) {
				if (sp < 11) { return false; }
				let dx6: float32 = s[10];
				let dy6: float32 = s[10];
				const dx: float32 = s[0] + s[2] + s[4] + s[6] + s[8];
				const dy: float32 = s[1] + s[3] + s[5] + s[7] + s[9];
				if (Math.abs(dx as float64) > Math.abs(dy as float64)) {
					dy6 = -dy;
				} else {
					dx6 = -dx;
				}
				c.rCurveTo(s[0], s[1], s[2], s[3], s[4], s[5]);
				c.rCurveTo(s[6], s[7], s[8], s[9], dx6, dy6);
			} else {
				return false;
			}
		} else {
			if (b0 != 255 && b0 != 28 && b0 < 32) { return false; }
			let f: float32 = 0;
			if (b0 == 255) {
				f = (asInt32(b.getBytes(4)) as float32) / 65536;
			} else {
				b.skip(-1);
				f = wrapInt16(b.readInt()) as float32;
			}
			if (sp >= MAX_STACK) { return false; }
			s[sp] = f;
			sp += 1;
			clearStack = false;
		}
		if (clearStack) { sp = 0; }
	}
	return false;
}

// stbtt__GetGlyphShapeT2: the outline of a CFF glyph, empty when stb returns 0.
export function getGlyphShapeT2(info: FontInfo, glyphIndex: int32): Vec<Vertex> {
	let c = newCtx(false);
	if (runCharstring(info, glyphIndex, c)) { return move c.vertices; }
	return [];
}

// stbtt__GetGlyphInfoT2: the control-point box of a CFF glyph, zeros when stb returns 0.
export function getGlyphInfoT2(info: FontInfo, glyphIndex: int32): GlyphBox {
	let c = newCtx(true);
	if (!runCharstring(info, glyphIndex, c)) { return { x0: 0, y0: 0, x1: 0, y1: 0 }; }
	return { x0: c.minX, y0: c.minY, x1: c.maxX, y1: c.maxY };
}
