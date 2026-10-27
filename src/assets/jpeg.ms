// Void Asset — the JPEG decoder: stb_image.h's JPEG path (baseline and progressive, Huffman
// decoding, the integer IDCT, the resamplers, YCbCr, CMYK and YCCK conversion), alike on every
// target. Arithmetic that stb leaves to int wrap-around (the IDCT on corrupt coefficients) is
// done in uint32 so a hostile file cannot stop the program.

import { INT_MAX, mad2Valid, mad3Valid, zeros16, zeros32, zeros8, zerosU32 } from "./stbCommon";

export struct JpegImage {
	width: int32;
	height: int32;
	channels: int32;
	pixels: uint8[];
}

export struct JpegInfo {
	width: int32;
	height: int32;
	channels: int32;
}

const FAST_BITS: int32 = 9;
const FAST_SIZE: int32 = 512;
const MARKER_NONE: int32 = 0xFF;

const BMASK: uint32[] = [
	0, 1, 3, 7, 15, 31, 63, 127, 255, 511, 1023, 2047, 4095, 8191, 16383, 32767, 65535,
];
const JBIAS: int32[] = [
	0, -1, -3, -7, -15, -31, -63, -127, -255, -511, -1023, -2047, -4095, -8191, -16383, -32767,
];
const DEZIGZAG: int32[] = [
	0, 1, 8, 16, 9, 2, 3, 10,
	17, 24, 32, 25, 18, 11, 4, 5,
	12, 19, 26, 33, 40, 48, 41, 34,
	27, 20, 13, 6, 7, 14, 21, 28,
	35, 42, 49, 56, 57, 50, 43, 36,
	29, 22, 15, 23, 30, 37, 44, 51,
	58, 59, 52, 45, 38, 31, 39, 46,
	53, 60, 61, 54, 47, 55, 62, 63,
	63, 63, 63, 63, 63, 63, 63, 63,
	63, 63, 63, 63, 63, 63, 63,
];

enum Scan {
	Load,
	Type,
	Header,
}

enum Resampler {
	One,
	V2,
	H2,
	Hv2,
	Generic,
}

let failureReason: string | null = null;

// stbi_failure_reason: set by every failure, never cleared.
export function jpegFailureReason(): string | null {
	return failureReason;
}

function fail(reason: string): boolean {
	failureReason = reason;
	return false;
}

// (short) of an int.
function wrapShort(value: int32): int32 {
	return ((value & 0xFFFF) ^ 0x8000) - 0x8000;
}

function addintsValid(a: int32, b: int32): boolean {
	if ((a >= 0) != (b >= 0)) { return true; }
	if (a < 0 && b < 0) { return (a as int64) >= -2147483648 - (b as int64); }
	return (a as int64) <= INT_MAX - (b as int64);
}

function mul2shortsValid(a: int32, b: int32): boolean {
	if (b == 0 || b == -1) { return true; }
	if ((a >= 0) == (b >= 0)) { return a <= 32767 / b; }
	if (b < 0) { return a <= -32768 / b; }
	return a >= -32768 / b;
}

function lrot(value: uint32, count: int32): uint32 {
	return (value << (count as uint32)) | (value >> (((32 - count) & 31) as uint32));
}

class Huffman {
	fast: uint8[] = zeros8(FAST_SIZE);
	code: uint16[] = zeros16(256);
	values: uint8[] = zeros8(256);
	size: uint8[] = zeros8(257);
	maxcode: uint32[] = zerosU32(18);
	delta: int32[] = zeros32(17);
}

class Component {
	id: int32 = 0;
	h: int32 = 0;
	v: int32 = 0;
	tq: int32 = 0;
	hd: int32 = 0;
	ha: int32 = 0;
	dcPred: int32 = 0;
	x: int32 = 0;
	y: int32 = 0;
	w2: int32 = 0;
	h2: int32 = 0;
	data: uint8[] = [];
	coeff: int32[] = [];
	coeffW: int32 = 0;
	coeffH: int32 = 0;
	linebuf: uint8[] = [];
}

class Plane {
	buf: uint8[] = [];
	off: int32 = 0;
}

class Resample {
	kind: Resampler = Resampler.One;
	line0: int32 = 0;
	line1: int32 = 0;
	hs: int32 = 0;
	vs: int32 = 0;
	wLores: int32 = 0;
	ystep: int32 = 0;
	ypos: int32 = 0;
}

struct JpegInput {
	bytes: Readonly<Span<uint8>>;
}

class JpegDecoder {
	input: JpegInput;
	pos: int64 = 0;
	maxSide: int32;
	imgX: int32 = 0;
	imgY: int32 = 0;
	imgN: int32 = 0;
	huffDc: Huffman[] = [new Huffman(), new Huffman(), new Huffman(), new Huffman()];
	huffAc: Huffman[] = [new Huffman(), new Huffman(), new Huffman(), new Huffman()];
	dequant: int32[] = zeros32(256);
	fastAc: int32[] = zeros32(4 * FAST_SIZE);
	comps: Component[] = [new Component(), new Component(), new Component(), new Component()];
	imgHMax: int32 = 0;
	imgVMax: int32 = 0;
	imgMcuX: int32 = 0;
	imgMcuY: int32 = 0;
	imgMcuW: int32 = 0;
	imgMcuH: int32 = 0;
	codeBuffer: uint32 = 0;
	codeBits: int32 = 0;
	marker: int32 = MARKER_NONE;
	nomore: boolean = false;
	progressive: boolean = false;
	specStart: int32 = 0;
	specEnd: int32 = 0;
	succHigh: int32 = 0;
	succLow: int32 = 0;
	eobRun: int32 = 0;
	jfif: boolean = false;
	app14ColorTransform: int32 = -1;
	rgb: int32 = 0;
	scanN: int32 = 0;
	order: int32[] = zeros32(4);
	restartInterval: int32 = 0;
	todo: int32 = 0;
	block: int32[] = zeros32(64);
	idctVal: uint32[] = zerosU32(64);
	idctOut: uint32[] = zerosU32(8);

	constructor(input: JpegInput, maxSide: int32) {
		this.input = input;
		this.maxSide = maxSide;
	}
}

function get8(this j: JpegDecoder): int32 {
	if (j.pos < (j.input.bytes.length as int64)) {
		const value = j.input.bytes[j.pos as int32] as int32;
		j.pos++;
		return value;
	}
	return 0;
}

function get16be(this j: JpegDecoder): int32 {
	const z = j.get8();
	return (z << 8) + j.get8();
}

function atEof(this j: JpegDecoder): boolean {
	return j.pos >= (j.input.bytes.length as int64);
}

