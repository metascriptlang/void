// Void Asset — the PNG decoder: stb_image.h's PNG path (zlib inflate, chunk reader, filters,
// Adam7, palettes, 1/2/4/8/16-bit depths, tRNS, the req_comp conversion), alike on every target.

import {
	INT_MAX, mad2Valid, mad3Valid, zeros16, zeros32, zeros8,
} from "./stbCommon";

export struct PngImage {
	width: int32;
	height: int32;
	channels: int32;
	pixels: Vec<uint8>;
}

const ZFAST_BITS: int32 = 9;
const ZFAST_MASK: uint32 = 511;
const ZNSYMS: int32 = 288;
const UINT_MAX: int64 = 4294967295;

const CHUNK_CGBI: uint32 = 0x43674249;
const CHUNK_IHDR: uint32 = 0x49484452;
const CHUNK_PLTE: uint32 = 0x504C5445;
const CHUNK_TRNS: uint32 = 0x74524E53;
const CHUNK_IDAT: uint32 = 0x49444154;
const CHUNK_IEND: uint32 = 0x49454E44;

const ZLENGTH_BASE: int32[] = [
	3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115,
	131, 163, 195, 227, 258, 0, 0,
];
const ZLENGTH_EXTRA: int32[] = [
	0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0, 0, 0,
];
const ZDIST_BASE: int32[] = [
	1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537,
	2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577, 0, 0,
];
const ZDIST_EXTRA: int32[] = [
	0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13,
	13,
];
const LENGTH_DEZIGZAG: int32[] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];
const FIRST_ROW_FILTER: int32[] = [0, 1, 0, 5, 1];
const DEPTH_SCALE: int32[] = [0, 0xff, 0x55, 0, 0x11, 0, 0, 0, 0x01];
const XORIG: int32[] = [0, 4, 0, 2, 0, 1, 0];
const YORIG: int32[] = [0, 0, 4, 0, 2, 0, 1];
const XSPC: int32[] = [8, 8, 4, 4, 2, 2, 1];
const YSPC: int32[] = [8, 8, 8, 4, 4, 2, 2];

const FILTER_NONE: int32 = 0;
const FILTER_SUB: int32 = 1;
const FILTER_UP: int32 = 2;
const FILTER_AVG: int32 = 3;
const FILTER_PAETH: int32 = 4;
const FILTER_AVG_FIRST: int32 = 5;

enum Chunk {
	Next,
	Done,
	Failed,
}

let failureReason: string | null = null;

// stbi_failure_reason: set by every failure, never cleared, so a failure that sets none keeps
// the previous one.
export function pngFailureReason(): string | null {
	return failureReason;
}

function fail(reason: string): boolean {
	failureReason = reason;
	return false;
}

function untilNul(text: string): string {
	const end = text.indexOf("\0");
	return end < 0 ? text : text.slice(0, end);
}

function bitReverse(value: int32, bits: int32): int32 {
	let n = value;
	n = ((n & 0xAAAA) >> 1) | ((n & 0x5555) << 1);
	n = ((n & 0xCCCC) >> 2) | ((n & 0x3333) << 2);
	n = ((n & 0xF0F0) >> 4) | ((n & 0x0F0F) << 4);
	n = ((n & 0xFF00) >> 8) | ((n & 0x00FF) << 8);
	return n >> (16 - bits);
}

class ZHuffman {
	fast: uint16[] = zeros16(1 << ZFAST_BITS);
	firstcode: uint16[] = zeros16(16);
	maxcode: int32[] = zeros32(17);
	firstsymbol: uint16[] = zeros16(16);
	size: uint8[] = zeros8(ZNSYMS);
	value: uint16[] = zeros16(ZNSYMS);
}

function buildHuffman(z: ZHuffman, sizelist: uint8[], offset: int32, num: int32): boolean {
	const nextCode: int32[] = zeros32(16);
	const sizes: int32[] = zeros32(17);
	for (let i: int32 = 0; i < (1 << ZFAST_BITS); i++) { z.fast[i] = 0; }
	for (let i: int32 = 0; i < num; i++) { sizes[sizelist[offset + i] as int32]++; }
	sizes[0] = 0;
	for (let i: int32 = 1; i < 16; i++) {
		if (sizes[i] > (1 << i)) { return fail("bad sizes"); }
	}
	let code: int32 = 0;
	let k: int32 = 0;
	for (let i: int32 = 1; i < 16; i++) {
		nextCode[i] = code;
		z.firstcode[i] = (code & 0xFFFF) as uint16;
		z.firstsymbol[i] = k as uint16;
		code = code + sizes[i];
		if (sizes[i] != 0 && code - 1 >= (1 << i)) { return fail("bad codelengths"); }
		z.maxcode[i] = code << (16 - i);
		code = code << 1;
		k += sizes[i];
	}
	z.maxcode[16] = 0x10000;
	for (let i: int32 = 0; i < num; i++) {
		const s = sizelist[offset + i] as int32;
		if (s == 0) { continue; }
		const c = nextCode[s] - (z.firstcode[s] as int32) + (z.firstsymbol[s] as int32);
		const fastValue = ((s << 9) | i) as uint16;
		z.size[c] = s as uint8;
		z.value[c] = i as uint16;
		if (s <= ZFAST_BITS) {
			let j = bitReverse(nextCode[s], s);
			while (j < (1 << ZFAST_BITS)) {
				z.fast[j] = fastValue;
				j += 1 << s;
			}
		}
		nextCode[s]++;
	}
	return true;
}

