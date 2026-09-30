import { decodeImage, imageFormatOf, ImageError, ImageFormat, Pixels } from "../assets/image";
import {
	COLOR_GREY_ALPHA,
	COLOR_RGB,
	COLOR_PALETTE,
	bytesOf,
	pngOf,
	rgbaPng,
	twoBlockJpeg,
} from "./imageBytes";

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