function skip(this j: JpegDecoder, n: int32): void {
	if (n == 0) { return; }
	if (n < 0) {
		j.pos = j.input.bytes.length as int64;
		return;
	}
	j.pos += n as int64;
}

function buildHuffman(h: Huffman, count: int32[]): boolean {
	let k: int32 = 0;
	for (let i: int32 = 0; i < 16; i++) {
		for (let j: int32 = 0; j < count[i]; j++) {
			h.size[k] = (i + 1) as uint8;
			k++;
			if (k >= 257) { return fail("bad size list"); }
		}
	}
	h.size[k] = 0;

	let code: uint32 = 0;
	k = 0;
	let j: int32 = 0;
	for (j = 1; j <= 16; j++) {
		h.delta[j] = k - (code as int32);
		if ((h.size[k] as int32) == j) {
			while ((h.size[k] as int32) == j) {
				h.code[k] = (code & 0xFFFF) as uint16;
				k++;
				code++;
			}
			if (code - 1 >= ((1 as uint32) << (j as uint32))) { return fail("bad code lengths"); }
		}
		h.maxcode[j] = code << ((16 - j) as uint32);
		code = code << 1;
	}
	h.maxcode[j] = 0xFFFFFFFF;

	for (let i: int32 = 0; i < FAST_SIZE; i++) { h.fast[i] = 255; }
	for (let i: int32 = 0; i < k; i++) {
		const s = h.size[i] as int32;
		if (s <= FAST_BITS) {
			const c = (h.code[i] as int32) << (FAST_BITS - s);
			const m = 1 << (FAST_BITS - s);
			for (let n: int32 = 0; n < m; n++) { h.fast[c + n] = i as uint8; }
		}
	}
	return true;
}

// A table that decodes both magnitude and value of small ACs in one go.
function buildFastAc(fastAc: int32[], base: int32, h: Huffman): void {
	for (let i: int32 = 0; i < FAST_SIZE; i++) {
		const fast = h.fast[i] as int32;
		fastAc[base + i] = 0;
		if (fast < 255) {
			const rs = h.values[fast] as int32;
			const run = (rs >> 4) & 15;
			const magbits = rs & 15;
			const len = h.size[fast] as int32;
			if (magbits != 0 && len + magbits <= FAST_BITS) {
				let k = ((i << len) & (FAST_SIZE - 1)) >> (FAST_BITS - magbits);
				const m = 1 << (magbits - 1);
				if (k < m) { k += 1 - (1 << magbits); }
				if (k >= -128 && k <= 127) {
					fastAc[base + i] = (k * 256) + (run * 16) + (len + magbits);
				}
			}
		}
	}
}

function growBuffer(this j: JpegDecoder): void {
	do {
		const b: uint32 = j.nomore ? 0 : (j.get8() as uint32);
		if (b == 0xFF) {
			let c = j.get8();
			while (c == 0xFF) { c = j.get8(); }
			if (c != 0) {
				j.marker = c;
				j.nomore = true;
				return;
			}
		}
		if (b != 0) { j.codeBuffer = j.codeBuffer | (b << ((24 - j.codeBits) as uint32)); }
		j.codeBits += 8;
	} while (j.codeBits <= 24);
}

// A Huffman value from the bitstream, -1 on a code that is not in the table.
function huffDecode(this j: JpegDecoder, h: Huffman): int32 {
	if (j.codeBits < 16) { j.growBuffer(); }
	let c = ((j.codeBuffer >> ((32 - FAST_BITS) as uint32)) & ((FAST_SIZE - 1) as uint32)) as int32;
	let k = h.fast[c] as int32;
	if (k < 255) {
		const s = h.size[k] as int32;
		if (s > j.codeBits) { return -1; }
		j.codeBuffer = j.codeBuffer << (s as uint32);
		j.codeBits -= s;
		return h.values[k] as int32;
	}
	const temp: uint32 = j.codeBuffer >> 16;
	k = FAST_BITS + 1;
	while (temp >= h.maxcode[k]) { k++; }
	if (k == 17) {
		j.codeBits -= 16;
		return -1;
	}
	if (k > j.codeBits) { return -1; }
	c = (((j.codeBuffer >> ((32 - k) as uint32)) & BMASK[k]) as int32) + h.delta[k];
	if (c < 0 || c >= 256) { return -1; }
	j.codeBits -= k;
	j.codeBuffer = j.codeBuffer << (k as uint32);
	return h.values[c] as int32;
}

// JPEG 'receive' and 'extend' in one, since baseline always extends everything it receives.
function extendReceive(this j: JpegDecoder, n: int32): int32 {
	if (j.codeBits < n) { j.growBuffer(); }
	if (j.codeBits < n) { return 0; }
	const sgn = (j.codeBuffer >> 31) as int32;
	let k: uint32 = lrot(j.codeBuffer, n);
	j.codeBuffer = k & ~BMASK[n];
	k = k & BMASK[n];
	j.codeBits -= n;
	return (k as int32) + (JBIAS[n] & (sgn - 1));
}

function getBits(this j: JpegDecoder, n: int32): int32 {
	if (j.codeBits < n) { j.growBuffer(); }
	if (j.codeBits < n) { return 0; }
	const k: uint32 = lrot(j.codeBuffer, n);
	j.codeBuffer = k & ~BMASK[n];
	j.codeBits -= n;
	return (k & BMASK[n]) as int32;
}

function getBit(this j: JpegDecoder): boolean {
	if (j.codeBits < 1) { j.growBuffer(); }
	if (j.codeBits < 1) { return false; }
	const k = j.codeBuffer;
	j.codeBuffer = j.codeBuffer << 1;
	j.codeBits--;
	return (k & 0x80000000) != 0;
}

