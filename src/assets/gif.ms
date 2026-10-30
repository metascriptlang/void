// Void Asset — the GIF decoder: stb_image.h's GIF path (LZW, interlace, local and global palettes,
// transparency, frame composition and disposal, delays) as stbi_load_gif_from_memory runs it,
// and Void's own scanner that counts the frames and finds what stb_image cannot decode. Alike
// on every target. Pixels are one 0xAABBGGRR word each.

import { mad3Valid, zeros32, zeros8 } from "./stbCommon";

export struct GifFrames {
	width: int32;
	height: int32;
	frameCount: int32;
	pixels: Vec<uint32>;
	delays: Vec<int32>;
}

export struct GifScan {
	width: int32;
	height: int32;
	frameCount: int32;
}

export enum GifScanError {
	Undecodable,
	Disposal3,
}

const GIF_SCAN_MAX_FRAMES: int32 = 0xFFFFFFF;
const LZW_CODES: int32 = 8192;

let failureReason: string | null = null;

// stbi_failure_reason: set by every failure, never cleared.
export function gifFailureReason(): string | null {
	return failureReason;
}

function fail(reason: string): boolean {
	failureReason = reason;
	return false;
}

function isGifSignature(b: Readonly<Span<uint8>>): boolean {
	return b.length >= 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38
		&& (b[4] == 0x37 || b[4] == 0x39) && b[5] == 0x61;
}

function skipSubBlocks(b: Readonly<Span<uint8>>, n: int64, start: int64): int64 {
	let i = start;
	while (true) {
		if (i >= n) { return -1; }
		const size = b[i as int32] as int64;
		i++;
		if (size == 0) { return i; }
		i += size;
		if (i > n) { return -1; }
	}
}

// What a GIF holds before stb_image decodes it: its canvas, its frame count, and a disposal
// method 3 on a frame past the first, which stb_image answers by reading before its buffer.
export function gifScan(bytes: Readonly<Span<uint8>>): Result<GifScan, GifScanError> {
	const b = bytes;
	const n = b.length as int64;
	if (n < 13 || b[0] != 0x47 || b[1] != 0x49 || b[2] != 0x46 || b[3] != 0x38
		|| (b[4] != 0x37 && b[4] != 0x39) || b[5] != 0x61) {
		return Result.err(GifScanError.Undecodable);
	}
	const width = (b[6] as int32) | ((b[7] as int32) << 8);
	const height = (b[8] as int32) | ((b[9] as int32) << 8);
	let i: int64 = 13;
	if (((b[10] as int32) & 0x80) != 0) { i += (3 as int64) << (((b[10] as int64) & 7) + 1); }
	let frames: int64 = 0;
	let restoringFrame: int64 = -1;
	let disposal: int32 = 0;
	while (i < n) {
		const tag = b[i as int32] as int32;
		i++;
		if (tag == 0x3B) {
			if (frames == 0 || width == 0 || height == 0) { return Result.err(GifScanError.Undecodable); }
			if (restoringFrame >= 0) { return Result.err(GifScanError.Disposal3); }
			if (frames > (GIF_SCAN_MAX_FRAMES as int64)) { return Result.err(GifScanError.Undecodable); }
			return Result.ok({ width: width, height: height, frameCount: frames as int32 });
		}
		if (tag == 0x21) {
			if (i + 1 >= n) { return Result.err(GifScanError.Undecodable); }
			const label = b[i as int32] as int32;
			i++;
			if (label == 0xF9) {
				if (i + 2 >= n) { return Result.err(GifScanError.Undecodable); }
				disposal = ((b[(i + 1) as int32] as int32) >> 2) & 7;
			}
			i = skipSubBlocks(b, n, i);
		} else if (tag == 0x2C) {
			if (i + 9 >= n) { return Result.err(GifScanError.Undecodable); }
			const packed = b[(i + 8) as int32] as int32;
			i += 9;
			if ((packed & 0x80) != 0) { i += (3 as int64) << (((packed & 7) as int64) + 1); }
			i++;
			if (i >= n) { return Result.err(GifScanError.Undecodable); }
			i = skipSubBlocks(b, n, i);
			if (disposal == 3 && frames >= 1 && restoringFrame < 0) { restoringFrame = frames; }
			frames++;
		} else {
			return Result.err(GifScanError.Undecodable);
		}
		if (i < 0) { return Result.err(GifScanError.Undecodable); }
	}
	return Result.err(GifScanError.Undecodable);
}

