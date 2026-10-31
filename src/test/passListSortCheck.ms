import { translation } from "../math/math3d";
import { DrawItem, MeshId, MaterialId } from "../void3d/draw";
import { Material, Phase, ShadowCasting } from "../void3d/material";
import { TextureId, isTexture } from "../void3d/texture";
import { Program, ProgramKey } from "../void3d/gpu3d";
import { RenderState, Face } from "../gpu/state";
import { Bounds3D } from "../void3d/bounds";
import { Frustum3D } from "../void3d/frustum";
import { MeshData } from "../void3d/meshData";
import {
	PassList, collectCasters, filterFrustum, filterFrustumInto, sortBackToFront, sortByLayer,
	sortByMaterial, sortCasters,
} from "../void3d/passList";
import { collect } from "./drawHelpers";

const NONE: TextureId = { store: 0, index: 0, generation: 0 };

function textured(index: int32): TextureId {
	return { store: 1, index: index, generation: 1 };
}

function itemOf(material: int32, order: int32, z: float32): DrawItem {
	const mesh: MeshId = { store: 1, index: 0, generation: 1 };
	const made: MaterialId = { store: 1, index: material, generation: 1 };
	return {
		mesh: mesh, material: made, world: translation(0.0, 0.0, z), order: order, skin: null,
		skinGeometry: null, skinPalette: 0, range: null, instances: null,
	};
}

function materialOf(program: Program, culling: Face, texture: TextureId, layer: int32): Material {
	const plain: Material = Material.plain(
		program, RenderState.defaults().withCulling(culling), Phase.Opaque);
	return { ...plain, texture: texture, layer: layer };
}

// Material 0 and 1 differ in render state, 2 in program, 3 and 4 in texture only.
function materials(): Vec<Material> {
	return [
		materialOf(Program.Lit, Face.Back, NONE, 0),
		materialOf(Program.Lit, Face.None, NONE, 0),
		materialOf(Program.UnlitTextured, Face.Back, textured(1), 0),
		materialOf(Program.UnlitTextured, Face.Back, textured(2), 0),
		materialOf(Program.UnlitTextured, Face.Back, textured(1), 0),
		materialOf(Program.Lit, Face.Back, NONE, 5),
		materialOf(Program.Lit, Face.Back, NONE, -5),
	];
}

function programsOf(list: Readonly<Span<Material>>): Vec<ProgramKey> {
	let drawn: Vec<ProgramKey> = [];
	for (const material of list) { drawn.push(material.program); }
	return drawn;
}

function sorted(items: Vec<DrawItem>): PassList {
	const table: Vec<Material> = materials();
	let list: PassList = PassList.forPhase(Phase.Opaque);
	collect(list, items, table);
	sortByMaterial(list, items, programsOf(table), table);
	return list;
}

function indicesOf(list: PassList): Vec<int32> {
	let out: Vec<int32> = [];
	for (let i = 0; i < list.count; i++) { out.push(list.indices[i]); }
	return out;
}

function same(a: Vec<int32>, b: Vec<int32>): boolean {
	if (a.length != b.length) { return false; }
	for (let i = 0; i < (a.length as int32); i++) { if (a[i] != b[i]) { return false; } }
	return true;
}

function switches(list: PassList, items: Vec<DrawItem>): int32 {
	const table: Vec<Material> = materials();
	let count: int32 = 0;
	for (let i = 1; i < list.count; i++) {
		const a: Material = table[items[list.indices[i - 1]].material.index];
		const b: Material = table[items[list.indices[i]].material.index];
		if (a.program != b.program || a.pass != b.pass) { count = count + 1; }
	}
	return count;
}

test "an opaque list groups one pipeline together and keeps item order inside a group" {
	const items: Vec<DrawItem> = [
		itemOf(0, 0, 0.0), itemOf(1, 0, 0.0), itemOf(0, 0, 0.0),
		itemOf(1, 0, 0.0), itemOf(0, 0, 0.0), itemOf(1, 0, 0.0),
	];
	const list: PassList = sorted(items);
	assert same(indicesOf(list), [0, 2, 4, 1, 3, 5]);
	assert switches(list, items) == 1;
}

test "an opaque list groups a program, then a texture, the group of the first item first" {
	const items: Vec<DrawItem> = [
		itemOf(2, 0, 0.0), itemOf(0, 0, 0.0), itemOf(3, 0, 0.0), itemOf(2, 0, 0.0),
		itemOf(0, 0, 0.0), itemOf(4, 0, 0.0), itemOf(3, 0, 0.0),
	];
	const list: PassList = sorted(items);
	assert same(indicesOf(list), [0, 3, 5, 2, 6, 1, 4]);
}