// One 64-entry block into data at dataOff, dequantized and de-zigzagged.
function decodeBlock(
	this j: JpegDecoder, data: int32[], dataOff: int32, hdc: Huffman, hac: Huffman, fac: int32,
	b: int32, dq: int32,
): boolean {
	if (j.codeBits < 16) { j.growBuffer(); }
	const t = j.huffDecode(hdc);
	if (t < 0 || t > 15) { return fail("bad huffman code"); }

	for (let i: int32 = 0; i < 64; i++) { data[dataOff + i] = 0; }

	const diff = t != 0 ? j.extendReceive(t) : 0;
	const comp = j.comps[b];
	if (!addintsValid(comp.dcPred, diff)) { return fail("bad delta"); }
	const dc = comp.dcPred + diff;
	comp.dcPred = dc;
	if (!mul2shortsValid(dc, j.dequant[dq])) { return fail("can't merge dc and ac"); }
	data[dataOff] = wrapShort(dc * j.dequant[dq]);

	let k: int32 = 1;
	do {
		if (j.codeBits < 16) { j.growBuffer(); }
		const c = ((j.codeBuffer >> ((32 - FAST_BITS) as uint32)) & ((FAST_SIZE - 1) as uint32)) as int32;
		let r = j.fastAc[fac + c];
		if (r != 0) {
			k += (r >> 4) & 15;
			const s = r & 15;
			if (s > j.codeBits) { return fail("bad huffman code"); }
			j.codeBuffer = j.codeBuffer << (s as uint32);
			j.codeBits -= s;
			const zig = DEZIGZAG[k];
			k++;
			data[dataOff + zig] = wrapShort((r >> 8) * j.dequant[dq + zig]);
		} else {
			const rs = j.huffDecode(hac);
			if (rs < 0) { return fail("bad huffman code"); }
			const s = rs & 15;
			r = rs >> 4;
			if (s == 0) {
				if (rs != 0xF0) { break; }
				k += 16;
			} else {
				k += r;
				const zig = DEZIGZAG[k];
				k++;
				data[dataOff + zig] = wrapShort(j.extendReceive(s) * j.dequant[dq + zig]);
			}
		}
	} while (k < 64);
	return true;
}

function decodeBlockProgDc(
	this j: JpegDecoder, data: int32[], dataOff: int32, hdc: Huffman, b: int32,
): boolean {
	if (j.specEnd != 0) { return fail("can't merge dc and ac"); }

	if (j.codeBits < 16) { j.growBuffer(); }

	if (j.succHigh == 0) {
		for (let i: int32 = 0; i < 64; i++) { data[dataOff + i] = 0; }
		const t = j.huffDecode(hdc);
		if (t < 0 || t > 15) { return fail("can't merge dc and ac"); }
		const diff = t != 0 ? j.extendReceive(t) : 0;

		const comp = j.comps[b];
		if (!addintsValid(comp.dcPred, diff)) { return fail("bad delta"); }
		const dc = comp.dcPred + diff;
		comp.dcPred = dc;
		if (!mul2shortsValid(dc, 1 << j.succLow)) { return fail("can't merge dc and ac"); }
		data[dataOff] = wrapShort(dc * (1 << j.succLow));
	} else {
		if (j.getBit()) { data[dataOff] = wrapShort(data[dataOff] + (1 << j.succLow)); }
	}
	return true;
}

// Adds or subtracts one refinement bit to a nonzero coefficient that does not yet carry it.
function refine(this j: JpegDecoder, data: int32[], at: int32, bit: int32): void {
	if (j.getBit()) {
		if ((data[at] & bit) == 0) {
			if (data[at] > 0) {
				data[at] = wrapShort(data[at] + bit);
			} else {
				data[at] = wrapShort(data[at] - bit);
			}
		}
	}
}

function decodeBlockProgAc(
	this j: JpegDecoder, data: int32[], dataOff: int32, hac: Huffman, fac: int32,
): boolean {
	if (j.specStart == 0) { return fail("can't merge dc and ac"); }

	if (j.succHigh == 0) {
		const shift = j.succLow;

		if (j.eobRun != 0) {
			j.eobRun--;
			return true;
		}

		let k = j.specStart;
		do {
			if (j.codeBits < 16) { j.growBuffer(); }
			const c = ((j.codeBuffer >> ((32 - FAST_BITS) as uint32)) & ((FAST_SIZE - 1) as uint32)) as int32;
			let r = j.fastAc[fac + c];
			if (r != 0) {
				k += (r >> 4) & 15;
				const s = r & 15;
				if (s > j.codeBits) { return fail("bad huffman code"); }
				j.codeBuffer = j.codeBuffer << (s as uint32);
				j.codeBits -= s;
				const zig = DEZIGZAG[k];
				k++;
				data[dataOff + zig] = wrapShort((r >> 8) * (1 << shift));
			} else {
				const rs = j.huffDecode(hac);
				if (rs < 0) { return fail("bad huffman code"); }
				const s = rs & 15;
				r = rs >> 4;
				if (s == 0) {
					if (r < 15) {
						j.eobRun = 1 << r;
						if (r != 0) { j.eobRun += j.getBits(r); }
						j.eobRun--;
						break;
					}
					k += 16;
				} else {
					k += r;
					const zig = DEZIGZAG[k];
					k++;
					data[dataOff + zig] = wrapShort(j.extendReceive(s) * (1 << shift));
				}
			}
		} while (k <= j.specEnd);
	} else {
		const bit = 1 << j.succLow;

		if (j.eobRun != 0) {
			j.eobRun--;
			for (let k = j.specStart; k <= j.specEnd; k++) {
				const at = dataOff + DEZIGZAG[k];
				if (data[at] != 0) { j.refine(data, at, bit); }
			}
		} else {
			let k = j.specStart;
			do {
				let s: int32;
				let r: int32;
				const rs = j.huffDecode(hac);
				if (rs < 0) { return fail("bad huffman code"); }
				s = rs & 15;
				r = rs >> 4;
				if (s == 0) {
					if (r < 15) {
						j.eobRun = (1 << r) - 1;
						if (r != 0) { j.eobRun += j.getBits(r); }
						r = 64;
					}
				} else {
					if (s != 1) { return fail("bad huffman code"); }
					if (j.getBit()) {
						s = bit;
					} else {
						s = -bit;
					}
				}

				while (k <= j.specEnd) {
					const at = dataOff + DEZIGZAG[k];
					k++;
					if (data[at] != 0) {
						j.refine(data, at, bit);
					} else {
						if (r == 0) {
							data[at] = wrapShort(s);
							break;
						}
						r--;
					}
				}
			} while (k <= j.specEnd);
		}
	}
	return true;
}

// Arithmetic shift right of a wrapped int.
function sar(x: uint32, n: int32): uint32 {
	return (x >> (n as uint32)) | (((x >> 31) * 0xFFFFFFFF) << ((32 - n) as uint32));
}

// take a -128..127 value and clamp it to 0..255; x is an int in two's complement.
function clamp(x: uint32): int32 {
	if (x > 255) { return (x >> 31) != 0 ? 0 : 255; }
	return x as int32;
}

