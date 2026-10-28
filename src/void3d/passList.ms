// Port of h3d.pass.PassList: the draw items one renderer pass draws, in drawing order.
//
// Heaps links PassObjects into a list that `filter` splits and `sort` reorders in place. Here
// a list holds indices into the frame's Span<DrawItem>: `collect` keeps the items whose
// material is in the list's phase, in item order, `sortByMaterial` orders them as SortByMaterial
// does, by Pass.layer, then the item's render order, then its pipeline and texture, and
// `sortBackToFront` reorders them the way Renderer.depthSort does for the "alpha" pass. Each
// sort builds one key pair per item and merge-sorts positions by it, so equal keys keep their
// order. The storage grows only when the item count does (a structural change), so a frame
// allocates nothing.

import { DrawContext, DrawItem, SceneTexture, drawBatchWith, drawItemWith } from "./draw";
import { TargetLayout } from "../gpu/target";
import { Material, Phase, UniformBlock, ShadowCasting } from "./material";
import { ProgramKey } from "./gpu3d";
import { sortKeyOf } from "./sortKey";
import { RenderState, bits } from "../gpu/state";
import { TextureId, isTexture } from "./texture";
import { MeshData } from "./meshData";
import { Frustum3D } from "./frustum";
import { identity } from "../math/math3d";
import { center } from "./bounds";

// Float offsets of the view-projection column that yields clip z, in the camera block
// (shader3d.ms `VertexParams`, viewProj first): Heaps' cam._13, _23, _33, _43.
const CLIP_Z_X: int32 = 2;
const CLIP_Z_Y: int32 = 6;
const CLIP_Z_Z: int32 = 10;
const CLIP_Z_W: int32 = 14;

// First-seen numbers for 64-bit keys: an open-addressing table, cleared for each sort.
struct Ranks {
	keys: Vec<uint64>;
	numbers: Vec<int32>;
	mask: int32;
	count: int32;
}

export struct PassList {
	phase: Phase;
	indices: Vec<int32>;
	depths: Vec<float32>;
	layers: Vec<int32>;
	orders: Vec<int32>;
	count: int32;
	highs: Vec<uint64>;
	lows: Vec<uint64>;
	positions: Vec<int32>;
	spare: Vec<int32>;
	spareDepths: Vec<float32>;
	pipelines: Ranks;
	textures: Ranks;
}

function noRanks(): Ranks {
	return { keys: [], numbers: [], mask: 0, count: 0 };
}

export function forPhase(this typeof PassList, phase: Phase): PassList {
	return {
		phase: phase, indices: [], depths: [], layers: [], orders: [], count: 0,
		highs: [], lows: [], positions: [], spare: [], spareDepths: [],
		pipelines: noRanks(), textures: noRanks(),
	};
}

function reserve(ref list: PassList, length: int32): void {
	while ((list.indices.length as int32) < length) { list.indices.push(0); }
	while ((list.depths.length as int32) < length) { list.depths.push(0.0); }
	while ((list.layers.length as int32) < length) { list.layers.push(0); }
	while ((list.orders.length as int32) < length) { list.orders.push(0); }
	while ((list.highs.length as int32) < length) { list.highs.push(0); }
	while ((list.lows.length as int32) < length) { list.lows.push(0); }
	while ((list.positions.length as int32) < length) { list.positions.push(0); }
	while ((list.spare.length as int32) < length) { list.spare.push(0); }
	while ((list.spareDepths.length as int32) < length) { list.spareDepths.push(0.0); }
}

function clearRanks(ref table: Ranks, items: int32): void {
	let size: int32 = 16;
	while (size < 2 * items) { size = size * 2; }
	while ((table.keys.length as int32) < size) {
		table.keys.push(0);
		table.numbers.push(-1);
	}
	table.mask = size - 1;
	table.count = 0;
	for (let i = 0; i < size; i++) { table.numbers[i] = -1; }
}

function rankOf(ref table: Ranks, key: uint64): int32 {
	let at: int32 = (((((key >> 32) ^ key) * 2654435761) >> 16) & (table.mask as uint64)) as int32;
	while (table.numbers[at] >= 0) {
		if (table.keys[at] == key) { return table.numbers[at]; }
		at = (at + 1) & table.mask;
	}
	table.keys[at] = key;
	table.numbers[at] = table.count;
	table.count = table.count + 1;
	return table.numbers[at];
}

const KEY_BIAS: int64 = 2147483648;

function layerOrderKey(layer: int32, order: int32): uint64 {
	return ((((layer as int64) + KEY_BIAS) as uint64) << 32) |
		(((order as int64) + KEY_BIAS) as uint64);
}

function before(list: PassList, a: int32, b: int32): boolean {
	if (list.highs[a] != list.highs[b]) { return list.highs[a] < list.highs[b]; }
	return list.lows[a] < list.lows[b];
}

