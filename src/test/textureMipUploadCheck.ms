import { FilterMode, Wrap } from "../gpu/state";
import { Texture, TextureError, mipLevelCount, mipChainWords } from "../gpu/texture";
import { DrawContext, addTextureMip } from "../void3d/draw";
import { TextureId, TextureUploadError } from "../void3d/texture";
import {
	TextureMipLevel,
	TextureMipData,
	TextureMipError,
	TextureMipFilter,
	TextureSampler2D,
	TextureSamplerError,
	SamplerCall,
} from "../void3d/textureMip";

function trilinear(lastLod: float32): TextureSampler2D {
	return {
		minFilter: FilterMode.Linear,
		magFilter: FilterMode.Linear,
		mipFilter: TextureMipFilter.Linear,
		wrapU: Wrap.Repeat,
		wrapV: Wrap.Mirror,
		minLod: 0.0,
		maxLod: lastLod,
		maxAnisotropy: 1,
	};
}

function levelsOf(width: int32, height: int32): Vec<TextureMipLevel> {
	let levels: Vec<TextureMipLevel> = [];
	let offset: int32 = 0;
	let w: int32 = width;
	let h: int32 = height;
	while (true) {
		levels.push({ width: w, height: h, pixelOffset: offset, pixelCount: w * h });
		offset += w * h;
		if (w == 1 && h == 1) { break; }
		w = Math.max(1, w / 2);
		h = Math.max(1, h / 2);
	}
	return move levels;
}

function pixelsFor(count: int32): Vec<uint32> {
	let pixels: Vec<uint32> = [];
	for (let i = 0; i < count; i++) { pixels.push(0xFF000000 + (i as uint32)); }
	return move pixels;
}

function chainOf(width: int32, height: int32): TextureMipData {
	const levels: Vec<TextureMipLevel> = levelsOf(width, height);
	const last: TextureMipLevel = levels[levels.length - 1];
	const created: Result<TextureMipData, TextureMipError> = TextureMipData.create(
		levels, pixelsFor(last.pixelOffset + last.pixelCount), trilinear((levels.length - 1) as float32),
	);
	if (!created.ok) { unreachable; }
	return created.value;
}

test "the door's chain length and per-level layout are the supplied chain's offsets" {
	const sizes: Vec<int32> = [4, 4, 7, 3, 1, 1, 5, 1, 8, 2, 3, 9];
	for (let i = 0; i < sizes.length; i += 2) {
		const chain: TextureMipData = chainOf(sizes[i], sizes[i + 1]);
		const count: int32 = chain.levels.length;
		assert mipLevelCount(sizes[i], sizes[i + 1]) == count;
		assert mipChainWords(sizes[i], sizes[i + 1], count) == (chain.pixels.length as int64);
		let sum: int64 = 0;
		for (let level = 0; level < count; level++) {
			assert (chain.levels[level].pixelOffset as int64) == sum;
			assert mipChainWords(sizes[i], sizes[i + 1], 1) == (sizes[i] * sizes[i + 1] as int64);
			sum += chain.levels[level].pixelCount as int64;
		}
	}
}

test "a chain the door cannot take has no word count: not 1 and not the full chain" {
	assert mipChainWords(7, 3, 1) == 21 && mipChainWords(7, 3, 3) == 25;
	assert mipChainWords(7, 3, 2) < 0 && mipChainWords(7, 3, 4) < 0 && mipChainWords(7, 3, 0) < 0;
	assert mipChainWords(0, 3, 1) < 0 && mipChainWords(7, -1, 1) < 0;
	assert mipLevelCount(1, 1) == 1 && mipLevelCount(1, 9) == 4 && mipLevelCount(16, 16) == 5;
}