class ZBuf {
	input: uint8[] = [];
	zbuffer: int32 = 0;
	zbufferEnd: int32 = 0;
	numBits: int32 = 0;
	hitZeofOnce: boolean = false;
	codeBuffer: uint32 = 0;
	zout: uint8[] = [];
	zoutPos: int32 = 0;
	zoutEnd: int32 = 0;
	zLength: ZHuffman = new ZHuffman();
	zDistance: ZHuffman = new ZHuffman();
}

function zeof(this z: ZBuf): boolean {
	return z.zbuffer >= z.zbufferEnd;
}

function zget8(this z: ZBuf): uint8 {
	if (z.zeof()) { return 0; }
	const value = z.input[z.zbuffer];
	z.zbuffer++;
	return value;
}

function fillBits(this z: ZBuf): void {
	while (true) {
		const shift = (z.numBits & 31) as uint32;
		if (z.codeBuffer >= ((1 as uint32) << shift)) {
			z.zbuffer = z.zbufferEnd;
			return;
		}
		z.codeBuffer = z.codeBuffer | ((z.zget8() as uint32) << shift);
		z.numBits += 8;
		if (z.numBits > 24) { return; }
	}
}

function zreceive(this z: ZBuf, n: int32): int32 {
	if (z.numBits < n) { z.fillBits(); }
	const k = z.codeBuffer & (((1 as uint32) << (n as uint32)) - 1);
	z.codeBuffer = z.codeBuffer >> (n as uint32);
	z.numBits -= n;
	return k as int32;
}

function huffmanDecodeSlow(this a: ZBuf, z: ZHuffman): int32 {
	const k = bitReverse((a.codeBuffer & 0xFFFF) as int32, 16);
	let s: int32 = ZFAST_BITS + 1;
	while (k >= z.maxcode[s]) { s++; }
	if (s >= 16) { return -1; }
	const b = (k >> (16 - s)) - (z.firstcode[s] as int32) + (z.firstsymbol[s] as int32);
	if (b < 0 || b >= ZNSYMS) { return -1; }
	if ((z.size[b] as int32) != s) { return -1; }
	a.codeBuffer = a.codeBuffer >> (s as uint32);
	a.numBits -= s;
	return z.value[b] as int32;
}

function huffmanDecode(this a: ZBuf, z: ZHuffman): int32 {
	if (a.numBits < 16) {
		if (a.zeof()) {
			if (!a.hitZeofOnce) {
				a.hitZeofOnce = true;
				a.numBits += 16;
			} else {
				return -1;
			}
		} else {
			a.fillBits();
		}
	}
	const b = z.fast[(a.codeBuffer & ZFAST_MASK) as int32] as int32;
	if (b != 0) {
		const s = b >> 9;
		a.codeBuffer = a.codeBuffer >> (s as uint32);
		a.numBits -= s;
		return b & 511;
	}
	return a.huffmanDecodeSlow(z);
}

function zexpand(this z: ZBuf, n: int32): boolean {
	const cur = z.zoutPos as int64;
	let limit = z.zoutEnd as int64;
	if (UINT_MAX - cur < (n as int64)) { return fail("outofmem"); }
	while (cur + (n as int64) > limit) {
		if (limit > UINT_MAX / 2) { return fail("outofmem"); }
		limit *= 2;
	}
	if (limit > INT_MAX) { return fail("outofmem"); }
	const grown: uint8[] = new Array<uint8>(limit as int32);
	for (let i: int32 = 0; i < z.zoutPos; i++) { grown[i] = z.zout[i]; }
	z.zout = grown;
	z.zoutEnd = limit as int32;
	return true;
}

function parseHuffmanBlock(this a: ZBuf): boolean {
	while (true) {
		let z = a.huffmanDecode(a.zLength);
		if (z < 256) {
			if (z < 0) { return fail("bad huffman code"); }
			if (a.zoutPos >= a.zoutEnd) {
				if (!a.zexpand(1)) { return false; }
			}
			a.zout[a.zoutPos] = z as uint8;
			a.zoutPos++;
		} else {
			if (z == 256) {
				if (a.hitZeofOnce && a.numBits < 16) { return fail("unexpected end"); }
				return true;
			}
			if (z >= 286) { return fail("bad huffman code"); }
			z -= 257;
			let len = ZLENGTH_BASE[z];
			if (ZLENGTH_EXTRA[z] != 0) { len += a.zreceive(ZLENGTH_EXTRA[z]); }
			z = a.huffmanDecode(a.zDistance);
			if (z < 0 || z >= 30) { return fail("bad huffman code"); }
			let dist = ZDIST_BASE[z];
			if (ZDIST_EXTRA[z] != 0) { dist += a.zreceive(ZDIST_EXTRA[z]); }
			if (a.zoutPos < dist) { return fail("bad dist"); }
			if (len > a.zoutEnd - a.zoutPos) {
				if (!a.zexpand(len)) { return false; }
			}
			let from = a.zoutPos - dist;
			for (let i: int32 = 0; i < len; i++) {
				a.zout[a.zoutPos] = a.zout[from];
				a.zoutPos++;
				from++;
			}
		}
	}
}

