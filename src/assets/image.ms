// Void Asset — image decoding (PNG and JPEG through stb_image's paths, GIF animations), alike on
// every target.

import { decodeGif, gifScan, GifScanError } from "./gif";
import { decodeJpeg, jpegInfo } from "./jpeg";
import { decodePng, pngInfo } from "./png";
import {
	ImageFormat, ImageError, Pixels, DecodedAnimation, imageFormatOf, isGif,
	MAX_IMAGE_SIDE, MAX_ENCODED_LENGTH, MAX_ANIMATION_BYTES, gifDelayMs,
} from "./imageTypes";
export {
	ImageFormat, ImageError, Pixels, DecodedAnimation, imageFormatOf, gifDelayMs,
} from "./imageTypes";

// STBI_MAX_DIMENSIONS.
const STB_MAX_DIMENSIONS: int32 = 1 << 24;

function packRgba(rgba: Readonly<Span<uint8>>): Vec<uint32> {
	const count = rgba.length / 4;
	let pixels: Vec<uint32> = new Array(count);
	for (let i: int32 = 0; i < count; i++) {
		const at = i * 4;
		pixels[i] = (rgba[at] as uint32) | ((rgba[at + 1] as uint32) << 8)
			| ((rgba[at + 2] as uint32) << 16) | ((rgba[at + 3] as uint32) << 24);
	}
	return pixels;
}

export function decodeImage(bytes: Readonly<Span<uint8>>): Result<Pixels, ImageError> {
	const format: ImageFormat = try imageFormatOf(bytes);
	if ((bytes.length as int64) > MAX_ENCODED_LENGTH) { return Result.err(ImageError.TooLarge); }
	let width: int32;
	let height: int32;
	if (format == ImageFormat.Png) {
		const info = pngInfo(bytes, STB_MAX_DIMENSIONS);
		if (!info.ok) { return Result.err(ImageError.Undecodable); }
		width = info.value.width;
		height = info.value.height;
	} else {
		const info = jpegInfo(bytes, STB_MAX_DIMENSIONS);
		if (!info.ok) { return Result.err(ImageError.Undecodable); }
		width = info.value.width;
		height = info.value.height;
	}
	if (width <= 0 || height <= 0) { return Result.err(ImageError.Undecodable); }
	if (width > MAX_IMAGE_SIDE || height > MAX_IMAGE_SIDE) {
		return Result.err(ImageError.TooLarge);
	}
	let packed: Vec<uint32>;
	if (format == ImageFormat.Png) {
		const decoded = decodePng(bytes, 4, MAX_IMAGE_SIDE);
		if (!decoded.ok) { return Result.err(ImageError.Undecodable); }
		if (decoded.value.pixels.length != width * height * 4) {
			return Result.err(ImageError.Undecodable);
		}
		packed = packRgba(decoded.value.pixels);
	} else {
		const decoded = decodeJpeg(bytes, 4, MAX_IMAGE_SIDE);
		if (!decoded.ok) { return Result.err(ImageError.Undecodable); }
		if (decoded.value.pixels.length != width * height * 4) {
			return Result.err(ImageError.Undecodable);
		}
		packed = packRgba(decoded.value.pixels);
	}
	return Result.ok({ pixels: move packed, width: width, height: height });
}

// Disposal method 3 is refused: stb_image reads its "two frames back" canvas from before the
// start of its output buffer. Method 2 restores the canvas as it was before the frame, where
// a browser shows the transparent background.
export function decodeAnimation(
	bytes: Readonly<Span<uint8>>,
): Result<DecodedAnimation, ImageError> {
	if (!isGif(bytes)) { return Result.err(ImageError.NotGif); }
	if ((bytes.length as int64) > MAX_ENCODED_LENGTH) { return Result.err(ImageError.TooLarge); }
	const scan = gifScan(bytes);
	if (!scan.ok) {
		const refused = scan.error == GifScanError.Disposal3;
		return Result.err(refused ? ImageError.UnsupportedDisposal : ImageError.Undecodable);
	}
	const width = scan.value.width;
	const height = scan.value.height;
	const frameCount = scan.value.frameCount;
	if (width > MAX_IMAGE_SIDE || height > MAX_IMAGE_SIDE) {
		return Result.err(ImageError.TooLarge);
	}
	const bytesNeeded: int64 = (width as int64) * (height as int64) * (frameCount as int64) * 4;
	if (bytesNeeded > MAX_ANIMATION_BYTES) { return Result.err(ImageError.TooLarge); }
	const decoded = decodeGif(bytes, MAX_IMAGE_SIDE);
	if (!decoded.ok) { return Result.err(ImageError.Undecodable); }
	let frames = decoded.value;
	if (frames.width != width || frames.height != height || frames.frameCount != frameCount) {
		return Result.err(ImageError.Undecodable);
	}
	let delays: Vec<int32> = move frames.delays;
	for (let i: int32 = 0; i < frameCount; i++) { delays[i] = gifDelayMs(delays[i]); }
	return Result.ok({
		pixels: move frames.pixels, delays: delays, width: width, height: height,
		frameCount: frameCount,
	});
}
