// A cube render target: the Cube + Target half of h3d.mat.Texture, drawn into one face of one mip
// at a time (Engine.pushTarget(texture, face, mip)) and sampled whole. Like RenderTarget it keeps
// its size, mip count and format, so allocate makes it again after context loss; what was drawn
// into it is gone then, and its owner draws it again.

import { Vec4 } from "../math/math3d";
import {
	PixelFormat,
	LoadAction,
	makeCubeTargetImage,
	makeCubeAttachmentView,
	makeTextureView,
	destroyImage,
	destroyView,
	imageAlive,
	contextGeneration,
} from "./door";
import { ColorAttachment } from "./target";

export interface CubeTarget {
	size: int32;
	levels: int32;
	format: PixelFormat;
	image: uint32;
	// One attachment view per face and mip, face-major: faces[face * levels + level].
	faces: Vec<uint32>;
	texture: uint32;
	generation: int32;
	closed: boolean;
}

export const CUBE_FACES: int32 = 6;

// The mip count of a full chain down to 1x1 (h3d Texture.mipLevels).
export function cubeFullLevels(size: int32): int32 {
	let levels: int32 = 1;
	for (let largest = size; largest > 1; largest = largest >> 1) { levels = levels + 1; }
	return levels;
}

function stopOnClosedCube(call: string): void {
	console.log(`gpu door: ${call} on a cube target that was closed`);
	unreachable;
}

export function unallocated(
	this typeof CubeTarget,
	size: int32,
	levels: int32,
	format: PixelFormat,
): CubeTarget {
	return {
		size: size,
		levels: levels,
		format: format,
		image: 0,
		faces: [],
		texture: 0,
		generation: 0,
		closed: false,
	};
}

function destroyHandles(target: CubeTarget): void {
	if (target.texture != 0) { destroyView(target.texture); }
	for (const view of target.faces) {
		if (view != 0) { destroyView(view); }
	}
	if (target.image != 0) { destroyImage(target.image); }
	target.image = 0;
	target.faces = [];
	target.texture = 0;
	target.generation = 0;
}

function stopOnRefusedCube(target: CubeTarget, what: string): void {
	destroyHandles(target);
	console.log(`gpu door: allocate refused a ${target.size}x${target.size} cube of ` +
		`${target.levels} mips in ${target.format.toString()}: ${what}`);
	unreachable;
}

// Whether the GPU objects belong to the current context; false before the first allocate and
// after context loss, when what was drawn into the cube is gone.
export function isCurrent(this target: CubeTarget): boolean {
	if (target.closed) { stopOnClosedCube("isCurrent"); }
	if (target.image == 0 || target.generation != contextGeneration()) { return false; }
	if (!imageAlive(target.image)) {
		console.log("gpu door: isCurrent on a cube target whose image was released");
		unreachable;
	}
	return true;
}

// Makes the image, a view of every face and mip, and the texture view; a cube from an earlier
// context is forgotten, its handles died with it.
export function allocate(this target: CubeTarget): void {
	if (target.closed) { stopOnClosedCube("allocate"); }
	if (target.isCurrent()) { destroyHandles(target); }
	target.image = 0;
	target.faces = [];
	target.texture = 0;
	target.image = makeCubeTargetImage(target.size, target.levels, target.format);
	if (target.image == 0) { stopOnRefusedCube(target, "image"); }
	for (let face = 0; face < CUBE_FACES; face++) {
		for (let level = 0; level < target.levels; level++) {
			const view: uint32 = makeCubeAttachmentView(target.image, face, level);
			if (view == 0) { stopOnRefusedCube(target, `face ${face} mip ${level} view`); }
			target.faces.push(view);
		}
	}
	target.texture = makeTextureView(target.image);
	if (target.texture == 0) { stopOnRefusedCube(target, "texture view"); }
	target.generation = contextGeneration();
}

function requireCurrentCube(target: CubeTarget, call: string): void {
	if (!target.isCurrent()) {
		console.log(`gpu door: ${call} on a cube target with no GPU objects of this context; ` +
			"allocate makes them");
		unreachable;
	}
}

// Face `face` (sokol's order, +X -X +Y -Y +Z -Z) of mip `level` as a pass's colour attachment.
export function asColor(
	this target: CubeTarget,
	face: int32,
	level: int32,
	load: LoadAction,
	clear: Vec4,
): ColorAttachment {
	requireCurrentCube(target, "asColor");
	if (face < 0 || face >= CUBE_FACES || level < 0 || level >= target.levels) {
		console.log(`gpu door: asColor on face ${face} mip ${level} of a cube with ` +
			`${target.levels} mips`);
		unreachable;
	}
	return {
		view: target.faces[face * target.levels + level],
		format: target.format,
		load: load,
		clear: clear,
		generation: target.generation,
	};
}

export function asTexture(this target: CubeTarget): uint32 {
	requireCurrentCube(target, "asTexture");
	return target.texture;
}

export function close(this target: CubeTarget): void {
	if (target.closed) { stopOnClosedCube("close"); }
	if (target.image != 0 && target.generation == contextGeneration()) { destroyHandles(target); }
	target.image = 0;
	target.faces = [];
	target.texture = 0;
	target.generation = 0;
	target.closed = true;
}
