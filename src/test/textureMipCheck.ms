import { FilterMode, Wrap } from "../gpu/state";
import {
	TextureMipLevel,
	TextureMipData,
	TextureMipError,
	TextureMipFilter,
	TextureSampler2D,
	TextureSamplerError,
	replaceTextureMip,
} from "../void3d/textureMip";

function sampling(mip: TextureMipFilter, lastLod: float32): TextureSampler2D {
	return {
		minFilter: FilterMode.Linear,
		magFilter: FilterMode.Nearest,
		mipFilter: mip,
		wrapU: Wrap.Repeat,
		wrapV: Wrap.Clamp,
		minLod: 0.0,
		maxLod: lastLod,
		maxAnisotropy: 1,
	};
}

function squareLevels(): Vec<TextureMipLevel> {
	return [
		{ width: 4, height: 4, pixelOffset: 0, pixelCount: 16 },
		{ width: 2, height: 2, pixelOffset: 16, pixelCount: 4 },
		{ width: 1, height: 1, pixelOffset: 20, pixelCount: 1 },
	];
}

function rectangularLevels(): Vec<TextureMipLevel> {
	return [
		{ width: 7, height: 3, pixelOffset: 0, pixelCount: 21 },
		{ width: 3, height: 1, pixelOffset: 21, pixelCount: 3 },
		{ width: 1, height: 1, pixelOffset: 24, pixelCount: 1 },
	];
}

function colours(firstCount: int32, secondCount: int32): Vec<uint32> {
	let pixels: Vec<uint32> = [];
	for (let i = 0; i < firstCount; i++) { pixels.push(0xFF0000FF); }
	for (let i = 0; i < secondCount; i++) { pixels.push(0xFF00FF00); }
	pixels.push(0xFFFF0000);
	return move pixels;
}

function mipError(result: Result<TextureMipData, TextureMipError>): TextureMipError {
	if (result.ok) { unreachable; }
	return result.error;
}

function samplerError(result: Result<void, TextureSamplerError>): TextureSamplerError {
	if (result.ok) { unreachable; }
	return result.error;
}

test "textureMip owns every colour-coded supplied square mip and its offsets" {
	let levels: Vec<TextureMipLevel> = squareLevels();
	let pixels: Vec<uint32> = colours(16, 4);
	const made: Result<TextureMipData, TextureMipError> = TextureMipData.create(
		levels, pixels, sampling(TextureMipFilter.Nearest, 2.0),
	);
	assert made.ok;
	if (!made.ok) { return; }
	let data: TextureMipData = made.value;
	assert data.levels.length == 3 && data.pixels.length == 21;
	assert data.levels[1].pixelOffset == 16 && data.levels[2].pixelOffset == 20;
	assert data.levels[1].byteOffset() == 64 && data.levels[2].byteCount() == 4;
	assert data.pixels[0] == 0xFF0000FF && data.pixels[15] == 0xFF0000FF;
	assert data.pixels[16] == 0xFF00FF00 && data.pixels[19] == 0xFF00FF00;
	assert data.pixels[20] == 0xFFFF0000;
	pixels[20] = 0;
	levels[2].pixelOffset = 0;
	assert data.pixels[20] == 0xFFFF0000 && data.levels[2].pixelOffset == 20;
	let copied: TextureMipData = data;
	copied.pixels[0] = 0;
	copied.levels[0].width = 1;
	assert data.pixels[0] == 0xFF0000FF && data.levels[0].width == 4;
}