function meshItem(material: int32, mesh: int32): DrawItem {
	return { ...itemOf(material, 0, 0.0), mesh: { store: 1, index: mesh, generation: 1 } };
}

test "two meshes collected A, B, A, B come out A, A, B, B" {
	const items: Vec<DrawItem> = [
		meshItem(0, 0), meshItem(0, 1), meshItem(0, 0), meshItem(0, 1),
	];
	assert same(indicesOf(sorted(items)), [0, 2, 1, 3]);
}

test "two materials sharing a program and a texture group by material, then mesh" {
	const items: Vec<DrawItem> = [
		meshItem(2, 0), meshItem(4, 0), meshItem(2, 1), meshItem(4, 1), meshItem(2, 0),
	];
	assert same(indicesOf(sorted(items)), [0, 4, 2, 1, 3]);
}

test "casters collected A, B, A, B draw A, A, B, B, whatever their layer and order" {
	const items: Vec<DrawItem> = [
		meshItem(0, 0), { ...meshItem(0, 1), order: 7 }, meshItem(0, 0), meshItem(0, 1),
	];
	let list: PassList = PassList.forPhase(Phase.Opaque);
	const casting: Vec<Material> = [{ ...materials()[0], castShadows: ShadowCasting.On }];
	collectCasters(list, items, casting);
	assert list.count == 4;
	sortCasters(list, items);
	assert same(indicesOf(list), [0, 2, 1, 3]);
}

function boundedMeshes(): Vec<MeshData> {
	const cube: Bounds3D = Bounds3D.fromValues(-0.25, -0.25, -0.25, 0.5, 0.5, 0.5);
	return [
		{ vertices: [], indices: [], bounds: cube },
		{ vertices: [], indices: [], bounds: cube },
	];
}

function casterAt(material: int32, mesh: int32, x: float32): DrawItem {
	return { ...meshItem(material, mesh), world: translation(x, 0.0, 0.5) };
}

function layersAsBefore(items: Vec<DrawItem>, centres: Vec<float32>): boolean {
	const casting: Vec<Material> = [
		{ ...materials()[0], castShadows: ShadowCasting.On },
		{ ...materials()[1], castShadows: ShadowCasting.On },
		{ ...materials()[2], castShadows: ShadowCasting.On },
	];
	const meshes: Vec<MeshData> = boundedMeshes();
	let kept: PassList = PassList.forPhase(Phase.Opaque);
	let layer: PassList = PassList.forPhase(Phase.Opaque);
	let old: PassList = PassList.forPhase(Phase.Opaque);
	collectCasters(kept, items, casting);
	sortCasters(kept, items);
	const total: int32 = kept.count;
	for (const centre of centres) {
		const frustum: Frustum3D = Frustum3D.fromMatrix(translation(-centre, 0.0, 0.0));
		collectCasters(old, items, casting);
		const oldExcluded: int32 = filterFrustum(old, items, meshes, frustum);
		sortCasters(old, items);
		const excluded: int32 = filterFrustumInto(layer, kept, items, meshes, frustum);
		if (!same(indicesOf(layer), indicesOf(old)) || excluded != oldExcluded ||
			kept.count != total) { return false; }
	}
	return true;
}

test "each layer's casters filtered from the once-sorted list equal the per-layer sort" {
	const items: Vec<DrawItem> = [
		casterAt(2, 0, 0.0), casterAt(0, 1, 1.0), casterAt(1, 0, 2.0), casterAt(0, 0, 3.0),
		casterAt(2, 1, 4.0), casterAt(1, 1, 0.5), casterAt(0, 0, 2.5), casterAt(2, 0, 5.0),
		casterAt(1, 0, 9.0), casterAt(0, 1, 3.5), casterAt(2, 0, 1.5), casterAt(1, 1, 4.5),
	];
	assert layersAsBefore(items, [0.0, 2.0, 4.0, 6.0]);
}

test "a material cast only in a later layer still orders that layer as the per-layer sort" {
	const items: Vec<DrawItem> = [
		casterAt(0, 0, 0.0), casterAt(1, 0, 0.1), casterAt(0, 1, 0.2), casterAt(1, 1, 0.3),
		casterAt(2, 1, 4.0), casterAt(0, 0, 4.1), casterAt(2, 0, 4.2), casterAt(1, 1, 4.3),
	];
	assert layersAsBefore(items, [0.0, 4.0]);
}

test "equal keys keep item order" {
	const items: Vec<DrawItem> = [itemOf(0, 3, 0.0), itemOf(0, 3, 1.0), itemOf(0, 3, -1.0)];
	assert same(indicesOf(sorted(items)), [0, 1, 2]);
}

