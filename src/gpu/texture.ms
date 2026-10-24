// Sampled textures, through the GPU door: the non-target half of h3d.mat.Texture. A texture
// survives a lost context the way Heaps' does: `realloc` is called when the texture is next
// used (h3d/mat/Texture.hx:166-168), and one without it is lost for good (`isDisposed`, :232-235).

import {
	makeImage,
	makeImageMips,
	makeTextureView,
	destroyImage,
	destroyView,
	imageAlive,
	viewAlive,
	contextGeneration,
} from "./door";
import { stop } from "./stop";

export enum TextureError {
	BadSize,
	ImageRefused,
	ViewRefused,
}

// `pixels` are RGBA8, one 0xAABBGGRR word each, row by row from the top (void3d's TextureData).
export interface Texture {
	width: int32;
	height: int32;
	image: uint32;
	view: uint32;
	generation: int32;
	owned: boolean;
	closed: boolean;
	realloc: ((texture: Texture) => void) | null;
}

export function create(
	this typeof Texture,
	width: int32,
	height: int32,
	realloc: ((texture: Texture) => void) | null,
): Texture {
	return {
		width: width,
		height: height,
		image: 0,
		view: 0,
		generation: 0,
		owned: true,
		closed: false,
		realloc: realloc,
	};
}

// Levels of the full chain down to 1x1, as h3d Texture.mipLevels counts them (Texture.hx:80-90).
export function mipLevelCount(width: int32, height: int32): int32 {
	let count: int32 = 1;
	let largest: int32 = Math.max(width, height);
	while (largest > 1) {
		largest /= 2;
		count++;
	}
	return count;
}

// Pixels of a chain of `levels` (1 or the full chain, as the door takes it), -1 for any other.
export function mipChainWords(width: int32, height: int32, levels: int32): int64 {
	if (width <= 0 || height <= 0 || levels < 1) { return -1; }
	if (levels != 1 && levels != mipLevelCount(width, height)) { return -1; }
	let words: int64 = 0;
	let w: int32 = width;
	let h: int32 = height;
	for (let level = 0; level < levels; level++) {
		words += (w as int64) * (h as int64);
		w = Math.max(1, w / 2);
		h = Math.max(1, h / 2);
	}
	return words;
}

function reuploadKept(pixels: Vec<uint32>): (texture: Texture) => void {
	return (texture: Texture): void => {
		const uploaded: Result<int32, TextureError> = texture.upload(pixels);
		if (!uploaded.ok) { stopOnRefusedRealloc(texture, uploaded.error); }
	};
}

export function fromPixels(
	this typeof Texture,
	pixels: Readonly<Span<uint32>>,
	width: int32,
	height: int32,
	keep: boolean,
): Result<Texture, TextureError> {
	const texture: Texture = Texture.create(width, height, null);
	const uploaded: Result<int32, TextureError> = texture.upload(pixels);
	if (!uploaded.ok) { return Result.err(uploaded.error); }
	if (keep) {
		let kept: Vec<uint32> = new Array(0);
		for (const pixel of pixels) { kept.push(pixel); }
		texture.realloc = reuploadKept(kept);
	}
	return Result.ok(texture);
}

export function adopt(
	this typeof Texture,
	image: uint32,
	view: uint32,
	width: int32,
	height: int32,
): Texture {
	return {
		width: width,
		height: height,
		image: image,
		view: view,
		generation: contextGeneration(),
		owned: false,
		closed: false,
		realloc: null,
	};
}

function stopOnClosed(call: string): never {
	stop(`${call} on a texture that was closed`);
}

function stopOnRefusedRealloc(texture: Texture, error: TextureError): never {
	stop(`a ${texture.width}x${texture.height} texture's realloc could not ` +
		`upload its pixels again: ${error.toString()}`);
}

function holdsCurrent(this texture: Texture): boolean {
	return texture.view != 0 && texture.generation == contextGeneration();
}

function forgetHandles(texture: Texture): void {
	texture.image = 0;
	texture.view = 0;
	texture.generation = 0;
}

