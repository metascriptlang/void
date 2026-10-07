// Void Asset — Image loading (PNG, JPEG via stb_image)
// C/POSIX backend — sync file I/O via stb_image.

import {
	void_load_image, void_image_width, void_image_height, void_free_image
} from "./image.h";

extern function void_image_size(bytes: Readonly<Span<uint8>>): int64;
extern function void_decode_image(bytes: Readonly<Span<uint8>>, pixels: Span<uint32>): int32;
extern function void_gif_scan(bytes: Readonly<Span<uint8>>): int64;
extern function void_decode_gif(
	bytes: Readonly<Span<uint8>>, pixels: Span<uint32>, delays: Span<int32>,
): int32;

export async function loadImage(path: string, channels: int32): Promise<Ptr<void>> {
	return void_load_image(path, channels);
}

export function loadImageSync(path: string, channels: int32): Ptr<void> {
	return void_load_image(path, channels);
}

export function imageWidth(): int32 {
	return void_image_width();
}

export function imageHeight(): int32 {
	return void_image_height();
}

export function freeImage(data: Ptr<void>): void {
	void_free_image(data);
}

export enum ImageFormat {
	Png,
	Jpeg,
}

export enum ImageError {
	NotPngOrJpeg,
	Undecodable,
	TooLarge,
	NotGif,
	UnsupportedDisposal,
}

// hxd.Pixels, RGBA8: one 0xAABBGGRR word per pixel, row by row from the top.
export struct Pixels {
	pixels: Vec<uint32>;
	width: int32;
	height: int32;
}

// D3D11_REQ_TEXTURE2D_U_OR_V_DIMENSION: no backend here can draw a longer side.
const MAX_IMAGE_SIDE: int32 = 16384;
const MAX_ENCODED_LENGTH: int64 = 2147483647;

function isPng(bytes: Readonly<Span<uint8>>): boolean {
	return bytes.length >= 8
		&& bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47
		&& bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A;
}

function isJpeg(bytes: Readonly<Span<uint8>>): boolean {
	return bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
}

// By the first bytes, as hxd.res.Image.getInfo does, with the signatures glTF 2.0 lists
// for image/png and image/jpeg.
export function imageFormatOf(bytes: Readonly<Span<uint8>>): Result<ImageFormat, ImageError> {
	if (isPng(bytes)) { return Result.ok(ImageFormat.Png); }
	if (isJpeg(bytes)) { return Result.ok(ImageFormat.Jpeg); }
	return Result.err(ImageError.NotPngOrJpeg);
}

export function decodeImage(bytes: Readonly<Span<uint8>>): Result<Pixels, ImageError> {
	const _format: ImageFormat = try imageFormatOf(bytes);
	if ((bytes.length as int64) > MAX_ENCODED_LENGTH) { return Result.err(ImageError.TooLarge); }
	const size: int64 = void_image_size(bytes);
	if (size < 0) { return Result.err(ImageError.Undecodable); }
	const width: int32 = (size >> (32 as int64)) as int32;
	const height: int32 = (size & (0xFFFFFFFF as int64)) as int32;
	if (width <= 0 || height <= 0) { return Result.err(ImageError.Undecodable); }
	if (width > MAX_IMAGE_SIDE || height > MAX_IMAGE_SIDE) {
		return Result.err(ImageError.TooLarge);
	}
	let pixels: Vec<uint32> = new Array(width * height);
	if (void_decode_image(bytes, pixels) == 0) { return Result.err(ImageError.Undecodable); }
	return Result.ok({ pixels: pixels, width: width, height: height });
}

// Every frame is the whole canvas, composed by stb_image, one frame after another in `pixels`.
// `delays` are milliseconds.
export struct DecodedAnimation {
	pixels: Vec<uint32>;
	delays: Vec<int32>;
	width: int32;
	height: int32;
	frameCount: int32;
}

const MAX_ANIMATION_BYTES: int64 = 268435456;
const BROWSER_MIN_DELAY_MS: int32 = 10;
const BROWSER_DEFAULT_DELAY_MS: int32 = 100;

function isGif(bytes: Readonly<Span<uint8>>): boolean {
	return bytes.length >= 6
		&& bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38
		&& (bytes[4] == 0x37 || bytes[4] == 0x39) && bytes[5] == 0x61;
}

export function gifDelayMs(milliseconds: int32): int32 {
	return milliseconds <= BROWSER_MIN_DELAY_MS ? BROWSER_DEFAULT_DELAY_MS : milliseconds;
}

// Disposal method 3 is refused: stb_image reads its "two frames back" canvas from before the
// start of its output buffer. Method 2 restores the canvas as it was before the frame, where
// a browser shows the transparent background.
export function decodeAnimation(
	bytes: Readonly<Span<uint8>>,
): Result<DecodedAnimation, ImageError> {
	if (!isGif(bytes)) { return Result.err(ImageError.NotGif); }
	if ((bytes.length as int64) > MAX_ENCODED_LENGTH) { return Result.err(ImageError.TooLarge); }
	const scan: int64 = void_gif_scan(bytes);
	if (scan == (-2 as int64)) { return Result.err(ImageError.UnsupportedDisposal); }
	if (scan < 0) { return Result.err(ImageError.Undecodable); }
	const width: int32 = ((scan >> (44 as int64)) & (0xFFFF as int64)) as int32;
	const height: int32 = ((scan >> (28 as int64)) & (0xFFFF as int64)) as int32;
	const frameCount: int32 = (scan & (0xFFFFFFF as int64)) as int32;
	if (width > MAX_IMAGE_SIDE || height > MAX_IMAGE_SIDE) {
		return Result.err(ImageError.TooLarge);
	}
	const bytesNeeded: int64 = (width as int64) * (height as int64) * (frameCount as int64) * 4;
	if (bytesNeeded > MAX_ANIMATION_BYTES) { return Result.err(ImageError.TooLarge); }
	let pixels: Vec<uint32> = new Array(width * height * frameCount);
	let delays: Vec<int32> = new Array(frameCount);
	if (void_decode_gif(bytes, pixels, delays) == 0) { return Result.err(ImageError.Undecodable); }
	for (let i: int32 = 0; i < frameCount; i++) { delays[i] = gifDelayMs(delays[i]); }
	return Result.ok({
		pixels: pixels, delays: delays, width: width, height: height, frameCount: frameCount,
	});
}