test "a render order comes before the pipeline, and a layer before both" {
	const byOrder: Vec<DrawItem> = [itemOf(0, 1, 0.0), itemOf(1, 0, 0.0), itemOf(0, 0, 0.0)];
	assert same(indicesOf(sorted(byOrder)), [2, 1, 0]);
	const byLayer: Vec<DrawItem> = [
		itemOf(5, -9, 0.0), itemOf(0, 0, 0.0), itemOf(6, 9, 0.0), itemOf(0, 0, 0.0),
	];
	assert same(indicesOf(sorted(byLayer)), [2, 1, 3, 0]);
}

// Materials 2 and 4 share a pipeline and a texture, so they are one group.
function groupOf(material: int32): int32 {
	return material == 4 ? 2 : material;
}

test "a large opaque list sorts into one run per order, pipeline and texture" {
	let items: Vec<DrawItem> = [];
	let seed: int64 = 12345;
	for (let i = 0; i < 4000; i++) {
		seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
		items.push(itemOf(((seed >> 8) % 5) as int32, ((seed >> 16) % 3) as int32, 0.0));
	}
	const list: PassList = sorted(items);
	assert list.count == 4000;
	let runs: int32 = 0;
	for (let i = 0; i < list.count; i++) {
		const here: DrawItem = items[list.indices[i]];
		if (i == 0) {
			runs = 1;
			continue;
		}
		const last: DrawItem = items[list.indices[i - 1]];
		assert last.order <= here.order;
		if (last.order != here.order || groupOf(last.material.index) != groupOf(here.material.index)) {
			runs = runs + 1;
		}
		if (last.order == here.order && last.material.index == here.material.index) {
			assert list.indices[i - 1] < list.indices[i];
		}
	}
	assert runs == 12;
}

function insertionOracle(items: Vec<DrawItem>, table: Vec<Material>): Vec<int32> {
	let out: Vec<int32> = [];
	let depths: Vec<float32> = [];
	for (let i = 0; i < (items.length as int32); i++) {
		out.push(i);
		depths.push(items[i].world.m43);
	}
	for (let i = 1; i < (out.length as int32); i++) {
		const at: int32 = out[i];
		const depth: float32 = depths[i];
		const layer: int32 = table[items[at].material.index].layer;
		const order: int32 = items[at].order;
		let j: int32 = i - 1;
		while (j >= 0 && (table[items[out[j]].material.index].layer > layer ||
			(table[items[out[j]].material.index].layer == layer && (items[out[j]].order > order ||
				(items[out[j]].order == order && depths[j] < depth))))) {
			out[j + 1] = out[j];
			depths[j + 1] = depths[j];
			j = j - 1;
		}
		out[j + 1] = at;
		depths[j + 1] = depth;
	}
	return out;
}

function farToNear(): Vec<float32> {
	return [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0];
}

test "back to front gives the insertion order, ties and layers included, over 3000 items" {
	let items: Vec<DrawItem> = [];
	let seed: int64 = 777;
	for (let i = 0; i < 3000; i++) {
		seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
		const z: float32 = (((seed >> 8) % 7) as float32) - 3.0;
		items.push(itemOf(((seed >> 16) % 7) as int32, ((seed >> 24) % 3) as int32, z));
	}
	const table: Vec<Material> = materials();
	let list: PassList = PassList.forPhase(Phase.Opaque);
	collect(list, items, table);
	sortBackToFront(list, items, farToNear());
	assert same(indicesOf(list), insertionOracle(items, table));
}

test "a layer and order sort keeps item order inside equal keys, over 3000 items" {
	let items: Vec<DrawItem> = [];
	let seed: int64 = 99;
	for (let i = 0; i < 3000; i++) {
		seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
		items.push(itemOf(((seed >> 16) % 7) as int32, ((seed >> 24) % 3) as int32, 0.0));
	}
	const table: Vec<Material> = materials();
	let list: PassList = PassList.forPhase(Phase.Opaque);
	collect(list, items, table);
	sortByLayer(list);
	let flat: Vec<DrawItem> = [];
	for (const item of items) { flat.push({ ...item, world: translation(0.0, 0.0, 0.0) }); }
	assert same(indicesOf(list), insertionOracle(flat, table));
}

function firstSeen(ref seen: Vec<int32>, value: int32): int32 {
	for (let i = 0; i < (seen.length as int32); i++) { if (seen[i] == value) { return i; } }
	seen.push(value);
	return (seen.length as int32) - 1;
}

