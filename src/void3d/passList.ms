// Port of h3d.pass.PassList: the draw items one renderer pass draws, in drawing order.
//
// Heaps links PassObjects into a list that `filter` splits and `sort` reorders in place. Here
// a list holds indices into the frame's Span<DrawItem>: `collect` keeps the items whose
// material is in the list's phase, in item order, `sortByLayer` orders them by Pass.layer as
// SortByMaterial does first and then by the item's render order, and `sortBackToFront`
// reorders them the way Renderer.depthSort does for the "alpha" pass. The index storage grows
// only when the item count does (a structural change), so a frame allocates nothing.

import { DrawContext, DrawItem, SceneTexture, drawItemWith } from "./draw";
import { TargetLayout } from "../gpu/target";
import { Material, Phase, UniformBlock, ShadowCasting } from "./material";
import { ProgramKey } from "./gpu3d";
import { MeshData } from "./meshData";
import { Frustum3D } from "./frustum";

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
	layers: Vec<int32>;
	orders: Vec<int32>;
	count: int32;
}

export function forPhase(this typeof PassList, phase: Phase): PassList {
	return { phase: phase, indices: [], depths: [], layers: [], orders: [], count: 0 };
}

function reserve(ref list: PassList, length: int32): void {
	while ((list.indices.length as int32) < length) {
		list.indices.push(0);
		list.depths.push(0.0);
		list.layers.push(0);
		list.orders.push(0);
	}
}

// PassList.init + filter: the items whose material draws in this list's phase; a shadow-only
// caster draws in none.
export function collect(
	ref list: PassList,
	items: Readonly<Span<DrawItem>>,
	materials: Readonly<Span<Material>>,
): void {
	reserve(list, items.length as int32);
	let count: int32 = 0;
	for (let i = 0; i < (items.length as int32); i++) {
		const material: int32 = items[i].material.index;
		if (materials[material].phase == list.phase &&
			materials[material].castShadows != ShadowCasting.Only) {
			list.indices[count] = i;
			list.layers[count] = materials[material].layer;
			list.orders[count] = items[i].order;
			count = count + 1;
		}
	}
	list.count = count;
}

// The "shadow" pass list: the items whose material casts, in item order.
export function collectCasters(
	ref list: PassList,
	items: Readonly<Span<DrawItem>>,
	materials: Readonly<Span<Material>>,
): void {
	reserve(list, items.length as int32);
	let count: int32 = 0;
	for (let i = 0; i < (items.length as int32); i++) {
		const material: int32 = items[i].material.index;
		if (materials[material].castShadows != ShadowCasting.Off) {
			list.indices[count] = i;
			list.layers[count] = materials[material].layer;
			list.orders[count] = items[i].order;
			count = count + 1;
		}
	}
	list.count = count;
}

export function filterFrustum(
	ref list: PassList,
	items: Readonly<Span<DrawItem>>,
	meshes: Readonly<Span<MeshData>>,
	frustum: Frustum3D,
): int32 {
	let count: int32 = 0;
	let excluded: int32 = 0;
	for (let i = 0; i < list.count; i++) {
		let index: int32 = list.indices[i];
		if (frustum.intersectsBounds(meshes[items[index].mesh.index].bounds, items[index].world)) {
			list.indices[count] = index;
			list.layers[count] = list.layers[i];
			list.orders[count] = list.orders[i];
			count = count + 1;
		} else {
			excluded = excluded + 1;
		}
	}
	list.count = count;
	return excluded;
}

function depthOf(item: DrawItem, camera: Readonly<Span<float32>>): float32 {
	let z: float32 = item.world.m41 * camera[CLIP_Z_X] +
		item.world.m42 * camera[CLIP_Z_Y] +
		item.world.m43 * camera[CLIP_Z_Z] +
		camera[CLIP_Z_W];
	let w: float32 = item.world.m41 * camera[3] +
		item.world.m42 * camera[7] +
		item.world.m43 * camera[11] + camera[15];
	return w > 0.0 ? z / w : -z / w;
}

// Renderer.depthSort, back to front: lower layers first, then lower render orders, then
// farthest first; items at the same layer, order and depth keep their order. An insertion
// sort, stable and in place.
export function sortBackToFront(
	ref list: PassList,
	items: Readonly<Span<DrawItem>>,
	camera: Readonly<Span<float32>>,
): void {
	for (let i = 0; i < list.count; i++) {
		list.depths[i] = depthOf(items[list.indices[i]], camera);
	}
	for (let i = 1; i < list.count; i++) {
		const index: int32 = list.indices[i];
		const depth: float32 = list.depths[i];
		const layer: int32 = list.layers[i];
		const order: int32 = list.orders[i];
		let j: int32 = i - 1;
		while (j >= 0 && (list.layers[j] > layer ||
			(list.layers[j] == layer && (list.orders[j] > order ||
				(list.orders[j] == order && list.depths[j] < depth))))) {
			list.indices[j + 1] = list.indices[j];
			list.depths[j + 1] = list.depths[j];
			list.layers[j + 1] = list.layers[j];
			list.orders[j + 1] = list.orders[j];
			j = j - 1;
		}
		list.indices[j + 1] = index;
		list.depths[j + 1] = depth;
		list.layers[j + 1] = layer;
		list.orders[j + 1] = order;
	}
}

// SortByMaterial's first key: lower layers first, then lower render orders, item order kept
// inside both (void3d does not sort by shader or texture).
export function sortByLayer(ref list: PassList): void {
	for (let i = 1; i < list.count; i++) {
		const index: int32 = list.indices[i];
		const layer: int32 = list.layers[i];
		const order: int32 = list.orders[i];
		let j: int32 = i - 1;
		while (j >= 0 && (list.layers[j] > layer ||
			(list.layers[j] == layer && list.orders[j] > order))) {
			list.indices[j + 1] = list.indices[j];
			list.layers[j + 1] = list.layers[j];
			list.orders[j + 1] = list.orders[j];
			j = j - 1;
		}
		list.indices[j + 1] = index;
		list.layers[j + 1] = layer;
		list.orders[j + 1] = order;
	}
}

// Output.draw: the collected items, in the list's order, into the current pass, each with its
// program in `drawn`, which is indexed like `items`, and its material's pass.
export function drawPassList(
	context: DrawContext,
	list: PassList,
	items: Readonly<Span<DrawItem>>,
	drawn: Readonly<Span<ProgramKey>>,
	targets: TargetLayout,
	globals: Readonly<Span<UniformBlock>>,
	scene: SceneTexture,
): void {
	for (let i = 0; i < list.count; i++) {
		const index: int32 = list.indices[i];
		const material: Material = context.materials[items[index].material.index];
		drawItemWith(context, items[index], drawn[index], material.pass, targets, globals, scene);
	}
}