function computeHuffmanCodes(this a: ZBuf): boolean {
	const hlit = a.zreceive(5) + 257;
	const hdist = a.zreceive(5) + 1;
	const hclen = a.zreceive(4) + 4;
	const ntot = hlit + hdist;
	const codelengthSizes: uint8[] = zeros8(19);
	for (let i: int32 = 0; i < hclen; i++) {
		const s = a.zreceive(3);
		codelengthSizes[LENGTH_DEZIGZAG[i]] = s as uint8;
	}
	const zCodelength = new ZHuffman();
	if (!buildHuffman(zCodelength, codelengthSizes, 0, 19)) { return false; }
	const lencodes: uint8[] = zeros8(286 + 32 + 137);
	let n: int32 = 0;
	while (n < ntot) {
		let c = a.huffmanDecode(zCodelength);
		if (c < 0 || c >= 19) { return fail("bad codelengths"); }
		if (c < 16) {
			lencodes[n] = c as uint8;
			n++;
		} else {
			let fill: uint8 = 0;
			if (c == 16) {
				c = a.zreceive(2) + 3;
				if (n == 0) { return fail("bad codelengths"); }
				fill = lencodes[n - 1];
			} else if (c == 17) {
				c = a.zreceive(3) + 3;
			} else if (c == 18) {
				c = a.zreceive(7) + 11;
			} else {
				return fail("bad codelengths");
			}
			if (ntot - n < c) { return fail("bad codelengths"); }
			for (let i: int32 = 0; i < c; i++) { lencodes[n + i] = fill; }
			n += c;
		}
	}
	if (n != ntot) { return fail("bad codelengths"); }
	if (!buildHuffman(a.zLength, lencodes, 0, hlit)) { return false; }
	if (!buildHuffman(a.zDistance, lencodes, hlit, hdist)) { return false; }
	return true;
}

function parseUncompressedBlock(this a: ZBuf): boolean {
	const header: uint8[] = zeros8(4);
	if ((a.numBits & 7) != 0) { a.zreceive(a.numBits & 7); }
	let k: int32 = 0;
	while (a.numBits > 0) {
		header[k] = (a.codeBuffer & 255) as uint8;
		k++;
		a.codeBuffer = a.codeBuffer >> 8;
		a.numBits -= 8;
	}
	if (a.numBits < 0) { return fail("zlib corrupt"); }
	while (k < 4) {
		header[k] = a.zget8();
		k++;
	}
	const len = (header[1] as int32) * 256 + (header[0] as int32);
	const nlen = (header[3] as int32) * 256 + (header[2] as int32);
	if (nlen != (len ^ 0xffff)) { return fail("zlib corrupt"); }
	if (a.zbuffer + len > a.zbufferEnd) { return fail("read past buffer"); }
	if (a.zoutPos + len > a.zoutEnd) {
		if (!a.zexpand(len)) { return false; }
	}
	for (let i: int32 = 0; i < len; i++) { a.zout[a.zoutPos + i] = a.input[a.zbuffer + i]; }
	a.zbuffer += len;
	a.zoutPos += len;
	return true;
}

function parseZlibHeader(this a: ZBuf): boolean {
	const cmf = a.zget8() as int32;
	const cm = cmf & 15;
	const flg = a.zget8() as int32;
	if (a.zeof()) { return fail("bad zlib header"); }
	if ((cmf * 256 + flg) % 31 != 0) { return fail("bad zlib header"); }
	if ((flg & 32) != 0) { return fail("no preset dict"); }
	if (cm != 8) { return fail("bad compression"); }
	return true;
}

function fixedLengthSizes(): uint8[] {
	const sizes: uint8[] = zeros8(ZNSYMS);
	for (let i: int32 = 0; i < ZNSYMS; i++) {
		sizes[i] = (i <= 143 ? 8 : i <= 255 ? 9 : i <= 279 ? 7 : 8) as uint8;
	}
	return sizes;
}

function fixedDistanceSizes(): uint8[] {
	const sizes: uint8[] = zeros8(32);
	for (let i: int32 = 0; i < 32; i++) { sizes[i] = 5; }
	return sizes;
}

function parseZlib(this a: ZBuf, parseHeader: boolean): boolean {
	if (parseHeader) {
		if (!a.parseZlibHeader()) { return false; }
	}
	a.numBits = 0;
	a.codeBuffer = 0;
	a.hitZeofOnce = false;
	let final: int32 = 0;
	do {
		final = a.zreceive(1);
		const blockType = a.zreceive(2);
		if (blockType == 0) {
			if (!a.parseUncompressedBlock()) { return false; }
		} else if (blockType == 3) {
			return false;
		} else {
			if (blockType == 1) {
				if (!buildHuffman(a.zLength, fixedLengthSizes(), 0, ZNSYMS)) { return false; }
				if (!buildHuffman(a.zDistance, fixedDistanceSizes(), 0, 32)) { return false; }
			} else {
				if (!a.computeHuffmanCodes()) { return false; }
			}
			if (!a.parseHuffmanBlock()) { return false; }
		}
	} while (final == 0);
	return true;
}

struct PngInput {
	bytes: Readonly<Span<uint8>>;
}

class PngDecoder {
	input: PngInput;
	pos: int64 = 0;
	maxSide: int32;
	imgX: int32 = 0;
	imgY: int32 = 0;
	imgN: int32 = 0;
	imgOutN: int32 = 0;
	depth: int32 = 0;
	color: int32 = 0;
	interlace: int32 = 0;
	first: boolean = true;
	isIphone: boolean = false;
	headerOnly: boolean = false;
	palette: uint8[] = zeros8(1024);
	palLen: int32 = 0;
	palImgN: int32 = 0;
	hasTrans: boolean = false;
	tc: uint8[] = zeros8(3);
	tc16: uint16[] = zeros16(3);
	idata: uint8[] = [];
	ioff: int32 = 0;
	expanded: uint8[] = [];
	expandedLen: int32 = 0;
	out: Vec<uint8> = [];
	out16: uint16[] = [];

	constructor(input: PngInput, maxSide: int32) {
		this.input = input;
		this.maxSide = maxSide;
	}
}

function get8(this d: PngDecoder): int32 {
	if (d.pos < (d.input.bytes.length as int64)) {
		const value = d.input.bytes[d.pos as int32] as int32;
		d.pos++;
		return value;
	}
	return 0;
}

function get16be(this d: PngDecoder): int32 {
	const z = d.get8();
	return (z << 8) + d.get8();
}

