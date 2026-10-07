const CRC_POLYNOMIAL: uint32 = 0xEDB88320;
const ALL_ONES: uint32 = 0xFFFFFFFF;
const CHUNK_IHDR: uint32 = 0x49484452;
const CHUNK_PLTE: uint32 = 0x504C5445;
const CHUNK_IDAT: uint32 = 0x49444154;
const CHUNK_IEND: uint32 = 0x49454E44;
export const COLOR_GREY_ALPHA: int32 = 4;
export const COLOR_RGB: int32 = 2;
export const COLOR_PALETTE: int32 = 3;
export const COLOR_RGBA: int32 = 6;

function crc32(bytes: Span<uint8>): uint32 {
	let crc: uint32 = ALL_ONES;
	for (const b of bytes) {
		crc = crc ^ (b as uint32);
		for (let k = 0; k < 8; k++) {
			const low: uint32 = crc & (1 as uint32);
			crc = crc >> (1 as uint32);
			if (low != 0) { crc = crc ^ CRC_POLYNOMIAL; }
		}
	}
	return crc ^ ALL_ONES;
}

function adler32(bytes: Span<uint8>): uint32 {
	let a: uint32 = 1;
	let b: uint32 = 0;
	for (const byte of bytes) {
		a = (a + (byte as uint32)) % (65521 as uint32);
		b = (b + a) % (65521 as uint32);
	}
	return (b << (16 as uint32)) | a;
}

function pushBe32(ref out: Vec<uint8>, value: uint32): void {
	out.push(((value >> (24 as uint32)) & (0xFF as uint32)) as uint8);
	out.push(((value >> (16 as uint32)) & (0xFF as uint32)) as uint8);
	out.push(((value >> (8 as uint32)) & (0xFF as uint32)) as uint8);
	out.push((value & (0xFF as uint32)) as uint8);
}

function pushChunk(ref out: Vec<uint8>, kind: uint32, data: Readonly<Span<uint8>>): void {
	pushBe32(out, data.length as uint32);
	let typed: Vec<uint8> = [];
	pushBe32(typed, kind);
	for (const b of data) { typed.push(b); }
	for (const b of typed) { out.push(b); }
	pushBe32(out, crc32(typed));
}

// One stored (uncompressed) deflate block, RFC 1950/1951: enough for a few pixels.
function zlibStored(raw: Span<uint8>): Vec<uint8> {
	let out: Vec<uint8> = [0x78 as uint8, 0x01 as uint8, 0x01 as uint8];
	const length: int32 = raw.length as int32;
	out.push((length & 0xFF) as uint8);
	out.push(((length >> 8) & 0xFF) as uint8);
	out.push((~length & 0xFF) as uint8);
	out.push(((~length >> 8) & 0xFF) as uint8);
	for (const b of raw) { out.push(b); }
	pushBe32(out, adler32(raw));
	return out;
}

export function pngOf(
	width: int32,
	height: int32,
	bitDepth: int32,
	colorType: int32,
	unfilteredRows: Readonly<Span<uint8>>,
	rowLength: int32,
	palette: Readonly<Span<uint8>>,
): Vec<uint8> {
	let out: Vec<uint8> = [
		0x89 as uint8, 0x50 as uint8, 0x4E as uint8, 0x47 as uint8,
		0x0D as uint8, 0x0A as uint8, 0x1A as uint8, 0x0A as uint8,
	];
	let header: Vec<uint8> = [];
	pushBe32(header, width as uint32);
	pushBe32(header, height as uint32);
	header.push(bitDepth as uint8);
	header.push(colorType as uint8);
	header.push(0 as uint8);
	header.push(0 as uint8);
	header.push(0 as uint8);
	pushChunk(out, CHUNK_IHDR, header);
	if (palette.length > 0) { pushChunk(out, CHUNK_PLTE, palette); }
	let filtered: Vec<uint8> = [];
	for (let y = 0; y < height; y++) {
		filtered.push(0 as uint8);
		for (let x = 0; x < rowLength; x++) { filtered.push(unfilteredRows[y * rowLength + x]); }
	}
	pushChunk(out, CHUNK_IDAT, zlibStored(filtered));
	pushChunk(out, CHUNK_IEND, []);
	return out;
}

export function bytesOf(values: Span<int32>): Vec<uint8> {
	let out: Vec<uint8> = [];
	for (const v of values) { out.push(v as uint8); }
	return out;
}

function hexBytes(hex: string): Vec<uint8> {
	let out: Vec<uint8> = [];
	for (let i = 0; i + 1 < hex.byteLength(); i += 2) {
		out.push(((nibble(hex.byteAt(i)) << 4) | nibble(hex.byteAt(i + 1))) as uint8);
	}
	return out;
}

function nibble(c: int32): int32 {
	return c >= 65 ? c - 55 : c - 48;
}