// Reorders the list by (highs, lows), ascending, equal keys in their present order: a bottom-up
// merge of positions that takes the right run only when it is strictly before the left.
function orderByKeys(ref list: PassList): void {
	const count: int32 = list.count;
	reserve(list, count);
	for (let i = 0; i < count; i++) { list.positions[i] = i; }
	let width: int32 = 1;
	while (width < count) {
		let start: int32 = 0;
		while (start < count) {
			const middle: int32 = start + width < count ? start + width : count;
			const end: int32 = start + 2 * width < count ? start + 2 * width : count;
			let left: int32 = start;
			let right: int32 = middle;
			for (let at = start; at < end; at++) {
				if (left < middle && (right >= end ||
					!before(list, list.positions[right], list.positions[left]))) {
					list.spare[at] = list.positions[left];
					left = left + 1;
				} else {
					list.spare[at] = list.positions[right];
					right = right + 1;
				}
			}
			start = start + 2 * width;
		}
		for (let i = 0; i < count; i++) { list.positions[i] = list.spare[i]; }
		width = width * 2;
	}
	for (let i = 0; i < count; i++) { list.spare[i] = list.indices[list.positions[i]]; }
	for (let i = 0; i < count; i++) { list.indices[i] = list.spare[i]; }
	for (let i = 0; i < count; i++) { list.spareDepths[i] = list.depths[list.positions[i]]; }
	for (let i = 0; i < count; i++) { list.depths[i] = list.spareDepths[i]; }
	for (let i = 0; i < count; i++) { list.spare[i] = list.layers[list.positions[i]]; }
	for (let i = 0; i < count; i++) { list.layers[i] = list.spare[i]; }
	for (let i = 0; i < count; i++) { list.spare[i] = list.orders[list.positions[i]]; }
	for (let i = 0; i < count; i++) { list.orders[i] = list.spare[i]; }
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
		const geometry = items[index].skinGeometry;
		const visible: boolean = !items[index].lodCulled && (geometry === null ?
			frustum.intersectsBounds(meshes[items[index].mesh.index].bounds, items[index].world) :
			frustum.intersectsBounds(geometry.mesh.bounds, identity()));
		if (visible) {
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

function depthOf(item: Readonly<DrawItem>, camera: Readonly<Span<float32>>): float32 {
	let x: float32 = item.world.m41;
	let y: float32 = item.world.m42;
	let depth: float32 = item.world.m43;
	const geometry = item.skinGeometry;
	if (geometry !== null) {
		const middle = geometry.mesh.bounds.center();
		x = middle.x; y = middle.y; depth = middle.z;
	}
	let z: float32 = x * camera[CLIP_Z_X] + y * camera[CLIP_Z_Y] +
		depth * camera[CLIP_Z_Z] + camera[CLIP_Z_W];
	let w: float32 = x * camera[3] + y * camera[7] + depth * camera[11] + camera[15];
	return w > 0.0 ? z / w : -z / w;
}

// Renderer.depthSort, back to front: lower layers first, then lower render orders, then
// farthest first; items at the same layer, order and depth keep their order.
export function sortBackToFront(
	ref list: PassList,
	items: Readonly<Span<DrawItem>>,
	camera: Readonly<Span<float32>>,
): void {
	reserve(list, list.count);
	for (let i = 0; i < list.count; i++) {
		let depth: float32 = depthOf(items[list.indices[i]], camera);
		if (depth == 0.0) { depth = 0.0; }
		list.depths[i] = depth;
		list.highs[i] = layerOrderKey(list.layers[i], list.orders[i]);
		list.lows[i] = (~(sortKeyOf(depth) as uint64)) & 0xFFFFFFFF;
	}
	orderByKeys(list);
}

// The layer and render order alone, item order kept inside both: for a list whose draws
// commute with each other's state, and for one with no program to group by.
export function sortByLayer(ref list: PassList): void {
	reserve(list, list.count);
	for (let i = 0; i < list.count; i++) {
		list.highs[i] = layerOrderKey(list.layers[i], list.orders[i]);
		list.lows[i] = 0;
	}
	orderByKeys(list);
}

// SortByMaterial: lower layers first, then lower render orders (void3d's own key, before any
// material's), then the items of one pipeline (its program and render state), then those of
// one texture. Pipelines and textures are numbered by first appearance in the list, as
// SortByMaterial numbers its shaders and textures, so a group sits where its first item was.
// `drawn` is indexed like `materials`.
export function sortByMaterial(
	ref list: PassList,
	items: Readonly<Span<DrawItem>>,
	drawn: Readonly<Span<ProgramKey>>,
	materials: Readonly<Span<Material>>,
): void {
	reserve(list, list.count);
	clearRanks(list.pipelines, list.count);
	clearRanks(list.textures, list.count);
	for (let i = 0; i < list.count; i++) {
		const index: int32 = list.indices[i];
		const state: RenderState = { ...materials[items[index].material.index].pass };
		const image: TextureId = materials[items[index].material.index].texture;
		const pipeline: uint64 =
			(((drawn[items[index].material.index].bits() as uint32) as uint64) << 32) |
			(state.bits() as uint64);
		const texture: uint64 = image.isTexture() ? ((image.index as uint32) as uint64) + 1 : 0;
		list.highs[i] = layerOrderKey(list.layers[i], list.orders[i]);
		list.lows[i] = (((rankOf(list.pipelines, pipeline) as uint32) as uint64) << 32) |
			((rankOf(list.textures, texture) as uint32) as uint64);
	}
	orderByKeys(list);
}

// Output.draw: the collected items, in the list's order, into the current pass, each with its
// material's program in `drawn`, which is indexed like the context's materials, and its pass.
// Neighbours that differ only in their world matrices draw as one batch, whose instances keep the
// list's order.
export function drawPassList(
	context: DrawContext,
	list: PassList,
	items: Readonly<Span<DrawItem>>,
	drawn: Readonly<Span<ProgramKey>>,
	targets: TargetLayout,
	globals: Readonly<Span<UniformBlock>>,
	scene: SceneTexture,
): void {
	let i: int32 = 0;
	while (i < list.count) {
		const index: int32 = list.indices[i];
		const program: ProgramKey = drawn[items[index].material.index];
		const material: Material = context.materials[items[index].material.index];
		let end: int32 = i + 1;
		while (end < list.count && items[index].sameBatch(items[list.indices[end]])) {
			end = end + 1;
		}
		if (end - i == 1) {
			drawItemWith(context, items[index], program, material.pass, targets, globals, scene);
		} else {
			drawBatchWith(context, items, list.indices[i..end], program, material.pass,
				targets, globals, scene);
		}
		i = end;
	}
}
