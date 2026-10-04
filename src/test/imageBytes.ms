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
