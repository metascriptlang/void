// Void Asset — image formats, errors and pixels, alike on every target.

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
	NoDecoderOnJs,
}

// hxd.Pixels, RGBA8: one 0xAABBGGRR word per pixel, row by row from the top.
export struct Pixels {
	pixels: Vec<uint32>;
	width: int32;
	height: int32;
}

// D3D11_REQ_TEXTURE2D_U_OR_V_DIMENSION: no backend here can draw a longer side.
export const MAX_IMAGE_SIDE: int32 = 16384;
export const MAX_ENCODED_LENGTH: int64 = 2147483647;

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

// Every frame is the whole canvas, composed by stb_image, one frame after another in `pixels`.
// `delays` are milliseconds.
export struct DecodedAnimation {
	pixels: Vec<uint32>;
	delays: Vec<int32>;
	width: int32;
	height: int32;
	frameCount: int32;
}

export const MAX_ANIMATION_BYTES: int64 = 268435456;
const BROWSER_MIN_DELAY_MS: int32 = 10;
const BROWSER_DEFAULT_DELAY_MS: int32 = 100;

export function isGif(bytes: Readonly<Span<uint8>>): boolean {
	return bytes.length >= 6
		&& bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38
		&& (bytes[4] == 0x37 || bytes[4] == 0x39) && bytes[5] == 0x61;
}

export function gifDelayMs(milliseconds: int32): int32 {
	return milliseconds <= BROWSER_MIN_DELAY_MS ? BROWSER_DEFAULT_DELAY_MS : milliseconds;
}