struct GifInput {
	bytes: Readonly<Span<uint8>>;
}

class GifDecoder {
	input: GifInput;
	pos: int64 = 0;
	maxSide: int32;
	w: int32 = 0;
	h: int32 = 0;
	started: boolean = false;
	out: uint8[] = [];
	background: uint8[] = [];
	history: uint8[] = [];
	flags: int32 = 0;
	bgindex: int32 = 0;
	ratio: int32 = 0;
	transparent: int32 = 0;
	eflags: int32 = 0;
	pal: uint8[] = zeros8(1024);
	lpal: uint8[] = zeros8(1024);
	codePrefix: int32[] = zeros32(LZW_CODES);
	codeFirst: uint8[] = zeros8(LZW_CODES);
	codeSuffix: uint8[] = zeros8(LZW_CODES);
	localTable: boolean = false;
	parse: int32 = 0;
	step: int32 = 0;
	lflags: int32 = 0;
	startX: int32 = 0;
	startY: int32 = 0;
	maxX: int32 = 0;
	maxY: int32 = 0;
	curX: int32 = 0;
	curY: int32 = 0;
	lineSize: int32 = 0;
	delay: int32 = 0;

	constructor(input: GifInput, maxSide: int32) {
		this.input = input;
		this.maxSide = maxSide;
	}
}

function get8(this g: GifDecoder): int32 {
	if (g.pos < (g.input.bytes.length as int64)) {
		const value = g.input.bytes[g.pos as int32] as int32;
		g.pos++;
		return value;
	}
	return 0;
}

function get16le(this g: GifDecoder): int32 {
	const z = g.get8();
	return z + (g.get8() << 8);
}

function skip(this g: GifDecoder, n: int32): void {
	if (n == 0) { return; }
	if (n < 0) {
		g.pos = g.input.bytes.length as int64;
		return;
	}
	g.pos += n as int64;
}

function parseColortable(this g: GifDecoder, pal: uint8[], numEntries: int32, transp: int32): void {
	for (let i: int32 = 0; i < numEntries; i++) {
		pal[i * 4 + 2] = g.get8() as uint8;
		pal[i * 4 + 1] = g.get8() as uint8;
		pal[i * 4] = g.get8() as uint8;
		pal[i * 4 + 3] = transp == i ? 0 : 255;
	}
}

function gifHeader(this g: GifDecoder): boolean {
	if (g.get8() != 0x47 || g.get8() != 0x49 || g.get8() != 0x46 || g.get8() != 0x38) {
		return fail("not GIF");
	}
	const version = g.get8();
	if (version != 0x37 && version != 0x39) { return fail("not GIF"); }
	if (g.get8() != 0x61) { return fail("not GIF"); }

	failureReason = "";
	g.w = g.get16le();
	g.h = g.get16le();
	g.flags = g.get8();
	g.bgindex = g.get8();
	g.ratio = g.get8();
	g.transparent = -1;

	if (g.w > g.maxSide) { return fail("too large"); }
	if (g.h > g.maxSide) { return fail("too large"); }

	if ((g.flags & 0x80) != 0) { g.parseColortable(g.pal, 2 << (g.flags & 7), -1); }
	return true;
}

function outGifCode(this g: GifDecoder, code: int32): void {
	if (g.codePrefix[code] >= 0) { g.outGifCode(g.codePrefix[code]); }

	if (g.curY >= g.maxY) { return; }

	const idx = g.curX + g.curY;
	g.history[idx / 4] = 1;

	const table = g.localTable ? g.lpal : g.pal;
	const c = (g.codeSuffix[code] as int32) * 4;
	if ((table[c + 3] as int32) > 128) {
		g.out[idx] = table[c + 2];
		g.out[idx + 1] = table[c + 1];
		g.out[idx + 2] = table[c];
		g.out[idx + 3] = table[c + 3];
	}
	g.curX += 4;

	if (g.curX >= g.maxX) {
		g.curX = g.startX;
		g.curY += g.step;

		while (g.curY >= g.maxY && g.parse > 0) {
			g.step = (1 << g.parse) * g.lineSize;
			g.curY = g.startY + (g.step >> 1);
			g.parse--;
		}
	}
}

