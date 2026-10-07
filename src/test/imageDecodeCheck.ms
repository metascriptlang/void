import {
	decodeImage, decodeAnimation, imageFormatOf, ImageError, ImageFormat, Pixels, DecodedAnimation,
} from "../assets/image";
import {
	COLOR_GREY_ALPHA,
	COLOR_RGB,
	COLOR_PALETTE,
	bytesOf,
	pngOf,
	rgbaPng,
	twoBlockJpeg,
	GifFrame,
	animatedGif,
	solidFrame,
	GIF_RED,
	GIF_GREEN,
	GIF_BLUE,
	GIF_YELLOW,
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

function fourFrames(): Vec<GifFrame> {
	const patch: GifFrame = {
		x: 1, y: 1, w: 2, h: 1, indices: bytesOf([2, 2]), delayCentiseconds: 5, disposal: 2,
	};
	const corner: GifFrame = {
		x: 0, y: 0, w: 1, h: 1, indices: bytesOf([3]), delayCentiseconds: 1, disposal: 1,
	};
	return [solidFrame(4, 3, 0, 10), solidFrame(4, 3, 1, 20), patch, corner];
}

function frameWord(animation: DecodedAnimation, frame: int32, x: int32, y: int32): uint32 {
	return animation.pixels[frame * animation.width * animation.height + y * animation.width + x];
}

test "decodeAnimation reads every frame of a GIF as the whole canvas, straight RGBA" {
	const decoded = decodeAnimation(animatedGif(0x39, 4, 3, fourFrames()));
	assert decoded.ok;
	if (!decoded.ok) { return; }
	const a: DecodedAnimation = decoded.value;
	assert a.width == 4 && a.height == 3 && a.frameCount == 4;
	assert (a.pixels.length as int32) == 4 * 3 * 4;
	for (let i = 0; i < 12; i++) {
		assert a.pixels[i] == GIF_RED;
		assert a.pixels[12 + i] == GIF_GREEN;
	}
	assert frameWord(a, 2, 0, 0) == GIF_GREEN;
	assert frameWord(a, 2, 1, 1) == GIF_BLUE;
	assert frameWord(a, 2, 2, 1) == GIF_BLUE;
	assert frameWord(a, 2, 3, 1) == GIF_GREEN;
}

test "a frame's disposal 2 restores the canvas as it was before that frame, as stb does" {
	const decoded = decodeAnimation(animatedGif(0x39, 4, 3, fourFrames()));
	assert decoded.ok;
	if (!decoded.ok) { return; }
	const a: DecodedAnimation = decoded.value;
	assert frameWord(a, 3, 0, 0) == GIF_YELLOW;
	assert frameWord(a, 3, 1, 1) == GIF_GREEN;
	assert frameWord(a, 3, 2, 1) == GIF_GREEN;
	assert frameWord(a, 3, 3, 2) == GIF_GREEN;
}

test "delays come out in milliseconds and a delay of 10 ms or less plays as 100 ms" {
	const decoded = decodeAnimation(animatedGif(0x39, 4, 3, fourFrames()));
	assert decoded.ok;
	if (!decoded.ok) { return; }
	assert (decoded.value.delays.length as int32) == 4;
	assert decoded.value.delays[0] == 100;
	assert decoded.value.delays[1] == 200;
	assert decoded.value.delays[2] == 50;
	assert decoded.value.delays[3] == 100;
	const zero = decodeAnimation(animatedGif(0x39, 2, 2, [solidFrame(2, 2, 0, 0)]));
	assert zero.ok;
	if (zero.ok) { assert zero.value.delays[0] == 100; }
}

test "a GIF87a and a one-frame GIF decode, and a still PNG is not an animation" {
	const old = decodeAnimation(animatedGif(0x37, 2, 2, [solidFrame(2, 2, 3, 10)]));
	assert old.ok;
	if (old.ok) {
		assert old.value.frameCount == 1;
		assert old.value.pixels[3] == GIF_YELLOW;
	}
	const png = decodeAnimation(rgbaPng());
	assert !png.ok;
	if (!png.ok) { assert png.error == ImageError.NotGif; }
	const nothing = decodeAnimation([]);
	assert !nothing.ok;
	if (!nothing.ok) { assert nothing.error == ImageError.NotGif; }
}

test "a truncated GIF and a GIF with no frame each say which" {
	const whole: Vec<uint8> = animatedGif(0x39, 4, 3, fourFrames());
	for (const cutBy of [1, 7, 30]) {
		let shorter: Vec<uint8> = [];
		for (let i = 0; i < (whole.length as int32) - cutBy; i++) { shorter.push(whole[i]); }
		const broken = decodeAnimation(shorter);
		assert !broken.ok;
		if (!broken.ok) { assert broken.error == ImageError.Undecodable; }
	}
	const empty = decodeAnimation(animatedGif(0x39, 4, 3, []));
	assert !empty.ok;
	if (!empty.ok) { assert empty.error == ImageError.Undecodable; }
}

function withDisposal(frame: GifFrame, disposal: int32): GifFrame {
	let changed: GifFrame = frame;
	changed.disposal = disposal;
	return changed;
}

test "disposal 3 on a frame that stb restores from the wrong image is refused by name" {
	const frames: GifFrame[] = [
		solidFrame(4, 3, 0, 10), withDisposal(solidFrame(4, 3, 1, 10), 3), solidFrame(4, 3, 2, 10),
	];
	const three = decodeAnimation(animatedGif(0x39, 4, 3, frames));
	assert !three.ok;
	if (!three.ok) { assert three.error == ImageError.UnsupportedDisposal; }
}

test "disposal 3 that stb never runs on the last frame, or defaults on the first, decodes" {
	const last = decodeAnimation(animatedGif(0x39, 4, 3, [
		solidFrame(4, 3, 0, 10), withDisposal(solidFrame(4, 3, 1, 10), 3),
	]));
	assert last.ok;
	if (last.ok) { assert last.value.frameCount == 2; }
	const first = decodeAnimation(animatedGif(0x39, 4, 3, [
		withDisposal(solidFrame(4, 3, 0, 10), 3), solidFrame(4, 3, 1, 10),
	]));
	assert first.ok;
	if (first.ok) { assert first.value.frameCount == 2; }
}

test "a graphics control block of five bytes refuses the GIF, though its sub-blocks parse" {
	const whole: Vec<uint8> = animatedGif(0x39, 4, 3, fourFrames());
	assert whole[25] == (0x21 as uint8) && whole[26] == (0xF9 as uint8);
	assert whole[27] == (4 as uint8);
	let tampered: Vec<uint8> = [];
	for (let i = 0; i < (whole.length as int32); i++) {
		tampered.push(i == 27 ? (5 as uint8) : whole[i]);
		if (i == 31) { tampered.push(0 as uint8); }
	}
	const decoded = decodeAnimation(tampered);
	assert !decoded.ok;
	if (!decoded.ok) { assert decoded.error == ImageError.Undecodable; }
}

test "a corrupt later frame refuses the animation instead of playing the frames before it" {
	const corrupt: GifFrame = {
		x: 0, y: 0, w: 1, h: 1, indices: bytesOf([7]), delayCentiseconds: 10, disposal: 1,
	};
	const decoded = decodeAnimation(animatedGif(0x39, 4, 3, [solidFrame(4, 3, 0, 10), corrupt]));
	assert !decoded.ok;
	if (!decoded.ok) { assert decoded.error == ImageError.Undecodable; }
}

test "a GIF whose canvas is too large for all its frames is refused before it is decoded" {
	const corner: GifFrame = {
		x: 0, y: 0, w: 1, h: 1, indices: bytesOf([0]), delayCentiseconds: 10, disposal: 1,
	};
	const huge = decodeAnimation(animatedGif(0x39, 16384, 16384, [corner, corner]));
	assert !huge.ok;
	if (!huge.ok) { assert huge.error == ImageError.TooLarge; }
}

test "decodeImage still refuses a GIF, which is not a still-image format here" {
	const gif = decodeImage(animatedGif(0x39, 2, 2, [solidFrame(2, 2, 0, 10)]));
	assert !gif.ok;
	if (!gif.ok) { assert gif.error == ImageError.NotPngOrJpeg; }
}
