// Port of h3d.pass.PassList: the draw items one renderer pass draws, in drawing order.
//
// Heaps links PassObjects into a list that `filter` splits and `sort` reorders in place. Here
// a list holds indices into the frame's Span<DrawItem>: `collect` keeps the items whose
// material is in the list's phase, in item order, and `sortBackToFront` reorders them the way
// Renderer.depthSort does for the "alpha" pass. The index storage grows only when the item
// count does (a structural change), so a frame allocates nothing.

import { DrawContext, DrawItem, drawItem } from "./draw";
import { TargetLayout } from "./target";
import { Material, Phase, UniformBlock } from "./material";
import { Program } from "./gpu3d";
import { ProgramMap, ProgramError } from "./programMap";

// Float offsets of the view-projection column that yields clip z, in the camera block
// (shader3dBlocks.glsl `vertexParams`, viewProj first): Heaps' cam._13, _23, _33, _43.
const CLIP_Z_X: int32 = 2;
const CLIP_Z_Y: int32 = 6;
const CLIP_Z_Z: int32 = 10;
const CLIP_Z_W: int32 = 14;

export struct PassList {
	phase: Phase;
	indices: Vec<int32>;
	depths: Vec<float32>;
	count: int32;
}

export function forPhase(this typeof PassList, phase: Phase): PassList {
	return { phase: phase, indices: [], depths: [], count: 0 };
}

// PassList.init + filter: the items whose material draws in this list's phase.
export function collect(
	ref list: PassList,
	items: Span<DrawItem>,
	materials: Span<Material>,
): void {
	while ((list.indices.length as int32) < (items.length as int32)) {
		list.indices.push(0);
		list.depths.push(0.0);
	}
	let count: int32 = 0;
	for (let i = 0; i < (items.length as int32); i++) {
		if (materials[items[i].material].phase == list.phase) {
			list.indices[count] = i;
			count = count + 1;
		}
	}
	list.count = count;
}

// Clip-space depth of the item's origin (its world translation), as Heaps' depthSort takes
// it from absPos row 4. The camera is orthographic, so w is 1 and z is the depth.
function depthOf(item: DrawItem, camera: Span<float32>): float32 {
	return item.world.m41 * camera[CLIP_Z_X] +
		item.world.m42 * camera[CLIP_Z_Y] +
		item.world.m43 * camera[CLIP_Z_Z] +
		camera[CLIP_Z_W];
}

// Renderer.backToFront: farthest first, items at the same depth keep their order. An
// insertion sort, stable and in place; a pass list holds a handful of items.
export function sortBackToFront(
	ref list: PassList,
	items: Span<DrawItem>,
	camera: Span<float32>,
): void {
	for (let i = 0; i < list.count; i++) {
		list.depths[i] = depthOf(items[list.indices[i]], camera);
	}
	for (let i = 1; i < list.count; i++) {
		const index: int32 = list.indices[i];
		const depth: float32 = list.depths[i];
		let j: int32 = i - 1;
		while (j >= 0 && list.depths[j] < depth) {
			list.indices[j + 1] = list.indices[j];
			list.depths[j + 1] = list.depths[j];
			j = j - 1;
		}
		list.indices[j + 1] = index;
		list.depths[j + 1] = depth;
	}
}

// Output.draw: the collected items, in the list's order, into the current pass, each with the
// program `programs` draws for its material's. Answers how many it drew; an item whose program
// the map does not draw stops the list there.
export function drawPassList(
	ref context: DrawContext,
	list: PassList,
	items: Span<DrawItem>,
	programs: ProgramMap,
	targets: TargetLayout,
	globals: Span<UniformBlock>,
): Result<int32, ProgramError> {
	for (let i = 0; i < list.count; i++) {
		const item: DrawItem = items[list.indices[i]];
		const program: Program = try programs.drawnFor(context.materials[item.material].program);
		drawItem(context, item, program, targets, globals);
	}
	return Result.ok(list.count);
}
