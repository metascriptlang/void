// Sampled textures, through the GPU door: the non-target half of h3d.mat.Texture. A texture
// survives a lost context the way Heaps' does: `realloc` is called when the texture is next
// used (h3d/mat/Texture.hx:166-168), and one without it is lost for good (`isDisposed`, :232-235).

import {
	makeImage,
	makeTextureView,
	destroyImage,
	destroyView,
	imageAlive,
	viewAlive,
	contextGeneration,
} from "./door";

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

function stopOnClosed(call: string): void {
	console.log(`gpu door: ${call} on a texture that was closed`);
	unreachable;
}

function stopOnRefusedRealloc(texture: Texture, error: TextureError): void {
	console.log(`gpu door: a ${texture.width}x${texture.height} texture's realloc could not ` +
		`upload its pixels again: ${error.toString()}`);
	unreachable;
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
	if (texture.closed) { stopOnClosed("upload"); }
	if (!texture.owned) {
		console.log("gpu door: upload on an adopted texture; its image is the caller's");
		unreachable;
	}
	if (texture.width <= 0 || texture.height <= 0 ||
		(pixels.length as int64) != (texture.width as int64) * (texture.height as int64)) {
		return Result.err(TextureError.BadSize);
	}
	if (texture.holdsCurrent()) {
		console.log("gpu door: upload on a texture that holds a live image; its image is " +
			"immutable, so make a new Texture for new pixels");
		unreachable;
	}
	forgetHandles(texture);
	const image: uint32 = makeImage(pixels, texture.width, texture.height);
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

function stopOnLost(texture: Texture): void {
	const remedy: string = texture.owned
		? "the texture has no realloc, so upload its pixels again"
		: "the adopted image died with it, so adopt the caller's new one";
	console.log(`gpu door: asView on a texture of GPU context ${texture.generation}; the context ` +
		`is now ${contextGeneration()} and ${remedy} (isLost tells when)`);
	unreachable;
}

export function asView(this texture: Texture): uint32 {
	if (texture.closed) { stopOnClosed("asView"); }
	if (texture.holdsCurrent()) {
		if (texture.owned && (!imageAlive(texture.image) || !viewAlive(texture.view))) {
			console.log("gpu door: asView on a texture whose image or view was destroyed");
			unreachable;
		}
		return texture.view;
	}
	const realloc = texture.realloc;
	if (realloc === null) {
		if (texture.view == 0) {
			console.log(`gpu door: asView on a ${texture.width}x${texture.height} texture with ` +
				"no pixels uploaded and no realloc");
		} else {
			stopOnLost(texture);
		}
		unreachable;
	} else {
		forgetHandles(texture);
		realloc(texture);
	}
	if (!texture.holdsCurrent()) {
		console.log(`gpu door: a ${texture.width}x${texture.height} texture's realloc returned ` +
			"without uploading pixels");
		unreachable;
	}
	return texture.view;
}

export function close(this texture: Texture): void {
	if (texture.closed) { stopOnClosed("close"); }
	releaseCurrent(texture);
	texture.realloc = null;
	texture.closed = true;
}