function processGifRaster(this g: GifDecoder): boolean {
	const lzwCs = g.get8();
	if (lzwCs > 12) { return false; }
	const clear = 1 << lzwCs;
	let first: boolean = true;
	let codesize = lzwCs + 1;
	let codemask = (1 << codesize) - 1;
	let bits: int32 = 0;
	let validBits: int32 = 0;
	for (let initCode: int32 = 0; initCode < clear; initCode++) {
		g.codePrefix[initCode] = -1;
		g.codeFirst[initCode] = initCode as uint8;
		g.codeSuffix[initCode] = initCode as uint8;
	}

	let avail = clear + 2;
	let oldcode: int32 = -1;

	let len: int32 = 0;
	while (true) {
		if (validBits < codesize) {
			if (len == 0) {
				len = g.get8();
				if (len == 0) { return true; }
			}
			len--;
			bits = bits | (g.get8() << validBits);
			validBits += 8;
		} else {
			const code = bits & codemask;
			bits = bits >> codesize;
			validBits -= codesize;
			if (code == clear) {
				codesize = lzwCs + 1;
				codemask = (1 << codesize) - 1;
				avail = clear + 2;
				oldcode = -1;
				first = false;
			} else if (code == clear + 1) {
				g.skip(len);
				len = g.get8();
				while (len > 0) {
					g.skip(len);
					len = g.get8();
				}
				return true;
			} else if (code <= avail) {
				if (first) { return fail("no clear code"); }

				if (oldcode >= 0) {
					const p = avail;
					avail++;
					if (avail > 8192) { return fail("too many codes"); }

					g.codePrefix[p] = oldcode;
					g.codeFirst[p] = g.codeFirst[oldcode];
					g.codeSuffix[p] = code == avail ? g.codeFirst[p] : g.codeFirst[code];
				} else if (code == avail) {
					return fail("illegal code in raster");
				}

				g.outGifCode(code);

				if ((avail & codemask) == 0 && avail <= 0x0FFF) {
					codesize++;
					codemask = (1 << codesize) - 1;
				}

				oldcode = code;
			} else {
				return fail("illegal code in raster");
			}
		}
	}
}

enum Frame {
	Next,
	End,
	Failed,
}