test "textureMip NPOT rectangle floors each axis and keeps its one-row tail" {
	const levels: Vec<TextureMipLevel> = rectangularLevels();
	const pixels: Vec<uint32> = colours(21, 3);
	const made: Result<TextureMipData, TextureMipError> = TextureMipData.create(
		levels, pixels, sampling(TextureMipFilter.Linear, 2.0),
	);
	assert made.ok;
	if (!made.ok) { return; }
	const data: TextureMipData = made.value;
	assert data.levels[0].width == 7 && data.levels[0].height == 3;
	assert data.levels[1].width == 3 && data.levels[1].height == 1;
	assert data.levels[2].width == 1 && data.levels[2].height == 1;
	assert data.levels[2].byteOffset() == 96;
	assert data.pixels[20] == 0xFF0000FF && data.pixels[21] == 0xFF00FF00;
	assert data.pixels[23] == 0xFF00FF00 && data.pixels[24] == 0xFFFF0000;
}

test "textureMip late malformed data refuses replacement atomically for both chains" {
	const samplers: Vec<TextureSampler2D> = [
		sampling(TextureMipFilter.Nearest, 2.0),
		sampling(TextureMipFilter.Linear, 2.0),
	];
	for (let variant = 0; variant < 2; variant++) {
		let levels: Vec<TextureMipLevel> = variant == 0 ? squareLevels() : rectangularLevels();
		let pixels: Vec<uint32> = variant == 0 ? colours(16, 4) : colours(21, 3);
		const made: Result<TextureMipData, TextureMipError> =
			TextureMipData.create(levels, pixels, samplers[variant]);
		assert made.ok;
		if (!made.ok) { return; }
		let published: TextureMipData = made.value;
		pixels[0] = 0;
		pixels.pop();
		const refused: Result<void, TextureMipError> =
			replaceTextureMip(published, levels, pixels, samplers[variant]);
		assert !refused.ok && refused.error == TextureMipError.PixelExtent;
		assert published.pixels[0] == 0xFF0000FF;
		assert published.pixels[published.pixels.length - 1] == 0xFFFF0000;
		assert published.levels[2].pixelCount == 1;
		assert published.sampler.sameSampling(samplers[variant]);
	}
}

test "textureMip refuses missing repeated or wrongly rounded levels without repair" {
	let levels: Vec<TextureMipLevel> = squareLevels();
	const pixels: Vec<uint32> = colours(16, 4);
	levels.pop();
	assert mipError(TextureMipData.create(levels, pixels,
		sampling(TextureMipFilter.Nearest, 2.0))) == TextureMipError.IncompleteChain;
	levels = squareLevels();
	levels.push({ width: 1, height: 1, pixelOffset: 21, pixelCount: 1 });
	assert mipError(TextureMipData.create(levels, pixels,
		sampling(TextureMipFilter.Linear, 2.0))) == TextureMipError.IncompleteChain;
	levels = rectangularLevels();
	levels[1].width = 4;
	assert mipError(TextureMipData.create(levels, colours(21, 3),
		sampling(TextureMipFilter.Linear, 2.0))) == TextureMipError.LevelDimensions;
}

test "textureMip checks every offset count and trailing extent" {
	let levels: Vec<TextureMipLevel> = squareLevels();
	let pixels: Vec<uint32> = colours(16, 4);
	const sampler: TextureSampler2D = sampling(TextureMipFilter.Nearest, 2.0);
	levels[2].pixelOffset = -1;
	assert mipError(TextureMipData.create(levels, pixels, sampler)) == TextureMipError.PixelOffset;
	levels[2].pixelOffset = 19;
	assert mipError(TextureMipData.create(levels, pixels, sampler)) == TextureMipError.PixelOffset;
	levels[2].pixelOffset = 21;
	assert mipError(TextureMipData.create(levels, pixels, sampler)) == TextureMipError.PixelOffset;
	levels[2].pixelOffset = 2147483647;
	assert mipError(TextureMipData.create(levels, pixels, sampler)) == TextureMipError.PixelOffset;
	levels = squareLevels();
	levels[2].pixelCount = 2;
	assert mipError(TextureMipData.create(levels, pixels, sampler)) == TextureMipError.PixelCount;
	levels[2].pixelCount = -1;
	assert mipError(TextureMipData.create(levels, pixels, sampler)) == TextureMipError.PixelCount;
	levels = squareLevels();
	pixels.push(0);
	const trailing = TextureMipData.create(levels, pixels, sampler);
	assert !trailing.ok && trailing.error == TextureMipError.PixelExtent;
}