export function rgbaPng(): Vec<uint8> {
	const rows: Vec<uint8> = bytesOf([
		255, 0, 0, 255, 0, 255, 0, 255,
		0, 0, 255, 255, 255, 255, 0, 128,
	]);
	return pngOf(2, 2, 8, COLOR_RGBA, rows, 8, []);
}

// magick -size 16x8 xc:"rgb(200,100,50)" ( -size 8x8 xc:"rgb(40,160,220)" ) -geometry +8+0
// -composite -quality 100 -sampling-factor 1x1 -strip twoBlocks.jpg
export function twoBlockJpeg(): Vec<uint8> {
	return hexBytes(
		"FFD8FFE000104A46494600010100000100010000FFDB00430001010101010101010101010101010101010101"
		+ "0101010101010101010101010101010101010101010101010101010101010101010101010101010101010101"
		+ "01FFDB0043010101010101010101010101010101010101010101010101010101010101010101010101010101"
		+ "0101010101010101010101010101010101010101010101010101FFC000110800080010030111000211010311"
		+ "01FFC40014000100000000000000000000000000000006FFC400141001000000000000000000000000000000"
		+ "00FFC400150101010000000000000000000000000000090AFFC4001411010000000000000000000000000000"
		+ "0000FFDA000C03010002110311003F003E2BCD81C2B8108EFFD9",
	);
}

export struct GifFrame {
	x: int32;
	y: int32;
	w: int32;
	h: int32;
	indices: Vec<uint8>;
	delayCentiseconds: int32;
	disposal: int32;
}

export const GIF_RED: uint32 = 0xFF0000FF;
export const GIF_GREEN: uint32 = 0xFF00FF00;
export const GIF_BLUE: uint32 = 0xFFFF0000;
export const GIF_YELLOW: uint32 = 0xFF00FFFF;

function pushLe16(ref out: Vec<uint8>, value: int32): void {
	out.push((value & 0xFF) as uint8);
	out.push(((value >> 8) & 0xFF) as uint8);
}

const GIF_CLEAR: int32 = 4;
const GIF_END: int32 = 5;
const GIF_CODE_BITS: int32 = 3;

function gifLzw(indices: Readonly<Span<uint8>>): Vec<uint8> {
	let out: Vec<uint8> = [];
	let accumulator: int32 = 0;
	let held: int32 = 0;
	let codes: Vec<int32> = [GIF_CLEAR];
	for (let i = 0; i < indices.length; i++) {
		if (i > 0 && i % 2 == 0) { codes.push(GIF_CLEAR); }
		codes.push(indices[i] as int32);
	}
	codes.push(GIF_END);
	for (const code of codes) {
		accumulator = accumulator | (code << held);
		held = held + GIF_CODE_BITS;
		while (held >= 8) {
			out.push((accumulator & 0xFF) as uint8);
			accumulator = accumulator >> 8;
			held = held - 8;
		}
	}
	if (held > 0) { out.push((accumulator & 0xFF) as uint8); }
	return out;
}

// A four-colour global palette: red, green, blue, yellow. Each frame is a sub-rectangle of
// palette indices; the LZW stream clears every two literals so its codes stay three bits.
export function animatedGif(
	version: int32,
	width: int32,
	height: int32,
	frames: Readonly<Span<GifFrame>>,
): Vec<uint8> {
	let out: Vec<uint8> = [0x47 as uint8, 0x49 as uint8, 0x46 as uint8, 0x38 as uint8,
		version as uint8, 0x61 as uint8];
	pushLe16(out, width);
	pushLe16(out, height);
	out.push(0x81 as uint8);
	out.push(0 as uint8);
	out.push(0 as uint8);
	for (const b of bytesOf([255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0])) { out.push(b); }
	for (const frame of frames) {
		out.push(0x21 as uint8);
		out.push(0xF9 as uint8);
		out.push(4 as uint8);
		out.push((frame.disposal << 2) as uint8);
		pushLe16(out, frame.delayCentiseconds);
		out.push(0 as uint8);
		out.push(0 as uint8);
		out.push(0x2C as uint8);
		pushLe16(out, frame.x);
		pushLe16(out, frame.y);
		pushLe16(out, frame.w);
		pushLe16(out, frame.h);
		out.push(0 as uint8);
		out.push(2 as uint8);
		const lzw: Vec<uint8> = gifLzw(frame.indices);
		if (lzw.length > 255) {
			console.log(`imageBytes: ${lzw.length} LZW bytes need more than one GIF sub-block`);
			unreachable;
		}
		out.push((lzw.length as int32) as uint8);
		for (const b of lzw) { out.push(b); }
		out.push(0 as uint8);
	}
	out.push(0x3B as uint8);
	return out;
}

export function solidFrame(width: int32, height: int32, index: int32, delay: int32): GifFrame {
	let indices: Vec<uint8> = [];
	for (let i = 0; i < width * height; i++) { indices.push(index as uint8); }
	return {
		x: 0, y: 0, w: width, h: height, indices: indices, delayCentiseconds: delay, disposal: 1,
	};
}