function get32be(this d: PngDecoder): uint32 {
	const z = d.get16be() as uint32;
	return (z << 16) + (d.get16be() as uint32);
}

function skip(this d: PngDecoder, n: uint32): void {
	if (n == 0) { return; }
	if (n > 0x7FFFFFFF) {
		d.pos = d.input.bytes.length as int64;
		return;
	}
	d.pos += n as int64;
}

function skipCrc(this d: PngDecoder): void {
	d.get32be();
}

function checkPngHeader(this d: PngDecoder): boolean {
	const signature: int32[] = [137, 80, 78, 71, 13, 10, 26, 10];
	for (let i: int32 = 0; i < 8; i++) {
		if (d.get8() != signature[i]) { return fail("bad png sig"); }
	}
	return true;
}

function paeth(a: int32, b: int32, c: int32): int32 {
	const thresh = c * 3 - (a + b);
	const lo = a < b ? a : b;
	const hi = a < b ? b : a;
	const t0 = hi <= thresh ? lo : c;
	return thresh <= lo ? hi : t0;
}

function createPngImageRaw(
	this d: PngDecoder, raw: uint8[], rawStart: int32, rawLen: int64, outN: int32, x: int32,
	y: int32,
): boolean {
	const bytes: int32 = d.depth == 16 ? 2 : 1;
	const imgN = d.imgN;
	const outputBytes = outN * bytes;
	const depth = d.depth;
	let filterBytes = imgN * bytes;
	let width = x;
	if (!mad3Valid(x, y, outputBytes, 0)) { return fail("outofmem"); }
	const pixelCount = x * y * outN;
	if (depth == 16) {
		d.out16 = new Array<uint16>(pixelCount);
	} else {
		d.out = new Array<uint8>(pixelCount);
	}
	if (!mad3Valid(imgN, x, depth, 7)) { return fail("too large"); }
	const imgWidthBytes = (imgN * x * depth + 7) >> 3;
	if (!mad2Valid(imgWidthBytes, y, imgWidthBytes)) { return fail("too large"); }
	const imgLen = ((imgWidthBytes + 1) as int64) * (y as int64);
	if (rawLen < imgLen) { return fail("not enough pixels"); }
	const filterBuf: uint8[] = zeros8(imgWidthBytes * 2);
	if (depth < 8) {
		filterBytes = 1;
		width = imgWidthBytes;
	}
	let rp: int32 = rawStart;
	let allOk = true;
	for (let j: int32 = 0; j < y; j++) {
		const cur: int32 = (j & 1) * imgWidthBytes;
		const prior: int32 = ((j + 1) & 1) * imgWidthBytes;
		const dest: int32 = x * outN * j;
		const nk = width * filterBytes;
		let filter = raw[rp] as int32;
		rp++;
		if (filter > 4) {
			allOk = fail("invalid filter");
			break;
		}
		if (j == 0) { filter = FIRST_ROW_FILTER[filter]; }
		if (filter == FILTER_NONE) {
			for (let k: int32 = 0; k < nk; k++) { filterBuf[cur + k] = raw[rp + k]; }
		} else if (filter == FILTER_SUB) {
			for (let k: int32 = 0; k < filterBytes; k++) { filterBuf[cur + k] = raw[rp + k]; }
			for (let k: int32 = filterBytes; k < nk; k++) {
				filterBuf[cur + k] = (((raw[rp + k] as int32) + (filterBuf[cur + k - filterBytes] as int32)) & 255) as uint8;
			}
		} else if (filter == FILTER_UP) {
			for (let k: int32 = 0; k < nk; k++) {
				filterBuf[cur + k] = (((raw[rp + k] as int32) + (filterBuf[prior + k] as int32)) & 255) as uint8;
			}
		} else if (filter == FILTER_AVG) {
			for (let k: int32 = 0; k < filterBytes; k++) {
				filterBuf[cur + k] = (((raw[rp + k] as int32) + ((filterBuf[prior + k] as int32) >> 1)) & 255) as uint8;
			}
			for (let k: int32 = filterBytes; k < nk; k++) {
				const sum = (filterBuf[prior + k] as int32) + (filterBuf[cur + k - filterBytes] as int32);
				filterBuf[cur + k] = (((raw[rp + k] as int32) + (sum >> 1)) & 255) as uint8;
			}
		} else if (filter == FILTER_PAETH) {
			for (let k: int32 = 0; k < filterBytes; k++) {
				filterBuf[cur + k] = (((raw[rp + k] as int32) + (filterBuf[prior + k] as int32)) & 255) as uint8;
			}
			for (let k: int32 = filterBytes; k < nk; k++) {
				const p = paeth(
					filterBuf[cur + k - filterBytes] as int32, filterBuf[prior + k] as int32,
					filterBuf[prior + k - filterBytes] as int32,
				);
				filterBuf[cur + k] = (((raw[rp + k] as int32) + p) & 255) as uint8;
			}
		} else {
			for (let k: int32 = 0; k < filterBytes; k++) { filterBuf[cur + k] = raw[rp + k]; }
			for (let k: int32 = filterBytes; k < nk; k++) {
				const half = (filterBuf[cur + k - filterBytes] as int32) >> 1;
				filterBuf[cur + k] = (((raw[rp + k] as int32) + half) & 255) as uint8;
			}
		}
		rp += nk;
		if (depth < 8) {
			const scale: int32 = d.color == 0 ? DEPTH_SCALE[depth] : 1;
			let inPos: int32 = cur;
			let outPos: int32 = dest;
			let inb: int32 = 0;
			const nsmp = x * imgN;
			if (depth == 4) {
				for (let i: int32 = 0; i < nsmp; i++) {
					if ((i & 1) == 0) {
						inb = filterBuf[inPos] as int32;
						inPos++;
					}
					d.out[outPos] = (scale * (inb >> 4)) as uint8;
					outPos++;
					inb = (inb << 4) & 255;
				}
			} else if (depth == 2) {
				for (let i: int32 = 0; i < nsmp; i++) {
					if ((i & 3) == 0) {
						inb = filterBuf[inPos] as int32;
						inPos++;
					}
					d.out[outPos] = (scale * (inb >> 6)) as uint8;
					outPos++;
					inb = (inb << 2) & 255;
				}
			} else {
				for (let i: int32 = 0; i < nsmp; i++) {
					if ((i & 7) == 0) {
						inb = filterBuf[inPos] as int32;
						inPos++;
					}
					d.out[outPos] = (scale * (inb >> 7)) as uint8;
					outPos++;
					inb = (inb << 1) & 255;
				}
			}
			if (imgN != outN) { d.alphaExpand8InPlace(dest, x, imgN); }
		} else if (depth == 8) {
			if (imgN == outN) {
				for (let i: int32 = 0; i < x * imgN; i++) { d.out[dest + i] = filterBuf[cur + i]; }
			} else if (imgN == 1) {
				for (let i: int32 = x - 1; i >= 0; i--) {
					d.out[dest + i * 2 + 1] = 255;
					d.out[dest + i * 2] = filterBuf[cur + i];
				}
			} else {
				for (let i: int32 = x - 1; i >= 0; i--) {
					d.out[dest + i * 4 + 3] = 255;
					d.out[dest + i * 4 + 2] = filterBuf[cur + i * 3 + 2];
					d.out[dest + i * 4 + 1] = filterBuf[cur + i * 3 + 1];
					d.out[dest + i * 4] = filterBuf[cur + i * 3];
				}
			}
		} else {
			let src: int32 = cur;
			let dst: int32 = dest;
			if (imgN == outN) {
				for (let i: int32 = 0; i < x * imgN; i++) {
					d.out16[dst] = (((filterBuf[src] as int32) << 8) | (filterBuf[src + 1] as int32)) as uint16;
					dst++;
					src += 2;
				}
			} else if (imgN == 1) {
				for (let i: int32 = 0; i < x; i++) {
					d.out16[dst] = (((filterBuf[src] as int32) << 8) | (filterBuf[src + 1] as int32)) as uint16;
					d.out16[dst + 1] = 0xffff;
					dst += 2;
					src += 2;
				}
			} else {
				for (let i: int32 = 0; i < x; i++) {
					d.out16[dst] = (((filterBuf[src] as int32) << 8) | (filterBuf[src + 1] as int32)) as uint16;
					d.out16[dst + 1] = (((filterBuf[src + 2] as int32) << 8) | (filterBuf[src + 3] as int32)) as uint16;
					d.out16[dst + 2] = (((filterBuf[src + 4] as int32) << 8) | (filterBuf[src + 5] as int32)) as uint16;
					d.out16[dst + 3] = 0xffff;
					dst += 4;
					src += 6;
				}
			}
		}
	}
	return allOk;
}