// derived from jidctint -- DCT_ISLOW. Fills r with x0 x1 x2 x3 t0 t1 t2 t3.
function idct1d(
	r: uint32[], s0: uint32, s1: uint32, s2: uint32, s3: uint32, s4: uint32, s5: uint32,
	s6: uint32, s7: uint32,
): void {
	let p2 = s2;
	let p3 = s6;
	let p1 = (p2 + p3) * 2217;
	let t2 = p1 - p3 * 7567;
	let t3 = p1 + p2 * 3135;
	p2 = s0;
	p3 = s4;
	let t0 = (p2 + p3) * 4096;
	let t1 = (p2 - p3) * 4096;
	r[0] = t0 + t3;
	r[3] = t0 - t3;
	r[1] = t1 + t2;
	r[2] = t1 - t2;
	t0 = s7;
	t1 = s5;
	t2 = s3;
	t3 = s1;
	p3 = t0 + t2;
	let p4 = t1 + t3;
	p1 = t0 + t3;
	p2 = t1 + t2;
	const p5 = (p3 + p4) * 4816;
	t0 = t0 * 1223;
	t1 = t1 * 8410;
	t2 = t2 * 12586;
	t3 = t3 * 6149;
	p1 = p5 - p1 * 3685;
	p2 = p5 - p2 * 10497;
	p3 = 0 - p3 * 8034;
	p4 = 0 - p4 * 1597;
	t3 += p1 + p4;
	t2 += p2 + p3;
	t1 += p2 + p4;
	t0 += p1 + p3;
	r[4] = t0;
	r[5] = t1;
	r[6] = t2;
	r[7] = t3;
}

function idctBlock(
	this j: JpegDecoder, out: uint8[], outOff: int32, outStride: int32, data: int32[], dataOff: int32,
): void {
	const val = j.idctVal;
	const r = j.idctOut;
	for (let i: int32 = 0; i < 8; i++) {
		const d = dataOff + i;
		if (data[d + 8] == 0 && data[d + 16] == 0 && data[d + 24] == 0 && data[d + 32] == 0
			&& data[d + 40] == 0 && data[d + 48] == 0 && data[d + 56] == 0) {
			const dcterm = (data[d] * 4) as uint32;
			for (let n: int32 = 0; n < 64; n += 8) { val[i + n] = dcterm; }
		} else {
			idct1d(
				r, data[d] as uint32, data[d + 8] as uint32, data[d + 16] as uint32,
				data[d + 24] as uint32, data[d + 32] as uint32, data[d + 40] as uint32,
				data[d + 48] as uint32, data[d + 56] as uint32,
			);
			const x0 = r[0] + 512;
			const x1 = r[1] + 512;
			const x2 = r[2] + 512;
			const x3 = r[3] + 512;
			val[i] = sar(x0 + r[7], 10);
			val[i + 56] = sar(x0 - r[7], 10);
			val[i + 8] = sar(x1 + r[6], 10);
			val[i + 48] = sar(x1 - r[6], 10);
			val[i + 16] = sar(x2 + r[5], 10);
			val[i + 40] = sar(x2 - r[5], 10);
			val[i + 24] = sar(x3 + r[4], 10);
			val[i + 32] = sar(x3 - r[4], 10);
		}
	}

	for (let i: int32 = 0; i < 8; i++) {
		const v = i * 8;
		const o = outOff + i * outStride;
		idct1d(r, val[v], val[v + 1], val[v + 2], val[v + 3], val[v + 4], val[v + 5], val[v + 6], val[v + 7]);
		const bias: uint32 = 65536 + (128 << 17);
		const x0 = r[0] + bias;
		const x1 = r[1] + bias;
		const x2 = r[2] + bias;
		const x3 = r[3] + bias;
		out[o] = clamp(sar(x0 + r[7], 17)) as uint8;
		out[o + 7] = clamp(sar(x0 - r[7], 17)) as uint8;
		out[o + 1] = clamp(sar(x1 + r[6], 17)) as uint8;
		out[o + 6] = clamp(sar(x1 - r[6], 17)) as uint8;
		out[o + 2] = clamp(sar(x2 + r[5], 17)) as uint8;
		out[o + 5] = clamp(sar(x2 - r[5], 17)) as uint8;
		out[o + 3] = clamp(sar(x3 + r[4], 17)) as uint8;
		out[o + 4] = clamp(sar(x3 - r[4], 17)) as uint8;
	}
}

function getMarker(this j: JpegDecoder): int32 {
	if (j.marker != MARKER_NONE) {
		const x = j.marker;
		j.marker = MARKER_NONE;
		return x;
	}
	let x = j.get8();
	if (x != 0xFF) { return MARKER_NONE; }
	while (x == 0xFF) { x = j.get8(); }
	return x;
}

function isRestart(x: int32): boolean {
	return x >= 0xD0 && x <= 0xD7;
}

// After a restart interval, reset the entropy decoder and the dc prediction.
function jpegReset(this j: JpegDecoder): void {
	j.codeBits = 0;
	j.codeBuffer = 0;
	j.nomore = false;
	j.comps[0].dcPred = 0;
	j.comps[1].dcPred = 0;
	j.comps[2].dcPred = 0;
	j.comps[3].dcPred = 0;
	j.marker = MARKER_NONE;
	j.todo = j.restartInterval != 0 ? j.restartInterval : 0x7FFFFFFF;
	j.eobRun = 0;
}

// Counts one MCU down; true when decoding stops here, the interval's end not being a restart.
function mcuDone(this j: JpegDecoder): boolean {
	j.todo--;
	if (j.todo <= 0) {
		if (j.codeBits < 24) { j.growBuffer(); }
		if (!isRestart(j.marker)) { return true; }
		j.jpegReset();
	}
	return false;
}

