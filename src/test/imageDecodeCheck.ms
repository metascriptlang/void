import { decodeImage, imageFormatOf, ImageError, ImageFormat, Pixels } from "../assets/image";

const CRC_POLYNOMIAL: uint32 = 0xEDB88320;
const ALL_ONES: uint32 = 0xFFFFFFFF;
const CHUNK_IHDR: uint32 = 0x49484452;
const CHUNK_PLTE: uint32 = 0x504C5445;
const CHUNK_IDAT: uint32 = 0x49444154;
const CHUNK_IEND: uint32 = 0x49454E44;
const COLOR_GREY_ALPHA: int32 = 4;
const COLOR_RGB: int32 = 2;
const COLOR_PALETTE: int32 = 3;
const COLOR_RGBA: int32 = 6;

function crc32(bytes: Span<uint8>): uint32 {
	let crc: uint32 = ALL_ONES;
	for (const b of bytes) {
		crc = crc ^ (b as uint32);
		for (let k = 0; k < 8; k++) {
			crc = (crc & (1 as uint32)) != 0 ? (crc >> (1 as uint32)) ^ CRC_POLYNOMIAL : crc >> (1 as uint32);
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

function pushChunk(ref out: Vec<uint8>, kind: uint32, data: Span<uint8>): void {
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

function pngOf(
	width: int32,
	height: int32,
	bitDepth: int32,
	colorType: int32,
	unfilteredRows: Span<uint8>,
	rowLength: int32,
	palette: Span<uint8>,
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

function bytesOf(values: Span<int32>): Vec<uint8> {
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

function rgbaPng(): Vec<uint8> {
	const rows: Vec<uint8> = bytesOf([
		255, 0, 0, 255, 0, 255, 0, 255,
		0, 0, 255, 255, 255, 255, 0, 128,
	]);
	return pngOf(2, 2, 8, COLOR_RGBA, rows, 8, []);
}

// magick -size 16x8 xc:"rgb(200,100,50)" ( -size 8x8 xc:"rgb(40,160,220)" ) -geometry +8+0
// -composite -quality 100 -sampling-factor 1x1 -strip twoBlocks.jpg
function twoBlockJpeg(): Vec<uint8> {
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

function channel(word: uint32, shift: int32): int32 {
	return ((word >> (shift as uint32)) & (0xFF as uint32)) as int32;
}

function near(word: uint32, red: int32, green: int32, blue: int32): boolean {
	return Math.abs(channel(word, 0) - red) <= 2
		&& Math.abs(channel(word, 8) - green) <= 2
		&& Math.abs(channel(word, 16) - blue) <= 2
		&& channel(word, 24) == 255;
}

test "decodeImage reads a PNG's RGBA words row by row from the top" {
	const decoded: Result<Pixels, ImageError> = decodeImage(rgbaPng());
	assert decoded.ok;
	if (!decoded.ok) { return; }
	const image: Pixels = decoded.value;
	assert image.width == 2 && image.height == 2;
	assert (image.pixels.length as int32) == 4;
	assert image.pixels[0] == (0xFF0000FF as uint32);
	assert image.pixels[1] == (0xFF00FF00 as uint32);
	assert image.pixels[2] == (0xFFFF0000 as uint32);
	assert image.pixels[3] == (0x8000FFFF as uint32);
}

test "palette, 16-bit and grey-alpha PNGs all come out as RGBA8" {
	const indexed = decodeImage(pngOf(3, 1, 8, COLOR_PALETTE, bytesOf([1, 0, 1]), 3,
		bytesOf([10, 20, 30, 40, 50, 60])));
	assert indexed.ok;
	if (indexed.ok) {
		assert indexed.value.pixels[0] == (0xFF3C3228 as uint32);
		assert indexed.value.pixels[1] == (0xFF1E140A as uint32);
		assert indexed.value.pixels[2] == (0xFF3C3228 as uint32);
	}
	const deep = decodeImage(pngOf(1, 1, 16, COLOR_RGB, bytesOf([255, 255, 128, 0, 0, 0]), 6, []));
	assert deep.ok;
	if (deep.ok) { assert deep.value.pixels[0] == (0xFF0080FF as uint32); }
	const grey = decodeImage(pngOf(1, 1, 8, COLOR_GREY_ALPHA, bytesOf([100, 200]), 2, []));
	assert grey.ok;
	if (grey.ok) { assert grey.value.pixels[0] == (0xC8646464 as uint32); }
}

test "decodeImage reads a JPEG, its left block left" {
	const jpeg: Vec<uint8> = twoBlockJpeg();
	const format = imageFormatOf(jpeg);
	assert format.ok;
	if (format.ok) { assert format.value == ImageFormat.Jpeg; }
	const decoded = decodeImage(jpeg);
	assert decoded.ok;
	if (!decoded.ok) { return; }
	assert decoded.value.width == 16 && decoded.value.height == 8;
	assert near(decoded.value.pixels[3 * 16 + 3], 200, 100, 50);
	assert near(decoded.value.pixels[3 * 16 + 12], 40, 160, 220);
}

test "what is not PNG or JPEG, what does not decode and what is too large say which" {
	const gif = decodeImage(bytesOf([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 1, 0, 1, 0]));
	assert !gif.ok;
	if (!gif.ok) { assert gif.error == ImageError.NotPngOrJpeg; }
	const nothing = decodeImage([]);
	assert !nothing.ok;
	if (!nothing.ok) { assert nothing.error == ImageError.NotPngOrJpeg; }
	const signatureOnly = decodeImage(bytesOf([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]));
	assert !signatureOnly.ok;
	if (!signatureOnly.ok) { assert signatureOnly.error == ImageError.Undecodable; }
	const jpegHead = decodeImage(bytesOf([0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 1, 2, 3]));
	assert !jpegHead.ok;
	if (!jpegHead.ok) { assert jpegHead.error == ImageError.Undecodable; }
	let truncated: Vec<uint8> = rgbaPng();
	const cut: int32 = (truncated.length as int32) - 20;
	let shorter: Vec<uint8> = [];
	for (let i = 0; i < cut; i++) { shorter.push(truncated[i]); }
	const broken = decodeImage(shorter);
	assert !broken.ok;
	if (!broken.ok) { assert broken.error == ImageError.Undecodable; }
	const wide = decodeImage(pngOf(16385, 1, 8, COLOR_GREY_ALPHA, [], 0, []));
	assert !wide.ok;
	if (!wide.ok) { assert wide.error == ImageError.TooLarge; }
}

test "a refused image after a decoded one answers its own refusal and nothing stale" {
	const first = decodeImage(rgbaPng());
	assert first.ok;
	const refused = decodeImage(bytesOf([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]));
	assert !refused.ok;
	const jpeg = decodeImage(twoBlockJpeg());
	assert jpeg.ok;
	if (jpeg.ok) { assert jpeg.value.width == 16 && jpeg.value.height == 8; }
	const again = decodeImage(rgbaPng());
	assert again.ok;
	if (again.ok) { assert again.value.width == 2 && (again.value.pixels.length as int32) == 4; }
}
