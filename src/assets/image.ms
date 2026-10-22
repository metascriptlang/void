// Void Asset — Image loading (PNG, JPEG via stb_image)
// C/POSIX backend — sync file I/O via stb_image.

import {
	void_load_image, void_image_width, void_image_height, void_free_image
} from "./image.h";
import {
	ImageFormat, ImageError, Pixels, DecodedAnimation, imageFormatOf, isGif,
	MAX_IMAGE_SIDE, MAX_ENCODED_LENGTH, MAX_ANIMATION_BYTES, gifDelayMs,
} from "./imageTypes";
export {
	ImageFormat, ImageError, Pixels, DecodedAnimation, imageFormatOf, gifDelayMs,
} from "./imageTypes";

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