function parseEntropyCodedData(this j: JpegDecoder): boolean {
	j.jpegReset();
	if (!j.progressive) {
		if (j.scanN == 1) {
			const data = j.block;
			const n = j.order[0];
			const comp = j.comps[n];
			const w = (comp.x + 7) >> 3;
			const h = (comp.y + 7) >> 3;
			for (let y: int32 = 0; y < h; y++) {
				for (let x: int32 = 0; x < w; x++) {
					const ha = comp.ha;
					if (!j.decodeBlock(data, 0, j.huffDc[comp.hd], j.huffAc[ha], ha * FAST_SIZE, n, comp.tq * 64)) {
						return false;
					}
					j.idctBlock(comp.data, comp.w2 * y * 8 + x * 8, comp.w2, data, 0);
					if (j.mcuDone()) { return true; }
				}
			}
			return true;
		} else {
			const data = j.block;
			for (let y: int32 = 0; y < j.imgMcuY; y++) {
				for (let x: int32 = 0; x < j.imgMcuX; x++) {
					for (let k: int32 = 0; k < j.scanN; k++) {
						const n = j.order[k];
						const comp = j.comps[n];
						for (let cy: int32 = 0; cy < comp.v; cy++) {
							for (let cx: int32 = 0; cx < comp.h; cx++) {
								const x2 = (x * comp.h + cx) * 8;
								const y2 = (y * comp.v + cy) * 8;
								const ha = comp.ha;
								if (!j.decodeBlock(
									data, 0, j.huffDc[comp.hd], j.huffAc[ha], ha * FAST_SIZE, n, comp.tq * 64,
								)) {
									return false;
								}
								j.idctBlock(comp.data, comp.w2 * y2 + x2, comp.w2, data, 0);
							}
						}
					}
					if (j.mcuDone()) { return true; }
				}
			}
			return true;
		}
	} else {
		if (j.scanN == 1) {
			const n = j.order[0];
			const comp = j.comps[n];
			const w = (comp.x + 7) >> 3;
			const h = (comp.y + 7) >> 3;
			for (let y: int32 = 0; y < h; y++) {
				for (let x: int32 = 0; x < w; x++) {
					const at = 64 * (x + y * comp.coeffW);
					if (j.specStart == 0) {
						if (!j.decodeBlockProgDc(comp.coeff, at, j.huffDc[comp.hd], n)) { return false; }
					} else {
						const ha = comp.ha;
						if (!j.decodeBlockProgAc(comp.coeff, at, j.huffAc[ha], ha * FAST_SIZE)) {
							return false;
						}
					}
					if (j.mcuDone()) { return true; }
				}
			}
			return true;
		} else {
			for (let y: int32 = 0; y < j.imgMcuY; y++) {
				for (let x: int32 = 0; x < j.imgMcuX; x++) {
					for (let k: int32 = 0; k < j.scanN; k++) {
						const n = j.order[k];
						const comp = j.comps[n];
						for (let cy: int32 = 0; cy < comp.v; cy++) {
							for (let cx: int32 = 0; cx < comp.h; cx++) {
								const x2 = x * comp.h + cx;
								const y2 = y * comp.v + cy;
								const at = 64 * (x2 + y2 * comp.coeffW);
								if (!j.decodeBlockProgDc(comp.coeff, at, j.huffDc[comp.hd], n)) { return false; }
							}
						}
					}
					if (j.mcuDone()) { return true; }
				}
			}
			return true;
		}
	}
}

// The progressive coefficients, dequantized and inverse transformed.
function jpegFinish(this j: JpegDecoder): void {
	if (!j.progressive) { return; }
	for (let n: int32 = 0; n < j.imgN; n++) {
		const comp = j.comps[n];
		const w = (comp.x + 7) >> 3;
		const h = (comp.y + 7) >> 3;
		for (let y: int32 = 0; y < h; y++) {
			for (let x: int32 = 0; x < w; x++) {
				const at = 64 * (x + y * comp.coeffW);
				for (let i: int32 = 0; i < 64; i++) {
					comp.coeff[at + i] = wrapShort(comp.coeff[at + i] * j.dequant[comp.tq * 64 + i]);
				}
				j.idctBlock(comp.data, comp.w2 * y * 8 + x * 8, comp.w2, comp.coeff, at);
			}
		}
	}
}

function markerDri(this j: JpegDecoder): boolean {
	if (j.get16be() != 4) { return fail("bad DRI len"); }
	j.restartInterval = j.get16be();
	return true;
}

function markerDqt(this j: JpegDecoder): boolean {
	let l = j.get16be() - 2;
	while (l > 0) {
		const q = j.get8();
		const p = q >> 4;
		const sixteen = p != 0;
		const t = q & 15;
		if (p != 0 && p != 1) { return fail("bad DQT type"); }
		if (t > 3) { return fail("bad DQT table"); }
		for (let i: int32 = 0; i < 64; i++) {
			j.dequant[t * 64 + DEZIGZAG[i]] = (sixteen ? j.get16be() : j.get8()) & 0xFFFF;
		}
		l -= sixteen ? 129 : 65;
	}
	return l == 0;
}

function markerDht(this j: JpegDecoder): boolean {
	let l = j.get16be() - 2;
	while (l > 0) {
		const sizes: int32[] = zeros32(16);
		let n: int32 = 0;
		const q = j.get8();
		const tc = q >> 4;
		const th = q & 15;
		if (tc > 1 || th > 3) { return fail("bad DHT header"); }
		for (let i: int32 = 0; i < 16; i++) {
			sizes[i] = j.get8();
			n += sizes[i];
		}
		if (n > 256) { return fail("bad DHT header"); }
		l -= 17;
		const h = tc == 0 ? j.huffDc[th] : j.huffAc[th];
		if (!buildHuffman(h, sizes)) { return false; }
		for (let i: int32 = 0; i < n; i++) { h.values[i] = j.get8() as uint8; }
		if (tc != 0) { buildFastAc(j.fastAc, th * FAST_SIZE, h); }
		l -= n;
	}
	return l == 0;
}

function markerApp(this j: JpegDecoder, m: int32): boolean {
	if ((m >= 0xE0 && m <= 0xEF) || m == 0xFE) {
		let l = j.get16be();
		if (l < 2) { return m == 0xFE ? fail("bad COM len") : fail("bad APP len"); }
		l -= 2;

		if (m == 0xE0 && l >= 5) {
			const tag: int32[] = [74, 70, 73, 70, 0];
			let ok = true;
			for (let i: int32 = 0; i < 5; i++) {
				if (j.get8() != tag[i]) { ok = false; }
			}
			l -= 5;
			if (ok) { j.jfif = true; }
		} else if (m == 0xEE && l >= 12) {
			const tag: int32[] = [65, 100, 111, 98, 101, 0];
			let ok = true;
			for (let i: int32 = 0; i < 6; i++) {
				if (j.get8() != tag[i]) { ok = false; }
			}
			l -= 6;
			if (ok) {
				j.get8();
				j.get16be();
				j.get16be();
				j.app14ColorTransform = j.get8();
				l -= 6;
			}
		}

		j.skip(l);
		return true;
	}
	return fail("unknown marker");
}

function processMarker(this j: JpegDecoder, m: int32): boolean {
	return match (m) {
		0xFF => fail("expected marker"),
		0xDD => j.markerDri(),
		0xDB => j.markerDqt(),
		0xC4 => j.markerDht(),
		_ => j.markerApp(m),
	};
}

