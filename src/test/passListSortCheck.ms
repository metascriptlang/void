import { translation } from "../math/math3d";
import { DrawItem, MeshId, MaterialId } from "../void3d/draw";
import { Material, Phase } from "../void3d/material";
import { TextureId } from "../void3d/texture";
import { Program, ProgramKey } from "../void3d/gpu3d";
import { RenderState, Face } from "../gpu/state";
import { PassList, collect, sortBackToFront, sortByLayer, sortByMaterial } from "../void3d/passList";

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