test "textureMip rejects nonpositive overflow-sized and excessive descriptor shapes" {
	const sampler: TextureSampler2D = sampling(TextureMipFilter.None, 0.0);
	const empty: Vec<TextureMipLevel> = [];
	const pixels: Vec<uint32> = [0];
	assert mipError(TextureMipData.create(empty, pixels, sampler)) == TextureMipError.EmptyChain;
	let levels: Vec<TextureMipLevel> = [
		{ width: 0, height: 1, pixelOffset: 0, pixelCount: 1 },
	];
	assert mipError(TextureMipData.create(levels, pixels, sampler)) ==
		TextureMipError.LevelDimensions;
	levels[0].width = -1;
	assert mipError(TextureMipData.create(levels, pixels, sampler)) ==
		TextureMipError.LevelDimensions;
	levels[0].width = 2147483647;
	levels[0].height = 2147483647;
	assert mipError(TextureMipData.create(levels, pixels, sampler)) == TextureMipError.ByteExtent;
	levels = [];
	for (let i = 0; i < 17; i++) {
		levels.push({ width: 1, height: 1, pixelOffset: i, pixelCount: 1 });
	}
	assert mipError(TextureMipData.create(levels, pixels, sampler)) ==
		TextureMipError.TooManyLevels;
}

test "textureMip no-mip fixes LOD0 and accepts only base or complete supplied storage" {
	const sampler: TextureSampler2D = sampling(TextureMipFilter.None, 0.0);
	const base: Vec<TextureMipLevel> = [
		{ width: 4, height: 4, pixelOffset: 0, pixelCount: 16 },
	];
	const pixels: Vec<uint32> = new Array(16);
	assert TextureMipData.create(base, pixels, sampler).ok;
	assert TextureMipData.create(squareLevels(), colours(16, 4), sampler).ok;
	assert sampler.admitPortable(1).ok;
	const wrongLod: TextureSampler2D = { ...sampler, maxLod: 1.0 };
	assert samplerError(wrongLod.validate(3)) == TextureSamplerError.NoMipLod;
	assert mipError(TextureMipData.create(base, pixels,
		sampling(TextureMipFilter.Nearest, 0.0))) == TextureMipError.IncompleteChain;
	const tiny: Vec<TextureMipLevel> = [
		{ width: 1, height: 1, pixelOffset: 0, pixelCount: 1 },
	];
	const tinyPixels: Vec<uint32> = [0xFFFFFFFF];
	assert TextureMipData.create(tiny, tinyPixels, sampling(TextureMipFilter.Linear, 0.0)).ok;
}

test "textureMip sampler identity distinguishes mip V wrap and every supported field" {
	const base: TextureSampler2D = sampling(TextureMipFilter.Nearest, 2.0);
	const variants: Vec<TextureSampler2D> = [
		{ ...base, minFilter: FilterMode.Nearest },
		{ ...base, magFilter: FilterMode.Linear },
		{ ...base, mipFilter: TextureMipFilter.Linear },
		{ ...base, wrapU: Wrap.Mirror },
		{ ...base, wrapV: Wrap.Repeat },
		{ ...base, minLod: 0.5 },
		{ ...base, maxLod: 1.5 },
	];
	assert base.sameSampling(base) && base == base;
	for (const variant of variants) {
		assert variant.validate(3).ok;
		assert !base.sameSampling(variant) && !variant.sameSampling(base);
		assert base != variant;
	}
	const linear: TextureSampler2D = {
		...base, magFilter: FilterMode.Linear, mipFilter: TextureMipFilter.Linear,
	};
	const two: TextureSampler2D = { ...linear, maxAnisotropy: 2 };
	const sixteen: TextureSampler2D = { ...linear, maxAnisotropy: 16 };
	assert linear.validate(3).ok && two.validate(3).ok && sixteen.validate(3).ok;
	const twoData: Result<TextureMipData, TextureMipError> =
		TextureMipData.create(squareLevels(), colours(16, 4), two);
	const sixteenData: Result<TextureMipData, TextureMipError> =
		TextureMipData.create(squareLevels(), colours(16, 4), sixteen);
	assert twoData.ok && sixteenData.ok;
	if (!twoData.ok || !sixteenData.ok) { return; }
	assert twoData.value.sampler.maxAnisotropy == 2;
	assert sixteenData.value.sampler.maxAnisotropy == 16;
	assert !linear.sameSampling(two) && !two.sameSampling(sixteen);
	assert linear != two && two != sixteen && linear != sixteen;
	assert linear.admitPortable(3).ok;
	assert samplerError(two.admitPortable(3)) == TextureSamplerError.AnisotropyNeedsCapability;
	assert samplerError(sixteen.admitPortable(3)) == TextureSamplerError.AnisotropyNeedsCapability;
}