// After we see SOS.
function processScanHeader(this j: JpegDecoder): boolean {
	const ls = j.get16be();
	j.scanN = j.get8();
	if (j.scanN < 1 || j.scanN > 4 || j.scanN > j.imgN) { return fail("bad SOS component count"); }
	if (ls != 6 + 2 * j.scanN) { return fail("bad SOS len"); }
	for (let i: int32 = 0; i < j.scanN; i++) {
		const id = j.get8();
		const q = j.get8();
		let which: int32 = 0;
		while (which < j.imgN) {
			if (j.comps[which].id == id) { break; }
			which++;
		}
		if (which == j.imgN) { return false; }
		j.comps[which].hd = q >> 4;
		if (j.comps[which].hd > 3) { return fail("bad DC huff"); }
		j.comps[which].ha = q & 15;
		if (j.comps[which].ha > 3) { return fail("bad AC huff"); }
		j.order[i] = which;
	}

	j.specStart = j.get8();
	j.specEnd = j.get8();
	const aa = j.get8();
	j.succHigh = aa >> 4;
	j.succLow = aa & 15;
	if (j.progressive) {
		if (j.specStart > 63 || j.specEnd > 63 || j.specStart > j.specEnd || j.succHigh > 13
			|| j.succLow > 13) {
			return fail("bad SOS");
		}
	} else {
		if (j.specStart != 0) { return fail("bad SOS"); }
		if (j.succHigh != 0 || j.succLow != 0) { return fail("bad SOS"); }
		j.specEnd = 63;
	}
	return true;
}

function processFrameHeader(this j: JpegDecoder, scan: Scan): boolean {
	let hMax: int32 = 1;
	let vMax: int32 = 1;
	const lf = j.get16be();
	if (lf < 11) { return fail("bad SOF len"); }
	const p = j.get8();
	if (p != 8) { return fail("only 8-bit"); }
	j.imgY = j.get16be();
	if (j.imgY == 0) { return fail("no header height"); }
	j.imgX = j.get16be();
	if (j.imgX == 0) { return fail("0 width"); }
	if (j.imgY > j.maxSide) { return fail("too large"); }
	if (j.imgX > j.maxSide) { return fail("too large"); }
	const c = j.get8();
	if (c != 3 && c != 1 && c != 4) { return fail("bad component count"); }
	j.imgN = c;

	if (lf != 8 + 3 * j.imgN) { return fail("bad SOF len"); }

	const rgbTag: int32[] = [82, 71, 66];
	j.rgb = 0;
	for (let i: int32 = 0; i < j.imgN; i++) {
		const comp = j.comps[i];
		comp.id = j.get8();
		if (j.imgN == 3 && comp.id == rgbTag[i]) { j.rgb++; }
		const q = j.get8();
		comp.h = q >> 4;
		if (comp.h == 0 || comp.h > 4) { return fail("bad H"); }
		comp.v = q & 15;
		if (comp.v == 0 || comp.v > 4) { return fail("bad V"); }
		comp.tq = j.get8();
		if (comp.tq > 3) { return fail("bad TQ"); }
	}

	if (scan != Scan.Load) { return true; }

	if (!mad3Valid(j.imgX, j.imgY, j.imgN, 0)) { return fail("too large"); }

	for (let i: int32 = 0; i < j.imgN; i++) {
		if (j.comps[i].h > hMax) { hMax = j.comps[i].h; }
		if (j.comps[i].v > vMax) { vMax = j.comps[i].v; }
	}

	for (let i: int32 = 0; i < j.imgN; i++) {
		if (hMax % j.comps[i].h != 0) { return fail("bad H"); }
		if (vMax % j.comps[i].v != 0) { return fail("bad V"); }
	}

	j.imgHMax = hMax;
	j.imgVMax = vMax;
	j.imgMcuW = hMax * 8;
	j.imgMcuH = vMax * 8;
	j.imgMcuX = (j.imgX + j.imgMcuW - 1) / j.imgMcuW;
	j.imgMcuY = (j.imgY + j.imgMcuH - 1) / j.imgMcuH;

	for (let i: int32 = 0; i < j.imgN; i++) {
		const comp = j.comps[i];
		comp.x = (j.imgX * comp.h + hMax - 1) / hMax;
		comp.y = (j.imgY * comp.v + vMax - 1) / vMax;
		comp.w2 = j.imgMcuX * comp.h * 8;
		comp.h2 = j.imgMcuY * comp.v * 8;
		if (!mad2Valid(comp.w2, comp.h2, 15)) { return fail("outofmem"); }
		comp.data = zeros8(comp.w2 * comp.h2);
		if (j.progressive) {
			comp.coeffW = comp.w2 / 8;
			comp.coeffH = comp.h2 / 8;
			if (!mad3Valid(comp.w2, comp.h2, 2, 15)) { return fail("outofmem"); }
			comp.coeff = zeros32(comp.w2 * comp.h2);
		}
	}
	return true;
}

function decodeJpegHeader(this j: JpegDecoder, scan: Scan): boolean {
	j.jfif = false;
	j.app14ColorTransform = -1;
	j.marker = MARKER_NONE;
	let m = j.getMarker();
	if (m != 0xD8) { return fail("no SOI"); }
	if (scan == Scan.Type) { return true; }
	m = j.getMarker();
	while (!(m == 0xC0 || m == 0xC1 || m == 0xC2)) {
		if (!j.processMarker(m)) { return false; }
		m = j.getMarker();
		while (m == MARKER_NONE) {
			if (j.atEof()) { return fail("no SOF"); }
			m = j.getMarker();
		}
	}
	j.progressive = m == 0xC2;
	if (!j.processFrameHeader(scan)) { return false; }
	return true;
}

function skipJunkAtEnd(this j: JpegDecoder): int32 {
	while (!j.atEof()) {
		let x = j.get8();
		while (x == 0xFF) {
			if (j.atEof()) { return MARKER_NONE; }
			x = j.get8();
			if (x != 0x00 && x != 0xFF) { return x; }
		}
	}
	return MARKER_NONE;
}

// Decode the image to YCbCr.
function decodeJpegImage(this j: JpegDecoder): boolean {
	j.restartInterval = 0;
	if (!j.decodeJpegHeader(Scan.Load)) { return false; }
	let m = j.getMarker();
	while (m != 0xD9) {
		if (m == 0xDA) {
			if (!j.processScanHeader()) { return false; }
			if (!j.parseEntropyCodedData()) { return false; }
			if (j.marker == MARKER_NONE) { j.marker = j.skipJunkAtEnd(); }
			m = j.getMarker();
			if (isRestart(m)) { m = j.getMarker(); }
		} else if (m == 0xDC) {
			const ld = j.get16be();
			const nl = j.get16be();
			if (ld != 4) { return fail("bad DNL len"); }
			if (nl != j.imgY) { return fail("bad DNL height"); }
			m = j.getMarker();
		} else {
			if (!j.processMarker(m)) { return true; }
			m = j.getMarker();
		}
	}
	j.jpegFinish();
	return true;
}

