import { FilterMode, Wrap } from "../gpu/state";

export const MAX_TEXTURE_MIP_LEVELS: int32 = 16;
const MAX_SOKOL_SURFACE_WORDS: int64 = 536870911;
const MAX_TEXTURE_PIXEL_OFFSET: int64 = 2147483647;
const SMALLEST_POSITIVE_LOD: float32 = 1.17549435e-38;

export enum TextureMipFilter {
	None,
	Nearest,
	Linear,
}

export enum TextureSamplerError {
	MinFilter,
	MagFilter,
	MipFilter,
	WrapU,
	WrapV,
	LodRange,
	LodOutsideChain,
	NoMipLod,
	AnisotropyRange,
	NonlinearAnisotropy,
	AnisotropyNeedsCapability,
}

export struct TextureSampler2D {
	minFilter: FilterMode;
	magFilter: FilterMode;
	mipFilter: TextureMipFilter;
	wrapU: Wrap;
	wrapV: Wrap;
	minLod: float32;
	maxLod: float32;
	maxAnisotropy: int32;
}

function validFilter(filter: FilterMode): boolean {
	return match (filter) {
		FilterMode.Nearest | FilterMode.Linear => true,
		_ => false,
	};
}

function validWrap(wrap: Wrap): boolean {
	return match (wrap) {
		Wrap.Clamp | Wrap.Repeat | Wrap.Mirror => true,
		_ => false,
	};
}

export function validate(
	this sampler: TextureSampler2D,
	levelCount: int32,
): Result<void, TextureSamplerError> {
	if (!validFilter(sampler.minFilter)) { return Result.err(TextureSamplerError.MinFilter); }
	if (!validFilter(sampler.magFilter)) { return Result.err(TextureSamplerError.MagFilter); }
	const validMip: boolean = match (sampler.mipFilter) {
		TextureMipFilter.None | TextureMipFilter.Nearest | TextureMipFilter.Linear => true,
		_ => false,
	};
	if (!validMip) { return Result.err(TextureSamplerError.MipFilter); }
	if (!validWrap(sampler.wrapU)) { return Result.err(TextureSamplerError.WrapU); }
	if (!validWrap(sampler.wrapV)) { return Result.err(TextureSamplerError.WrapV); }
	if (!Number.isFinite(sampler.minLod) || !Number.isFinite(sampler.maxLod) ||
		sampler.minLod < 0.0 || sampler.maxLod < sampler.minLod) {
		return Result.err(TextureSamplerError.LodRange);
	}
	if (sampler.mipFilter == TextureMipFilter.None &&
		(sampler.minLod != 0.0 || sampler.maxLod != 0.0)) {
		return Result.err(TextureSamplerError.NoMipLod);
	}
	if (levelCount < 1 || levelCount > MAX_TEXTURE_MIP_LEVELS ||
		sampler.maxLod > ((levelCount - 1) as float32)) {
		return Result.err(TextureSamplerError.LodOutsideChain);
	}
	if (sampler.maxAnisotropy < 1 || sampler.maxAnisotropy > 16) {
		return Result.err(TextureSamplerError.AnisotropyRange);
	}
	if (sampler.maxAnisotropy > 1 &&
		(sampler.minFilter != FilterMode.Linear || sampler.magFilter != FilterMode.Linear ||
			sampler.mipFilter != TextureMipFilter.Linear)) {
		return Result.err(TextureSamplerError.NonlinearAnisotropy);
	}
	return Result.ok(null);
}

export function unmipped(
	this typeof TextureSampler2D,
	filter: FilterMode,
	wrap: Wrap,
): TextureSampler2D {
	return {
		minFilter: filter,
		magFilter: filter,
		mipFilter: TextureMipFilter.None,
		wrapU: wrap,
		wrapV: wrap,
		minLod: 0.0,
		maxLod: 0.0,
		maxAnisotropy: 1,
	};
}

export function admitPortable(
	this sampler: TextureSampler2D,
	levelCount: int32,
): Result<void, TextureSamplerError> {
	return sampler.admitFor(levelCount, false);
}

export function admitFor(
	this sampler: TextureSampler2D,
	levelCount: int32,
	anisotropyAvailable: boolean,
): Result<void, TextureSamplerError> {
	const checked = try sampler.validate(levelCount);
	if (sampler.maxAnisotropy > 1 && !anisotropyAvailable) {
		return Result.err(TextureSamplerError.AnisotropyNeedsCapability);
	}
	return Result.ok(null);
}

export function sameSampling(this sampler: TextureSampler2D, other: TextureSampler2D): boolean {
	return sampler.minFilter == other.minFilter && sampler.magFilter == other.magFilter &&
		sampler.mipFilter == other.mipFilter && sampler.wrapU == other.wrapU &&
		sampler.wrapV == other.wrapV && sampler.minLod == other.minLod &&
		sampler.maxLod == other.maxLod && sampler.maxAnisotropy == other.maxAnisotropy;
}

