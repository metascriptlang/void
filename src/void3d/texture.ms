// CPU side of a texture, in the role of h3d.mat.Texture: its pixels and the sampling Heaps keeps
// on the texture (`filter`, `wrap`; Bevy's `Image.sampler`). A lost context is rebuilt from it
// (draw.ms rebuildTextures), where Heaps calls the texture's `realloc`.

import { FilterMode, Wrap } from "../gpu/state";

// `pixels` are RGBA8, one 0xAABBGGRR word each (palette.ms packs them so), row by row from the
// top: uv (0, 0) is the first pixel on every backend.
export struct TextureData {
	pixels: Vec<uint32>;
	width: int32;
	height: int32;
	filter: FilterMode;
	wrap: Wrap;
}

export struct TextureId {
	index: int32;
	generation: int32;
}

export const NO_TEXTURE: TextureId = { index: 0, generation: 0 };

// `image` and `view` are the context's, made from the TextureData at the same index; `sampler`
// is the context's shared one for the texture's filter and wrap (draw.ms samplerFor).
export struct GpuTexture {
	image: uint32;
	view: uint32;
	sampler: uint32;
	generation: int32;
}

export enum TextureUploadError {
	BadSize,
	ImageRefused,
	ViewRefused,
	SamplerRefused,
}

export function empty(this typeof TextureData): TextureData {
	return { pixels: [], width: 0, height: 0, filter: FilterMode.Linear, wrap: Wrap.Clamp };
}

export function isWellFormed(this data: TextureData): boolean {
	if (data.width <= 0 || data.height <= 0) { return false; }
	return (data.pixels.length as int64) == (data.width as int64) * (data.height as int64);
}

export function isTexture(this id: TextureId): boolean {
	return id.generation != 0;
}