test "an upload of the wrong pixel count for its chain is refused before any image is made" {
	const texture: Texture = Texture.create(4, 4, null);
	const single: Result<int32, TextureError> = texture.upload(pixelsFor(15));
	assert !single.ok && single.error == TextureError.BadSize;
	const base: Result<int32, TextureError> = texture.uploadMips(pixelsFor(16), 3);
	assert !base.ok && base.error == TextureError.BadSize;
	const partial: Result<int32, TextureError> = texture.uploadMips(pixelsFor(20), 2);
	assert !partial.ok && partial.error == TextureError.BadSize;
	const none: Result<int32, TextureError> = texture.uploadMips(pixelsFor(21), 0);
	assert !none.ok && none.error == TextureError.BadSize;
	assert texture.view == 0 && texture.image == 0 && texture.generation == 0;
}

test "a sampler reaches the door as enum ordinals, with a max lod of 0 written positive" {
	const trilin: SamplerCall = trilinear(4.0).doorCall();
	assert trilin.minFilter == 1 && trilin.magFilter == 1 && trilin.mipFilter == 2;
	assert trilin.wrapU == 1 && trilin.wrapV == 2 && trilin.minLod == 0.0 && trilin.maxLod == 4.0;
	assert trilin.maxAnisotropy == 1;
	const mixed: TextureSampler2D = {
		...trilinear(1.0), minFilter: FilterMode.Nearest, magFilter: FilterMode.Linear,
		mipFilter: TextureMipFilter.Nearest, wrapU: Wrap.Clamp, minLod: 0.5, maxAnisotropy: 1,
	};
	const nearest: SamplerCall = mixed.doorCall();
	assert nearest.minFilter == 0 && nearest.magFilter == 1 && nearest.mipFilter == 1;
	assert nearest.wrapU == 0 && nearest.minLod == 0.5 && nearest.maxLod == 1.0;
	const flat: SamplerCall = TextureSampler2D.unmipped(FilterMode.Nearest, Wrap.Repeat).doorCall();
	assert flat.mipFilter == 0 && flat.minFilter == 0 && flat.wrapV == 1;
	assert flat.minLod == 0.0 && flat.maxLod > 0.0 && flat.maxLod < 0.0001;
}

test "anisotropy is admitted only where the backend can promise it, and only all-linear" {
	const aniso: TextureSampler2D = { ...trilinear(2.0), maxAnisotropy: 8 };
	assert aniso.admitFor(3, true).ok;
	const refused: Result<void, TextureSamplerError> = aniso.admitFor(3, false);
	assert !refused.ok && refused.error == TextureSamplerError.AnisotropyNeedsCapability;
	const nearestMag: TextureSampler2D = { ...aniso, magFilter: FilterMode.Nearest };
	const named: Result<void, TextureSamplerError> = nearestMag.admitFor(3, true);
	assert !named.ok && named.error == TextureSamplerError.NonlinearAnisotropy;
	assert trilinear(2.0).admitFor(3, false).ok && trilinear(2.0).admitPortable(3).ok;
	const outside: Result<void, TextureSamplerError> = trilinear(3.0).admitFor(3, true);
	assert !outside.ok && outside.error == TextureSamplerError.LodOutsideChain;
}

test "a chain whose sampler the validation refuses takes no slot and makes nothing" {
	const context: DrawContext = DrawContext.withUniformCapacity(0);
	const chain: TextureMipData = chainOf(4, 4);
	const flatWithLod: TextureMipData = {
		...chain, sampler: { ...trilinear(2.0), mipFilter: TextureMipFilter.None },
	};
	const refused: Result<TextureId, TextureUploadError> = addTextureMip(context, flatWithLod);
	assert !refused.ok && refused.error == TextureUploadError.SamplerRefused;
	const empty: TextureMipData = { ...chain, levels: [], pixels: [] };
	const noLevels: Result<TextureId, TextureUploadError> = addTextureMip(context, empty);
	assert !noLevels.ok && noLevels.error == TextureUploadError.BadSize;
	assert context.liveTextures() == 0 && context.textures.length == 0;
	assert context.textureMips.length == 0 && context.mipSamplers.length == 0;
}