// The arguments gpu/door.ms makeSamplerEx takes: enum ordinals, with sokol's max_lod of 0 (its
// unset, FLT_MAX) written as the smallest positive lod, which samples level 0 all the same.
export struct SamplerCall {
	minFilter: int32;
	magFilter: int32;
	mipFilter: int32;
	wrapU: int32;
	wrapV: int32;
	minLod: float32;
	maxLod: float32;
	maxAnisotropy: int32;
}

export function doorCall(this sampler: TextureSampler2D): SamplerCall {
	return {
		minFilter: sampler.minFilter as int32,
		magFilter: sampler.magFilter as int32,
		mipFilter: sampler.mipFilter as int32,
		wrapU: sampler.wrapU as int32,
		wrapV: sampler.wrapV as int32,
		minLod: sampler.minLod,
		maxLod: sampler.maxLod > 0.0 ? sampler.maxLod : SMALLEST_POSITIVE_LOD,
		maxAnisotropy: sampler.maxAnisotropy,
	};
}

export struct TextureMipLevel {
	width: int32;
	height: int32;
	pixelOffset: int32;
	pixelCount: int32;
}

export function byteOffset(this level: TextureMipLevel): int64 {
	return (level.pixelOffset as int64) * 4;
}

export function byteCount(this level: TextureMipLevel): int64 {
	return (level.pixelCount as int64) * 4;
}

export enum TextureMipError {
	EmptyChain,
	TooManyLevels,
	IncompleteChain,
	LevelDimensions,
	ByteExtent,
	PixelOffset,
	PixelCount,
	PixelExtent,
	Sampler,
}

export struct TextureMipData {
	levels: Vec<TextureMipLevel>;
	pixels: Vec<uint32>;
	sampler: TextureSampler2D;
}

export function create(
	this typeof TextureMipData,
	levels: Readonly<Span<TextureMipLevel>>,
	pixels: Readonly<Span<uint32>>,
	sampler: TextureSampler2D,
): Result<TextureMipData, TextureMipError> {
	if (levels.length < 1) { return Result.err(TextureMipError.EmptyChain); }
	if (levels.length > MAX_TEXTURE_MIP_LEVELS) {
		return Result.err(TextureMipError.TooManyLevels);
	}
	let width: int32 = levels[0].width;
	let height: int32 = levels[0].height;
	if (width <= 0 || height <= 0) { return Result.err(TextureMipError.LevelDimensions); }
	const baseWords: int64 = (width as int64) * (height as int64);
	if (baseWords > MAX_SOKOL_SURFACE_WORDS) { return Result.err(TextureMipError.ByteExtent); }
	let fullCount: int32 = 1;
	let largest: int32 = Math.max(width, height);
	while (largest > 1) {
		largest /= 2;
		fullCount++;
	}
	if (levels.length > 1 || sampler.mipFilter != TextureMipFilter.None) {
		if (fullCount > MAX_TEXTURE_MIP_LEVELS) {
			return Result.err(TextureMipError.TooManyLevels);
		}
		if (levels.length != fullCount) { return Result.err(TextureMipError.IncompleteChain); }
	}
	let offset: int64 = 0;
	for (const level of levels) {
		if (level.width != width || level.height != height) {
			return Result.err(TextureMipError.LevelDimensions);
		}
		const words: int64 = (width as int64) * (height as int64);
		if (words > MAX_SOKOL_SURFACE_WORDS || offset > MAX_TEXTURE_PIXEL_OFFSET - words) {
			return Result.err(TextureMipError.ByteExtent);
		}
		if (level.pixelOffset < 0 || (level.pixelOffset as int64) != offset) {
			return Result.err(TextureMipError.PixelOffset);
		}
		if ((level.pixelCount as int64) != words) {
			return Result.err(TextureMipError.PixelCount);
		}
		if (offset > pixels.length || words > pixels.length - offset) {
			return Result.err(TextureMipError.PixelExtent);
		}
		offset += words;
		width = Math.max(1, width / 2);
		height = Math.max(1, height / 2);
	}
	if (offset != pixels.length) { return Result.err(TextureMipError.PixelExtent); }
	const checked: Result<void, TextureSamplerError> = sampler.validate(levels.length as int32);
	if (!checked.ok) { return Result.err(TextureMipError.Sampler); }
	let data: TextureMipData = { levels: [], pixels: [], sampler: sampler };
	for (const level of levels) { data.levels.push({ ...level }); }
	for (const pixel of pixels) { data.pixels.push(pixel); }
	return Result.ok(move data);
}

export function replaceTextureMip(
	ref data: TextureMipData,
	levels: Readonly<Span<TextureMipLevel>>,
	pixels: Readonly<Span<uint32>>,
	sampler: TextureSampler2D,
): Result<void, TextureMipError> {
	let next: TextureMipData = try TextureMipData.create(levels, pixels, sampler);
	data = move next;
	return Result.ok(null);
}
