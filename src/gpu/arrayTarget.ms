// A depth array render target: the texture array h3d's CascadeShadowMap draws one cascade into per
// layer (Engine.pushTarget(texture, layer)) and samples whole. Like CubeTarget it keeps its size,
// layer count and format, so allocate makes it again after context loss; what was drawn into it
// is gone then, and its owner draws it again.

import {
	PixelFormat,
	LoadAction,
	StoreAction,
	makeArrayTargetImage,
	makeArrayAttachmentView,
	makeTextureView,
	destroyImage,
	destroyView,
	imageAlive,
	contextGeneration,
} from "./door";
import { DepthAttachment } from "./target";
import { stop } from "./stop";

export interface ArrayTarget {
	size: int32;
	layers: int32;
	format: PixelFormat;
	image: uint32;
	// One depth attachment view per layer.
	views: Vec<uint32>;
	texture: uint32;
	generation: int32;
	closed: boolean;
}

function stopOnClosedArray(call: string): never {
	stop(`${call} on an array target that was closed`);
}

export function unallocated(
	this typeof ArrayTarget,
	size: int32,
	layers: int32,
	format: PixelFormat,
): ArrayTarget {
	return {
		size: size,
		layers: layers,
		format: format,
		image: 0,
		views: [],
		texture: 0,
		generation: 0,
		closed: false,
	};
}

function destroyHandles(target: ArrayTarget): void {
	if (target.texture != 0) { destroyView(target.texture); }
	for (const view of target.views) {
		if (view != 0) { destroyView(view); }
	}
	if (target.image != 0) { destroyImage(target.image); }
	target.image = 0;
	target.views = [];
	target.texture = 0;
	target.generation = 0;
}

function stopOnRefusedArray(target: ArrayTarget, what: string): never {
	destroyHandles(target);
	stop(`allocate refused a ${target.size}x${target.size} array of ` +
		`${target.layers} layers in ${target.format.toString()}: ${what}`);
}

// Whether the GPU objects belong to the current context; false before the first allocate and
// after context loss, when what was drawn into the layers is gone.
export function isCurrent(this target: ArrayTarget): boolean {
	if (target.closed) { stopOnClosedArray("isCurrent"); }
	if (target.image == 0 || target.generation != contextGeneration()) { return false; }
	if (!imageAlive(target.image)) {
		stop("isCurrent on an array target whose image was released");
	}
	return true;
}

// Makes the image, a view of every layer, and the texture view; an array from an earlier
// context is forgotten, its handles died with it.
export function allocate(this target: ArrayTarget): void {
	if (target.closed) { stopOnClosedArray("allocate"); }
	if (target.isCurrent()) { destroyHandles(target); }
	target.image = 0;
	target.views = [];
	target.texture = 0;
	target.image = makeArrayTargetImage(target.size, target.layers, target.format);
	if (target.image == 0) { stopOnRefusedArray(target, "image"); }
	for (let layer = 0; layer < target.layers; layer++) {
		const view: uint32 = makeArrayAttachmentView(target.image, layer);
		if (view == 0) { stopOnRefusedArray(target, `layer ${layer} view`); }
		target.views.push(view);
	}
	target.texture = makeTextureView(target.image);
	if (target.texture == 0) { stopOnRefusedArray(target, "texture view"); }
	target.generation = contextGeneration();
}

function requireCurrentArray(target: ArrayTarget, call: string): void {
	if (!target.isCurrent()) {
		stop(`${call} on an array target with no GPU objects of this context; ` +
			"allocate makes them");
	}
}

// Layer `layer` as a pass's depth attachment.
export function asDepth(
	this target: ArrayTarget,
	layer: int32,
	load: LoadAction,
	clear: float32,
	store: StoreAction,
): DepthAttachment {
	requireCurrentArray(target, "asDepth");
	if (layer < 0 || layer >= target.layers) {
		stop(`asDepth on layer ${layer} of an array with ${target.layers} layers`);
	}
	return {
		view: target.views[layer],
		format: target.format,
		load: load,
		store: store,
		clear: clear,
		generation: target.generation,
	};
}

export function asTexture(this target: ArrayTarget): uint32 {
	requireCurrentArray(target, "asTexture");
	return target.texture;
}

export function close(this target: ArrayTarget): void {
	if (target.closed) { stopOnClosedArray("close"); }
	if (target.image != 0 && target.generation == contextGeneration()) { destroyHandles(target); }
	target.image = 0;
	target.views = [];
	target.texture = 0;
	target.generation = 0;
	target.closed = true;
}