function div4(x: int32): uint8 {
	return (x >> 2) as uint8;
}

function div16(x: int32): uint8 {
	return (x >> 4) as uint8;
}

function resampleV2(out: uint8[], near: uint8[], nearOff: int32, far: uint8[], farOff: int32, w: int32): void {
	for (let i: int32 = 0; i < w; i++) {
		out[i] = div4(3 * (near[nearOff + i] as int32) + (far[farOff + i] as int32) + 2);
	}
}

function resampleH2(out: uint8[], input: uint8[], inOff: int32, w: int32): void {
	if (w == 1) {
		out[0] = input[inOff];
		out[1] = input[inOff];
		return;
	}
	out[0] = input[inOff];
	out[1] = div4((input[inOff] as int32) * 3 + (input[inOff + 1] as int32) + 2);
	let i: int32 = 0;
	for (i = 1; i < w - 1; i++) {
		const n = 3 * (input[inOff + i] as int32) + 2;
		out[i * 2] = div4(n + (input[inOff + i - 1] as int32));
		out[i * 2 + 1] = div4(n + (input[inOff + i + 1] as int32));
	}
	out[i * 2] = div4((input[inOff + w - 2] as int32) * 3 + (input[inOff + w - 1] as int32) + 2);
	out[i * 2 + 1] = input[inOff + w - 1];
}

function resampleHv2(out: uint8[], near: uint8[], nearOff: int32, far: uint8[], farOff: int32, w: int32): void {
	if (w == 1) {
		const value = div4(3 * (near[nearOff] as int32) + (far[farOff] as int32) + 2);
		out[0] = value;
		out[1] = value;
		return;
	}
	let t0: int32;
	let t1 = 3 * (near[nearOff] as int32) + (far[farOff] as int32);
	out[0] = div4(t1 + 2);
	for (let i: int32 = 1; i < w; i++) {
		t0 = t1;
		t1 = 3 * (near[nearOff + i] as int32) + (far[farOff + i] as int32);
		out[i * 2 - 1] = div16(3 * t0 + t1 + 8);
		out[i * 2] = div16(3 * t1 + t0 + 8);
	}
	out[w * 2 - 1] = div4(t1 + 2);
}

// Nearest neighbour.
function resampleGeneric(out: uint8[], input: uint8[], inOff: int32, w: int32, hs: int32): void {
	for (let i: int32 = 0; i < w; i++) {
		for (let n: int32 = 0; n < hs; n++) { out[i * hs + n] = input[inOff + i]; }
	}
}

// A reduced-precision YCbCr-to-RGB, so the SIMD and scalar kernels agree.
function ycbcrToRgbRow(
	out: uint8[], outOff: int32, y: Plane, cb: Plane, cr: Plane, count: int32, step: int32,
): void {
	let o: int32 = outOff;
	for (let i: int32 = 0; i < count; i++) {
		const yFixed = ((y.buf[y.off + i] as int32) << 20) + (1 << 19);
		const crv = (cr.buf[cr.off + i] as int32) - 128;
		const cbv = (cb.buf[cb.off + i] as int32) - 128;
		let r = yFixed + crv * 1470208;
		let g = yFixed + (crv * -748800) + ((cbv * -360960) & -65536);
		let b = yFixed + cbv * 1858048;
		r = r >> 20;
		g = g >> 20;
		b = b >> 20;
		if (r < 0) { r = 0; } else if (r > 255) { r = 255; }
		if (g < 0) { g = 0; } else if (g > 255) { g = 255; }
		if (b < 0) { b = 0; } else if (b > 255) { b = 255; }
		out[o] = r as uint8;
		out[o + 1] = g as uint8;
		out[o + 2] = b as uint8;
		if (o + 3 < out.length) { out[o + 3] = 255; }
		o += step;
	}
}

// Fast 0..255 * 0..255 => 0..255 rounded multiplication.
function blinn8x8(x: int32, y: int32): int32 {
	const t = x * y + 128;
	return (t + (t >> 8)) >> 8;
}

function computeY(r: int32, g: int32, b: int32): int32 {
	return ((r * 77) + (g * 150) + (29 * b)) >> 8;
}

function pickResampler(hs: int32, vs: int32): Resampler {
	if (hs == 1 && vs == 1) { return Resampler.One; }
	if (hs == 1 && vs == 2) { return Resampler.V2; }
	if (hs == 2 && vs == 1) { return Resampler.H2; }
	if (hs == 2 && vs == 2) { return Resampler.Hv2; }
	return Resampler.Generic;
}

// One row of component k, resampled to the image's width; plane says where it is.
function resampleRow(this j: JpegDecoder, k: int32, r: Resample, plane: Plane): void {
	const comp = j.comps[k];
	const yBot = r.ystep >= (r.vs >> 1);
	const nearOff = yBot ? r.line1 : r.line0;
	const farOff = yBot ? r.line0 : r.line1;
	plane.buf = comp.linebuf;
	plane.off = 0;
	match (r.kind) {
		Resampler.One => {
			plane.buf = comp.data;
			plane.off = nearOff;
		},
		Resampler.V2 => resampleV2(comp.linebuf, comp.data, nearOff, comp.data, farOff, r.wLores),
		Resampler.H2 => resampleH2(comp.linebuf, comp.data, nearOff, r.wLores),
		Resampler.Hv2 => resampleHv2(comp.linebuf, comp.data, nearOff, comp.data, farOff, r.wLores),
		Resampler.Generic => resampleGeneric(comp.linebuf, comp.data, nearOff, r.wLores, r.hs),
	}
	r.ystep++;
	if (r.ystep >= r.vs) {
		r.ystep = 0;
		r.line0 = r.line1;
		r.ypos++;
		if (r.ypos < comp.y) { r.line1 += comp.w2; }
	}
}