function alphaExpand8InPlace(this d: PngDecoder, dest: int32, x: int32, imgN: int32): void {
	if (imgN == 1) {
		for (let i: int32 = x - 1; i >= 0; i--) {
			d.out[dest + i * 2 + 1] = 255;
			d.out[dest + i * 2] = d.out[dest + i];
		}
	} else {
		for (let i: int32 = x - 1; i >= 0; i--) {
			d.out[dest + i * 4 + 3] = 255;
			d.out[dest + i * 4 + 2] = d.out[dest + i * 3 + 2];
			d.out[dest + i * 4 + 1] = d.out[dest + i * 3 + 1];
			d.out[dest + i * 4] = d.out[dest + i * 3];
		}
	}
}

function createPngImage(this d: PngDecoder, outN: int32): boolean {
	if (d.interlace == 0) {
		return d.createPngImageRaw(d.expanded, 0, (d.expandedLen as int64), outN, d.imgX, d.imgY);
	}
	const wide = d.depth == 16;
	if (!mad3Valid(d.imgX, d.imgY, outN * (wide ? 2 : 1), 0)) { return fail("outofmem"); }
	const finalCount = d.imgX * d.imgY * outN;
	let final8: Vec<uint8> = [];
	if (!wide) { final8 = new Array<uint8>(finalCount); }
	const final16: uint16[] = wide ? new Array<uint16>(finalCount) : [];
	let dataStart: int32 = 0;
	let dataLen: int64 = (d.expandedLen as int64);
	for (let p: int32 = 0; p < 7; p++) {
		const x = (d.imgX - XORIG[p] + XSPC[p] - 1) / XSPC[p];
		const y = (d.imgY - YORIG[p] + YSPC[p] - 1) / YSPC[p];
		if (x == 0 || y == 0) { continue; }
		const imgLen = (((d.imgN * x * d.depth + 7) >> 3) + 1) * y;
		if (!d.createPngImageRaw(d.expanded, dataStart, dataLen, outN, x, y)) { return false; }
		for (let j: int32 = 0; j < y; j++) {
			for (let i: int32 = 0; i < x; i++) {
				const outY = j * YSPC[p] + YORIG[p];
				const outX = i * XSPC[p] + XORIG[p];
				const to = (outY * d.imgX + outX) * outN;
				const from = (j * x + i) * outN;
				for (let c: int32 = 0; c < outN; c++) {
					if (wide) {
						final16[to + c] = d.out16[from + c];
					} else {
						final8[to + c] = d.out[from + c];
					}
				}
			}
		}
		dataStart += imgLen;
		dataLen -= imgLen as int64;
	}
	if (wide) {
		d.out16 = final16;
	} else {
		d.out = move final8;
	}
	return true;
}