test "textureMip names unsupported anisotropy filtering and LOD requests" {
	const base: TextureSampler2D = sampling(TextureMipFilter.Linear, 2.0);
	const nonlinear: TextureSampler2D = { ...base, maxAnisotropy: 2 };
	assert samplerError(nonlinear.validate(3)) == TextureSamplerError.NonlinearAnisotropy;
	const zero: TextureSampler2D = { ...base, maxAnisotropy: 0 };
	const seventeen: TextureSampler2D = { ...base, maxAnisotropy: 17 };
	assert samplerError(zero.validate(3)) == TextureSamplerError.AnisotropyRange;
	assert samplerError(seventeen.validate(3)) == TextureSamplerError.AnisotropyRange;
	const reversed: TextureSampler2D = { ...base, minLod: 2.0, maxLod: 1.0 };
	const negative: TextureSampler2D = { ...base, minLod: -0.5 };
	const nan: TextureSampler2D = { ...base, maxLod: Number.NaN as float32 };
	const infinite: TextureSampler2D = { ...base, maxLod: Number.POSITIVE_INFINITY as float32 };
	const past: TextureSampler2D = { ...base, maxLod: 3.0 };
	assert samplerError(reversed.validate(3)) == TextureSamplerError.LodRange;
	assert samplerError(negative.validate(3)) == TextureSamplerError.LodRange;
	assert samplerError(nan.validate(3)) == TextureSamplerError.LodRange;
	assert samplerError(infinite.validate(3)) == TextureSamplerError.LodRange;
	assert samplerError(past.validate(3)) == TextureSamplerError.LodOutsideChain;
}

test "textureMip replacement publishes only after late sampler validation" {
	const levels: Vec<TextureMipLevel> = squareLevels();
	let pixels: Vec<uint32> = colours(16, 4);
	const sampler: TextureSampler2D = sampling(TextureMipFilter.Linear, 2.0);
	const made: Result<TextureMipData, TextureMipError> =
		TextureMipData.create(levels, pixels, sampler);
	assert made.ok;
	if (!made.ok) { return; }
	let published: TextureMipData = made.value;
	pixels[20] = 0xFF00FFFF;
	const invalid: TextureSampler2D = { ...sampler, maxLod: 3.0 };
	const refused: Result<void, TextureMipError> =
		replaceTextureMip(published, levels, pixels, invalid);
	assert !refused.ok && refused.error == TextureMipError.Sampler;
	assert published.pixels[20] == 0xFFFF0000;
	assert published.sampler.sameSampling(sampler);
	const accepted: Result<void, TextureMipError> =
		replaceTextureMip(published, levels, pixels, sampler);
	assert accepted.ok && published.pixels[20] == 0xFF00FFFF;
	pixels[20] = 0;
	assert published.pixels[20] == 0xFF00FFFF;
}