function loadJpegImage(this j: JpegDecoder, reqComp: int32): Result<JpegImage, string> {
	j.imgN = 0;

	if (reqComp < 0 || reqComp > 4) {
		fail("bad req_comp");
		return Result.err(failureReason ?? "");
	}

	if (!j.decodeJpegImage()) { return Result.err(failureReason ?? ""); }

	const n = reqComp != 0 ? reqComp : j.imgN >= 3 ? 3 : 1;

	const isRgb = j.imgN == 3 && (j.rgb == 3 || (j.app14ColorTransform == 0 && !j.jfif));

	const decodeN = j.imgN == 3 && n < 3 && !isRgb ? 1 : j.imgN;

	if (decodeN <= 0) { return Result.err(failureReason ?? ""); }

	const res: Resample[] = [new Resample(), new Resample(), new Resample(), new Resample()];
	const coutput: Plane[] = [new Plane(), new Plane(), new Plane(), new Plane()];

	for (let k: int32 = 0; k < decodeN; k++) {
		const comp = j.comps[k];
		const r = res[k];
		comp.linebuf = zeros8(j.imgX + 3);
		r.hs = j.imgHMax / comp.h;
		r.vs = j.imgVMax / comp.v;
		r.ystep = r.vs >> 1;
		r.wLores = (j.imgX + r.hs - 1) / r.hs;
		r.ypos = 0;
		r.line0 = 0;
		r.line1 = 0;
		r.kind = pickResampler(r.hs, r.vs);
	}

	if (!mad3Valid(n, j.imgX, j.imgY, 1)) {
		fail("outofmem");
		return Result.err(failureReason ?? "");
	}
	let output: uint8[] = zeros8(n * j.imgX * j.imgY);

	for (let row: int32 = 0; row < j.imgY; row++) {
		let o: int32 = n * j.imgX * row;
		for (let k: int32 = 0; k < decodeN; k++) { j.resampleRow(k, res[k], coutput[k]); }
		if (n >= 3) {
			const y = coutput[0];
			if (j.imgN == 3) {
				if (isRgb) {
					for (let i: int32 = 0; i < j.imgX; i++) {
						output[o] = y.buf[y.off + i];
						output[o + 1] = coutput[1].buf[coutput[1].off + i];
						output[o + 2] = coutput[2].buf[coutput[2].off + i];
						if (o + 3 < output.length) { output[o + 3] = 255; }
						o += n;
					}
				} else {
					ycbcrToRgbRow(output, o, y, coutput[1], coutput[2], j.imgX, n);
				}
			} else if (j.imgN == 4) {
				if (j.app14ColorTransform == 0) {
					for (let i: int32 = 0; i < j.imgX; i++) {
						const m = coutput[3].buf[coutput[3].off + i] as int32;
						output[o] = blinn8x8(coutput[0].buf[coutput[0].off + i] as int32, m) as uint8;
						output[o + 1] = blinn8x8(coutput[1].buf[coutput[1].off + i] as int32, m) as uint8;
						output[o + 2] = blinn8x8(coutput[2].buf[coutput[2].off + i] as int32, m) as uint8;
						if (o + 3 < output.length) { output[o + 3] = 255; }
						o += n;
					}
				} else if (j.app14ColorTransform == 2) {
					ycbcrToRgbRow(output, o, y, coutput[1], coutput[2], j.imgX, n);
					for (let i: int32 = 0; i < j.imgX; i++) {
						const m = coutput[3].buf[coutput[3].off + i] as int32;
						output[o] = blinn8x8(255 - (output[o] as int32), m) as uint8;
						output[o + 1] = blinn8x8(255 - (output[o + 1] as int32), m) as uint8;
						output[o + 2] = blinn8x8(255 - (output[o + 2] as int32), m) as uint8;
						o += n;
					}
				} else {
					ycbcrToRgbRow(output, o, y, coutput[1], coutput[2], j.imgX, n);
				}
			} else {
				for (let i: int32 = 0; i < j.imgX; i++) {
					const value = y.buf[y.off + i];
					output[o] = value;
					output[o + 1] = value;
					output[o + 2] = value;
					if (o + 3 < output.length) { output[o + 3] = 255; }
					o += n;
				}
			}
		} else {
			if (isRgb) {
				if (n == 1) {
					for (let i: int32 = 0; i < j.imgX; i++) {
						output[o] = computeY(
							coutput[0].buf[coutput[0].off + i] as int32,
							coutput[1].buf[coutput[1].off + i] as int32,
							coutput[2].buf[coutput[2].off + i] as int32,
						) as uint8;
						o++;
					}
				} else {
					for (let i: int32 = 0; i < j.imgX; i++) {
						output[o] = computeY(
							coutput[0].buf[coutput[0].off + i] as int32,
							coutput[1].buf[coutput[1].off + i] as int32,
							coutput[2].buf[coutput[2].off + i] as int32,
						) as uint8;
						output[o + 1] = 255;
						o += 2;
					}
				}
			} else if (j.imgN == 4 && j.app14ColorTransform == 0) {
				for (let i: int32 = 0; i < j.imgX; i++) {
					const m = coutput[3].buf[coutput[3].off + i] as int32;
					const r = blinn8x8(coutput[0].buf[coutput[0].off + i] as int32, m);
					const g = blinn8x8(coutput[1].buf[coutput[1].off + i] as int32, m);
					const b = blinn8x8(coutput[2].buf[coutput[2].off + i] as int32, m);
					output[o] = computeY(r, g, b) as uint8;
					if (o + 1 < output.length) { output[o + 1] = 255; }
					o += n;
				}
			} else if (j.imgN == 4 && j.app14ColorTransform == 2) {
				for (let i: int32 = 0; i < j.imgX; i++) {
					output[o] = blinn8x8(
						255 - (coutput[0].buf[coutput[0].off + i] as int32),
						coutput[3].buf[coutput[3].off + i] as int32,
					) as uint8;
					if (o + 1 < output.length) { output[o + 1] = 255; }
					o += n;
				}
			} else {
				const y = coutput[0];
				if (n == 1) {
					for (let i: int32 = 0; i < j.imgX; i++) { output[o + i] = y.buf[y.off + i]; }
				} else {
					for (let i: int32 = 0; i < j.imgX; i++) {
						output[o] = y.buf[y.off + i];
						output[o + 1] = 255;
						o += 2;
					}
				}
			}
		}
	}
	return Result.ok({
		width: j.imgX, height: j.imgY, channels: j.imgN >= 3 ? 3 : 1, pixels: move output,
	});
}

// stbi_load_from_memory for a JPEG: channels is the file's, pixels hold reqComp channels per
// texel (3 or 1 when reqComp is 0). maxSide is STBI_MAX_DIMENSIONS.
export function decodeJpeg(
	bytes: Readonly<Span<uint8>>, reqComp: int32, maxSide: int32,
): Result<JpegImage, string> {
	const j = new JpegDecoder({ bytes: bytes }, maxSide);
	return j.loadJpegImage(reqComp);
}

// stbi_info_from_memory for a JPEG: the header up to the frame header.
export function jpegInfo(bytes: Readonly<Span<uint8>>, maxSide: int32): Result<JpegInfo, string> {
	const j = new JpegDecoder({ bytes: bytes }, maxSide);
	if (!j.decodeJpegHeader(Scan.Header)) { return Result.err(failureReason ?? ""); }
	return Result.ok({ width: j.imgX, height: j.imgY, channels: j.imgN >= 3 ? 3 : 1 });
}