function computeTransparency(this d: PngDecoder, outN: int32): void {
	const pixelCount = d.imgX * d.imgY;
	let p: int32 = 0;
	if (outN == 2) {
		for (let i: int32 = 0; i < pixelCount; i++) {
			d.out[p + 1] = d.out[p] == d.tc[0] ? 0 : 255;
			p += 2;
		}
	} else {
		for (let i: int32 = 0; i < pixelCount; i++) {
			if (d.out[p] == d.tc[0] && d.out[p + 1] == d.tc[1] && d.out[p + 2] == d.tc[2]) {
				d.out[p + 3] = 0;
			}
			p += 4;
		}
	}
}

function computeTransparency16(this d: PngDecoder, outN: int32): void {
	const pixelCount = d.imgX * d.imgY;
	let p: int32 = 0;
	if (outN == 2) {
		for (let i: int32 = 0; i < pixelCount; i++) {
			d.out16[p + 1] = d.out16[p] == d.tc16[0] ? 0 : 65535;
			p += 2;
		}
	} else {
		for (let i: int32 = 0; i < pixelCount; i++) {
			const matches = d.out16[p] == d.tc16[0] && d.out16[p + 1] == d.tc16[1] &&
				d.out16[p + 2] == d.tc16[2];
			if (matches) { d.out16[p + 3] = 0; }
			p += 4;
		}
	}
}

function expandPngPalette(this d: PngDecoder, palImgN: int32): boolean {
	const pixelCount = d.imgX * d.imgY;
	if (!mad2Valid(pixelCount, palImgN, 0)) { return fail("outofmem"); }
	let expanded: Vec<uint8> = new Array<uint8>(pixelCount * palImgN);
	let p: int32 = 0;
	for (let i: int32 = 0; i < pixelCount; i++) {
		const n = (d.out[i] as int32) * 4;
		expanded[p] = d.palette[n];
		expanded[p + 1] = d.palette[n + 1];
		expanded[p + 2] = d.palette[n + 2];
		if (palImgN == 4) { expanded[p + 3] = d.palette[n + 3]; }
		p += palImgN;
	}
	d.out = move expanded;
	return true;
}

function failed(reason: string): Chunk {
	fail(reason);
	return Chunk.Failed;
}

function chunkIhdr(this d: PngDecoder, length: uint32): Chunk {
	if (!d.first) { return failed("multiple IHDR"); }
	d.first = false;
	if (length != 13) { return failed("bad IHDR len"); }
	const width = d.get32be();
	const height = d.get32be();
	const limit = d.maxSide as uint32;
	if (height > limit) { return failed("too large"); }
	if (width > limit) { return failed("too large"); }
	d.imgX = width as int32;
	d.imgY = height as int32;
	d.depth = d.get8();
	if (d.depth != 1 && d.depth != 2 && d.depth != 4 && d.depth != 8 && d.depth != 16) {
		return failed("1/2/4/8/16-bit only");
	}
	d.color = d.get8();
	if (d.color > 6) { return failed("bad ctype"); }
	if (d.color == 3 && d.depth == 16) { return failed("bad ctype"); }
	if (d.color == 3) {
		d.palImgN = 3;
	} else if ((d.color & 1) != 0) {
		return failed("bad ctype");
	}
	if (d.get8() != 0) { return failed("bad comp method"); }
	if (d.get8() != 0) { return failed("bad filter method"); }
	d.interlace = d.get8();
	if (d.interlace > 1) { return failed("bad interlace method"); }
	if (d.imgX == 0 || d.imgY == 0) { return failed("0-pixel image"); }
	if (d.palImgN == 0) {
		d.imgN = ((d.color & 2) != 0 ? 3 : 1) + ((d.color & 4) != 0 ? 1 : 0);
		if ((1 << 30) / d.imgX / d.imgN < d.imgY) { return failed("too large"); }
	} else {
		d.imgN = 1;
		if ((1 << 30) / d.imgX / 4 < d.imgY) { return failed("too large"); }
	}
	return Chunk.Next;
}

function chunkPlte(this d: PngDecoder, length: uint32): Chunk {
	if (d.first) { return failed("first not IHDR"); }
	if (length > 256 * 3) { return failed("invalid PLTE"); }
	d.palLen = (length / 3) as int32;
	if ((d.palLen as uint32) * 3 != length) { return failed("invalid PLTE"); }
	for (let i: int32 = 0; i < d.palLen; i++) {
		d.palette[i * 4] = d.get8() as uint8;
		d.palette[i * 4 + 1] = d.get8() as uint8;
		d.palette[i * 4 + 2] = d.get8() as uint8;
		d.palette[i * 4 + 3] = 255;
	}
	return Chunk.Next;
}

function chunkTrns(this d: PngDecoder, length: uint32): Chunk {
	if (d.first) { return failed("first not IHDR"); }
	if (d.ioff > 0) { return failed("tRNS after IDAT"); }
	if (d.palImgN != 0) {
		if (d.headerOnly) {
			d.imgN = 4;
			return Chunk.Done;
		}
		if (d.palLen == 0) { return failed("tRNS before PLTE"); }
		if (length > (d.palLen as uint32)) { return failed("bad tRNS len"); }
		d.palImgN = 4;
		for (let i: int32 = 0; i < (length as int32); i++) {
			d.palette[i * 4 + 3] = d.get8() as uint8;
		}
	} else {
		if ((d.imgN & 1) == 0) { return failed("tRNS with alpha"); }
		if (length != ((d.imgN * 2) as uint32)) { return failed("bad tRNS len"); }
		d.hasTrans = true;
		if (d.headerOnly) {
			d.imgN++;
			return Chunk.Done;
		}
		for (let k: int32 = 0; k < d.imgN && k < 3; k++) {
			if (d.depth == 16) {
				d.tc16[k] = d.get16be() as uint16;
			} else {
				d.tc[k] = (((d.get16be() & 255) * DEPTH_SCALE[d.depth]) & 255) as uint8;
			}
		}
	}
	return Chunk.Next;
}