function pipelineOf(table: Vec<Material>, material: int32): int32 {
	for (let i = 0; i <= material; i++) {
		if (table[i].program == table[material].program && table[i].pass == table[material].pass) {
			return i;
		}
	}
	return material;
}

function textureNumberOf(table: Vec<Material>, material: int32): int32 {
	return table[material].texture.isTexture() ? table[material].texture.index + 1 : 0;
}

// The numbering as it was: pipelines and textures by first appearance in this list alone.
function firstSeenOracle(items: Vec<DrawItem>, table: Vec<Material>): Vec<int32> {
	let pipelines: Vec<int32> = [];
	let textures: Vec<int32> = [];
	let pipelineRank: Vec<int32> = [];
	let textureRank: Vec<int32> = [];
	for (const item of items) {
		pipelineRank.push(firstSeen(pipelines, pipelineOf(table, item.material.index)));
		textureRank.push(firstSeen(textures, textureNumberOf(table, item.material.index)));
	}
	let out: Vec<int32> = [];
	for (let i = 0; i < (items.length as int32); i++) {
		let j: int32 = i;
		while (j > 0) {
			const a: int32 = out[j - 1];
			const layerA: int32 = table[items[a].material.index].layer;
			const layerI: int32 = table[items[i].material.index].layer;
			const keyA: Vec<int32> = [layerA, items[a].order, pipelineRank[a], textureRank[a],
				items[a].material.index, items[a].mesh.index];
			const keyI: Vec<int32> = [layerI, items[i].order, pipelineRank[i], textureRank[i],
				items[i].material.index, items[i].mesh.index];
			let after: boolean = false;
			for (let k = 0; k < 6; k++) {
				if (keyA[k] != keyI[k]) {
					after = keyA[k] > keyI[k];
					break;
				}
			}
			if (!after) { break; }
			if ((out.length as int32) == j) { out.push(a); } else { out[j] = a; }
			j = j - 1;
		}
		if ((out.length as int32) == j) { out.push(i); } else { out[j] = i; }
	}
	return out;
}

function randomItems(count: int32, seed: int64, materialCount: int32): Vec<DrawItem> {
	let items: Vec<DrawItem> = [];
	let state: int64 = seed;
	for (let i = 0; i < count; i++) {
		state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
		items.push({
			...itemOf(((state >> 8) % materialCount) as int32, ((state >> 16) % 3) as int32, 0.0),
			mesh: { store: 1, index: ((state >> 20) % 3) as int32, generation: 1 },
		});
	}
	return items;
}

function sortedAgain(ref list: PassList, items: Vec<DrawItem>): boolean {
	const table: Vec<Material> = materials();
	collect(list, items, table);
	sortByMaterial(list, items, programsOf(table), table);
	return same(indicesOf(list), firstSeenOracle(items, table));
}

test "one list sorted over and over numbers each call by that call's first appearances" {
	let list: PassList = PassList.forPhase(Phase.Opaque);
	assert sortedAgain(list, randomItems(600, 5, 5));
	assert sortedAgain(list, [itemOf(4, 0, 0.0), itemOf(3, 0, 0.0), itemOf(2, 0, 0.0),
		itemOf(1, 0, 0.0), itemOf(0, 0, 0.0)]);
	assert sortedAgain(list, [itemOf(0, 0, 0.0), itemOf(1, 0, 0.0), itemOf(2, 0, 0.0),
		itemOf(3, 0, 0.0), itemOf(4, 0, 0.0)]);
	assert sortedAgain(list, randomItems(40, 6, 5));
	assert sortedAgain(list, randomItems(1500, 7, 5));
	assert sortedAgain(list, randomItems(3, 8, 5));
}

test "a repeated call and a second list keep their own numbering" {
	let first: PassList = PassList.forPhase(Phase.Opaque);
	let second: PassList = PassList.forPhase(Phase.Opaque);
	const one: Vec<DrawItem> = randomItems(200, 11, 5);
	const two: Vec<DrawItem> = randomItems(200, 12, 5);
	assert sortedAgain(first, one);
	assert sortedAgain(second, two);
	assert sortedAgain(first, one);
	assert sortedAgain(first, two);
}

test "the rank epoch wraps without a stale rank surviving" {
	let list: PassList = PassList.forPhase(Phase.Opaque);
	assert sortedAgain(list, randomItems(300, 21, 5));
	list.pipelines.epoch = 2147483646;
	list.textures.epoch = 2147483646;
	assert sortedAgain(list, randomItems(300, 22, 5));
	assert sortedAgain(list, randomItems(300, 23, 5));
	assert list.pipelines.epoch == 1 && list.textures.epoch == 1;
	assert sortedAgain(list, randomItems(300, 24, 5));
}