function releaseCurrent(texture: Texture): void {
	if (texture.holdsCurrent() && texture.owned) {
		destroyView(texture.view);
		destroyImage(texture.image);
	}
	forgetHandles(texture);
}

export function isClosed(this texture: Texture): boolean { return texture.closed; }

export function isLost(this texture: Texture): boolean {
	return texture.generation != 0 && texture.generation != contextGeneration();
}

export function upload(
	this texture: Texture,
	pixels: Readonly<Span<uint32>>,
): Result<int32, TextureError> {
	return texture.uploadMips(pixels, 1);
}

// `pixels` holds the `levels` of the chain back to back, level 0 first.
export function uploadMips(
	this texture: Texture,
	pixels: Readonly<Span<uint32>>,
	levels: int32,
): Result<int32, TextureError> {
	if (texture.closed) { stopOnClosed("upload"); }
	if (!texture.owned) {
		stop("upload on an adopted texture; its image is the caller's");
	}
	if ((pixels.length as int64) != mipChainWords(texture.width, texture.height, levels)) {
		return Result.err(TextureError.BadSize);
	}
	if (texture.holdsCurrent()) {
		stop("upload on a texture that holds a live image; its image is " +
			"immutable, so make a new Texture for new pixels");
	}
	forgetHandles(texture);
	const image: uint32 = levels == 1
		? makeImage(pixels, texture.width, texture.height)
		: makeImageMips(pixels, texture.width, texture.height, levels);
	if (image == 0) { return Result.err(TextureError.ImageRefused); }
	const view: uint32 = makeTextureView(image);
	if (view == 0) {
		destroyImage(image);
		return Result.err(TextureError.ViewRefused);
	}
	texture.image = image;
	texture.view = view;
	texture.generation = contextGeneration();
	return Result.ok(0);
}

function stopOnLost(texture: Texture): never {
	const remedy: string = texture.owned
		? "the texture has no realloc, so upload its pixels again"
		: "the adopted image died with it, so adopt the caller's new one";
	stop(`asView on a texture of GPU context ${texture.generation}; the context ` +
		`is now ${contextGeneration()} and ${remedy} (isLost tells when)`);
}

export function asView(this texture: Texture): uint32 {
	if (texture.closed) { stopOnClosed("asView"); }
	if (texture.holdsCurrent()) {
		if (texture.owned && (!imageAlive(texture.image) || !viewAlive(texture.view))) {
			stop("asView on a texture whose image or view was destroyed");
		}
		return texture.view;
	}
	const realloc = texture.realloc;
	if (realloc === null) {
		if (texture.view == 0) {
			stop(`asView on a ${texture.width}x${texture.height} texture with ` +
				"no pixels uploaded and no realloc");
		} else {
			stopOnLost(texture);
		}
	} else {
		forgetHandles(texture);
		realloc(texture);
	}
	if (!texture.holdsCurrent()) {
		stop(`a ${texture.width}x${texture.height} texture's realloc returned ` +
			"without uploading pixels");
	}
	return texture.view;
}

export struct DetachedHandles {
	image: uint32;
	view: uint32;
	generation: int32;
}

// The inverse of `adopt`: the caller takes the texture's handles and destroys nothing, and the
// texture is closed as `close` leaves it. An adopted texture, which `close` never destroys,
// returns the handles it was given. A texture lost to a newer context returns its stale
// handles, so `generation` != `contextGeneration()` tells the caller they name nothing now.
export function detach(this texture: Texture): DetachedHandles {
	if (texture.closed) { stopOnClosed("detach"); }
	const handles: DetachedHandles = {
		image: texture.image,
		view: texture.view,
		generation: texture.generation,
	};
	forgetHandles(texture);
	texture.realloc = null;
	texture.closed = true;
	return handles;
}

export function close(this texture: Texture): void {
	if (texture.closed) { stopOnClosed("close"); }
	releaseCurrent(texture);
	texture.realloc = null;
	texture.closed = true;
}