function chunkIdat(this d: PngDecoder, length: uint32): Chunk {
	if (d.first) { return failed("first not IHDR"); }
	if (d.palImgN != 0 && d.palLen == 0) { return failed("no PLTE"); }
	if (d.headerOnly) {
		if (d.palImgN != 0) { d.imgN = d.palImgN; }
		return Chunk.Done;
	}
	if (length > ((1 as uint32) << 30)) { return failed("IDAT size limit"); }
	if ((d.ioff as int64) + (length as int64) > INT_MAX) { return Chunk.Failed; }
	const count = length as int32;
	if (d.pos + (count as int64) > (d.input.bytes.length as int64)) { return failed("outofdata"); }
	for (let i: int32 = 0; i < count; i++) { d.idata.push(d.input.bytes[(d.pos as int32) + i]); }
	d.pos += count as int64;
	d.ioff += count;
	return Chunk.Next;
}

function chunkIend(this d: PngDecoder, reqComp: int32): Chunk {
	if (d.first) { return failed("first not IHDR"); }
	if (d.headerOnly) { return Chunk.Done; }
	if (d.ioff == 0) { return failed("no IDAT"); }
	const bytesPerLine = ((d.imgX as int64) * (d.depth as int64) + 7) / 8;
	const guess = bytesPerLine * (d.imgY as int64) * (d.imgN as int64) + (d.imgY as int64);
	if (guess > INT_MAX) { return Chunk.Failed; }
	const z = new ZBuf();
	z.input = d.idata;
	z.zbufferEnd = d.ioff;
	z.zout = new Array<uint8>(guess as int32);
	z.zoutEnd = guess as int32;
	if (!z.parseZlib(!d.isIphone)) { return Chunk.Failed; }
	d.expanded = z.zout;
	d.expandedLen = z.zoutPos;
	d.idata = [];
	if ((reqComp == d.imgN + 1 && reqComp != 3 && d.palImgN == 0) || d.hasTrans) {
		d.imgOutN = d.imgN + 1;
	} else {
		d.imgOutN = d.imgN;
	}
	if (!d.createPngImage(d.imgOutN)) { return Chunk.Failed; }
	if (d.hasTrans) {
		if (d.depth == 16) {
			d.computeTransparency16(d.imgOutN);
		} else {
			d.computeTransparency(d.imgOutN);
		}
	}
	if (d.palImgN != 0) {
		d.imgN = d.palImgN;
		d.imgOutN = d.palImgN;
		if (reqComp >= 3) { d.imgOutN = reqComp; }
		if (!d.expandPngPalette(d.imgOutN)) { return Chunk.Failed; }
	} else if (d.hasTrans) {
		d.imgN++;
	}
	d.expanded = [];
	return Chunk.Done;
}

function chunkOther(this d: PngDecoder, chunkType: uint32, length: uint32): Chunk {
	if (d.first) { return failed("first not IHDR"); }
	if ((chunkType & ((1 as uint32) << 29)) == 0) {
		let name = "";
		for (let i: int32 = 0; i < 4; i++) {
			name += String.fromCharCode(((chunkType >> ((24 - 8 * i) as uint32)) & 255) as int32);
		}
		return failed(untilNul(name + " PNG chunk not known"));
	}
	d.skip(length);
	return Chunk.Next;
}

function parsePngFile(this d: PngDecoder, reqComp: int32): boolean {
	if (!d.checkPngHeader()) { return false; }
	while (true) {
		const length = d.get32be();
		const chunkType = d.get32be();
		let step = Chunk.Next;
		if (chunkType == CHUNK_CGBI) {
			d.isIphone = true;
			d.skip(length);
		} else if (chunkType == CHUNK_IHDR) {
			step = d.chunkIhdr(length);
		} else if (chunkType == CHUNK_PLTE) {
			step = d.chunkPlte(length);
		} else if (chunkType == CHUNK_TRNS) {
			step = d.chunkTrns(length);
		} else if (chunkType == CHUNK_IDAT) {
			step = d.chunkIdat(length);
		} else if (chunkType == CHUNK_IEND) {
			step = d.chunkIend(reqComp);
		} else {
			step = d.chunkOther(chunkType, length);
		}
		if (step == Chunk.Failed) { return false; }
		if (step == Chunk.Done) { return true; }
		d.skipCrc();
	}
}

function computeY(r: int32, g: int32, b: int32): int32 {
	return ((r * 77) + (g * 150) + (29 * b)) >> 8;
}

