// Void Asset — Image loading (PNG, JPEG via stb_image)
// C/POSIX backend — sync file I/O via stb_image.

import {
	void_load_image, void_image_width, void_image_height, void_free_image
} from "./image.h";

extern function void_image_size(bytes: Readonly<Span<uint8>>): int64;
extern function void_decode_image(bytes: Readonly<Span<uint8>>, pixels: Span<uint32>): int32;

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