// The next frame composed on g.out: Next when there is one, End on the stream terminator.
// A disposal method 3 on a frame past the first would read before stb_image's buffer, so
// it is Failed here, which gifScan refuses first.
function gifLoadNext(this g: GifDecoder, hasTwoBack: boolean): Frame {
	let firstFrame: boolean = false;
	if (!g.started) {
		if (!g.gifHeader()) { return Frame.Failed; }
		if (!mad3Valid(4, g.w, g.h, 0)) {
			fail("GIF image is too large");
			return Frame.Failed;
		}
		const pcount = g.w * g.h;
		g.out = zeros8(4 * pcount);
		g.background = zeros8(4 * pcount);
		g.history = zeros8(pcount);
		g.started = true;
		firstFrame = true;
	} else {
		let dispose = (g.eflags & 0x1C) >> 2;
		const pcount = g.w * g.h;

		if (dispose == 3 && !hasTwoBack) { dispose = 2; }

		if (dispose == 3) {
			fail("GIF disposal method 3");
			return Frame.Failed;
		} else if (dispose == 2) {
			for (let pi: int32 = 0; pi < pcount; pi++) {
				if (g.history[pi] != 0) {
					for (let n: int32 = 0; n < 4; n++) { g.out[pi * 4 + n] = g.background[pi * 4 + n]; }
				}
			}
		}

		for (let i: int32 = 0; i < 4 * pcount; i++) { g.background[i] = g.out[i]; }
	}

	for (let i: int32 = 0; i < g.w * g.h; i++) { g.history[i] = 0; }

	while (true) {
		const tag = g.get8();
		if (tag == 0x2C) {
			const x = g.get16le();
			const y = g.get16le();
			const w = g.get16le();
			const h = g.get16le();
			if (((x + w) > g.w) || ((y + h) > g.h)) {
				fail("bad Image Descriptor");
				return Frame.Failed;
			}

			g.lineSize = g.w * 4;
			g.startX = x * 4;
			g.startY = y * g.lineSize;
			g.maxX = g.startX + w * 4;
			g.maxY = g.startY + h * g.lineSize;
			g.curX = g.startX;
			g.curY = g.startY;

			if (w == 0) { g.curY = g.maxY; }

			g.lflags = g.get8();

			if ((g.lflags & 0x40) != 0) {
				g.step = 8 * g.lineSize;
				g.parse = 3;
			} else {
				g.step = g.lineSize;
				g.parse = 0;
			}

			if ((g.lflags & 0x80) != 0) {
				g.parseColortable(
					g.lpal, 2 << (g.lflags & 7), (g.eflags & 0x01) != 0 ? g.transparent : -1,
				);
				g.localTable = true;
			} else if ((g.flags & 0x80) != 0) {
				g.localTable = false;
			} else {
				fail("missing color table");
				return Frame.Failed;
			}

			if (!g.processGifRaster()) { return Frame.Failed; }

			const pcount = g.w * g.h;
			if (firstFrame && g.bgindex > 0) {
				for (let pi: int32 = 0; pi < pcount; pi++) {
					if (g.history[pi] == 0) {
						g.pal[g.bgindex * 4 + 3] = 255;
						for (let n: int32 = 0; n < 4; n++) { g.out[pi * 4 + n] = g.pal[g.bgindex * 4 + n]; }
					}
				}
			}

			return Frame.Next;
		} else if (tag == 0x21) {
			const ext = g.get8();
			if (ext == 0xF9) {
				const len = g.get8();
				if (len == 4) {
					g.eflags = g.get8();
					g.delay = 10 * g.get16le();

					if (g.transparent >= 0) { g.pal[g.transparent * 4 + 3] = 255; }
					if ((g.eflags & 0x01) != 0) {
						g.transparent = g.get8();
						if (g.transparent >= 0) { g.pal[g.transparent * 4 + 3] = 0; }
					} else {
						g.skip(1);
						g.transparent = -1;
					}
				} else {
					g.skip(len);
					continue;
				}
			}
			let len = g.get8();
			while (len != 0) {
				g.skip(len);
				len = g.get8();
			}
		} else if (tag == 0x3B) {
			return Frame.End;
		} else {
			fail("unknown code");
			return Frame.Failed;
		}
	}
}

// stbi_load_gif_from_memory with 4 channels: every frame as the whole canvas, in one Vec, and
// each frame's delay in milliseconds as the file gives it. A frame that fails to decode ends
// the stream, as it does there, so the frame count is what decoded.
export function decodeGif(bytes: Readonly<Span<uint8>>, maxSide: int32): Result<GifFrames, string> {
	const g = new GifDecoder({ bytes: bytes }, maxSide);
	if (!isGifSignature(bytes)) {
		fail("not GIF");
		return Result.err(failureReason ?? "");
	}
	let pixels: Vec<uint32> = [];
	let delays: Vec<int32> = [];
	let layers: int32 = 0;
	while (true) {
		const frame = g.gifLoadNext(layers >= 2);
		if (frame != Frame.Next) { break; }
		layers++;
		const pcount = g.w * g.h;
		for (let pi: int32 = 0; pi < pcount; pi++) {
			const at = pi * 4;
			pixels.push(
				(g.out[at] as uint32) | ((g.out[at + 1] as uint32) << 8) | ((g.out[at + 2] as uint32) << 16)
					| ((g.out[at + 3] as uint32) << 24),
			);
		}
		delays.push(g.delay);
	}
	if (layers == 0) { return Result.err(failureReason ?? ""); }
	return Result.ok({
		width: g.w, height: g.h, frameCount: layers, pixels: move pixels, delays: move delays,
	});
}