function convertFormat(
	data: Readonly<Span<uint8>>, imgN: int32, reqComp: int32, x: int32, y: int32,
): Vec<uint8> {
	let good: Vec<uint8> = new Array<uint8>(reqComp * x * y);
	for (let j: int32 = 0; j < y; j++) {
		let src: int32 = j * x * imgN;
		let dest: int32 = j * x * reqComp;
		for (let i: int32 = 0; i < x; i++) {
			if (imgN == 1) {
				good[dest] = data[src];
				if (reqComp == 2) {
					good[dest + 1] = 255;
				} else {
					good[dest + 1] = data[src];
					good[dest + 2] = data[src];
					if (reqComp == 4) { good[dest + 3] = 255; }
				}
			} else if (imgN == 2) {
				good[dest] = data[src];
				if (reqComp == 3) {
					good[dest + 1] = data[src];
					good[dest + 2] = data[src];
				} else if (reqComp == 4) {
					good[dest + 1] = data[src];
					good[dest + 2] = data[src];
					good[dest + 3] = data[src + 1];
				}
			} else if (imgN == 3) {
				if (reqComp == 4) {
					good[dest] = data[src];
					good[dest + 1] = data[src + 1];
					good[dest + 2] = data[src + 2];
					good[dest + 3] = 255;
				} else {
					const y8 = computeY(data[src] as int32, data[src + 1] as int32, data[src + 2] as int32);
					good[dest] = y8 as uint8;
					if (reqComp == 2) { good[dest + 1] = 255; }
				}
			} else {
				if (reqComp == 3) {
					good[dest] = data[src];
					good[dest + 1] = data[src + 1];
					good[dest + 2] = data[src + 2];
				} else {
					const y8 = computeY(data[src] as int32, data[src + 1] as int32, data[src + 2] as int32);
					good[dest] = y8 as uint8;
					if (reqComp == 2) { good[dest + 1] = data[src + 3]; }
				}
			}
			src += imgN;
			dest += reqComp;
		}
	}
	return move good;
}

function convertFormat16(
	data: uint16[], imgN: int32, reqComp: int32, x: int32, y: int32,
): uint16[] {
	const good: uint16[] = new Array<uint16>(reqComp * x * y);
	for (let j: int32 = 0; j < y; j++) {
		let src: int32 = j * x * imgN;
		let dest: int32 = j * x * reqComp;
		for (let i: int32 = 0; i < x; i++) {
			if (imgN == 1) {
				good[dest] = data[src];
				if (reqComp == 2) {
					good[dest + 1] = 0xffff;
				} else {
					good[dest + 1] = data[src];
					good[dest + 2] = data[src];
					if (reqComp == 4) { good[dest + 3] = 0xffff; }
				}
			} else if (imgN == 2) {
				good[dest] = data[src];
				if (reqComp == 3) {
					good[dest + 1] = data[src];
					good[dest + 2] = data[src];
				} else if (reqComp == 4) {
					good[dest + 1] = data[src];
					good[dest + 2] = data[src];
					good[dest + 3] = data[src + 1];
				}
			} else if (imgN == 3) {
				if (reqComp == 4) {
					good[dest] = data[src];
					good[dest + 1] = data[src + 1];
					good[dest + 2] = data[src + 2];
					good[dest + 3] = 0xffff;
				} else {
					const y16 = computeY(data[src] as int32, data[src + 1] as int32, data[src + 2] as int32);
					good[dest] = y16 as uint16;
					if (reqComp == 2) { good[dest + 1] = 0xffff; }
				}
			} else {
				if (reqComp == 3) {
					good[dest] = data[src];
					good[dest + 1] = data[src + 1];
					good[dest + 2] = data[src + 2];
				} else {
					const y16 = computeY(data[src] as int32, data[src + 1] as int32, data[src + 2] as int32);
					good[dest] = y16 as uint16;
					if (reqComp == 2) { good[dest + 1] = data[src + 3]; }
				}
			}
			src += imgN;
			dest += reqComp;
		}
	}
	return good;
}

// stbi_load_from_memory for a PNG: channels is the file's, pixels hold reqComp channels per
// texel (the file's when reqComp is 0), 16-bit samples reduced to their high byte. maxSide is
// STBI_MAX_DIMENSIONS and at most 16384.
export function decodePng(
	bytes: Readonly<Span<uint8>>, reqComp: int32, maxSide: int32,
): Result<PngImage, string> {
	if (maxSide < 1 || maxSide > 16384) { throw new Error("png: maxSide must be 1 to 16384"); }
	const d = new PngDecoder({ bytes: bytes }, maxSide);
	if (!d.checkPngHeader()) {
		fail("unknown image type");
		return Result.err(failureReason ?? "");
	}
	d.pos = 0;
	if (reqComp < 0 || reqComp > 4) {
		fail("bad req_comp");
		return Result.err(failureReason ?? "");
	}
	if (!d.parsePngFile(reqComp)) { return Result.err(failureReason ?? ""); }
	const convert = reqComp != 0 && reqComp != d.imgOutN;
	const outN = reqComp != 0 ? reqComp : d.imgN;
	let pixels: Vec<uint8>;
	if (d.depth == 16) {
		const wide = convert ? convertFormat16(d.out16, d.imgOutN, reqComp, d.imgX, d.imgY) : d.out16;
		let reduced: Vec<uint8> = new Array<uint8>(d.imgX * d.imgY * outN);
		for (let i: int32 = 0; i < reduced.length; i++) {
			reduced[i] = (((wide[i] as int32) >> 8) & 255) as uint8;
		}
		pixels = move reduced;
	} else {
		if (convert) {
			pixels = convertFormat(d.out, d.imgOutN, reqComp, d.imgX, d.imgY);
		} else {
			pixels = move d.out;
		}
	}
	return Result.ok({ width: d.imgX, height: d.imgY, channels: d.imgN, pixels: pixels });
}

export struct PngInfo {
	width: int32;
	height: int32;
	channels: int32;
}

// stbi_info_from_memory for a PNG: the header scan, which reads on to the first IDAT to learn
// whether a tRNS adds an alpha channel. maxSide is STBI_MAX_DIMENSIONS.
export function pngInfo(bytes: Readonly<Span<uint8>>, maxSide: int32): Result<PngInfo, string> {
	const d = new PngDecoder({ bytes: bytes }, maxSide);
	d.headerOnly = true;
	if (!d.parsePngFile(0)) { return Result.err(failureReason ?? ""); }
	return Result.ok({ width: d.imgX, height: d.imgY, channels: d.imgN });
}
