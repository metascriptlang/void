import { Mat4, translation } from "../math/math3d";
import { DrawItem, DrawRange, MaterialId, MeshId } from "../void3d/draw";
import { Material, Phase } from "../void3d/material";
import { Program, ProgramKey } from "../void3d/gpu3d";
import { RenderState } from "../gpu/state";
import { Bounds3D } from "../void3d/bounds";
import { Frustum3D } from "../void3d/frustum";
import { MeshData } from "../void3d/meshData";
import { PassList, filterFrustum, sortByMaterial } from "../void3d/passList";
import {
	CULL_WORKGROUP, CullBindings, CullRun, CullSlot, CullWork, InputScatterBindings, InputSlot,
	MeshInput, cullKernel, cullPlanesOf, scatterKernel,
} from "../void3d/gpuCull";
import { MeshInputTable, meshInputOfItem, viewWorkOf } from "../void3d/gpuWork";
import { collect } from "./drawHelpers";

function perspective(): Mat4 {
	return {
		m11: 1.0, m12: 0.0, m13: 0.0, m14: 0.0,
		m21: 0.0, m22: 1.0, m23: 0.0, m24: 0.0,
		m31: 0.0, m32: 0.0, m33: -1.125, m34: -1.0,
		m41: 0.0, m42: 0.0, m43: -1.125, m44: 0.0,
	};
}

function meshes(): Vec<MeshData> {
	const cube: Bounds3D = Bounds3D.fromValues(-0.25, -0.25, -0.25, 0.5, 0.5, 0.5);
	let out: Vec<MeshData> = [];
	for (let m = 0; m < 2; m++) {
		let data = MeshData.empty();
		for (let i = 0; i < 36 + m * 6; i++) { data.indices.push(0); }
		out.push({ ...data, bounds: cube });
	}
	return out;
}

function materials(): Vec<Material> {
	return [
		Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque),
		Material.plain(Program.UnlitTextured, RenderState.defaults(), Phase.Opaque),
	];
}

function itemAt(material: int32, mesh: int32, x: float32, z: float32): DrawItem {
	const id: MeshId = { store: 1, index: mesh, generation: 1 };
	const made: MaterialId = { store: 1, index: material, generation: 1 };
	return {
		mesh: id, material: made, world: translation(x, 0.0, z), order: 0, skin: null,
		skinGeometry: null, skinPalette: 0, range: null, instances: null,
	};
}

// 30 items over two meshes and two materials, a third of them outside the view, and one ranged.
function scene(): Vec<DrawItem> {
	let out: Vec<DrawItem> = [];
	for (let i = 0; i < 30; i++) {
		const x = ((i % 6) as float32) * 0.8 - 2.0;
		const z = i % 3 == 0 ? 5.0 : -1.0 - ((i % 4) as float32);
		out.push(itemAt(i % 2, (i >> 1) % 2, x, z));
	}
	const range: DrawRange = { base: 6, count: 12 };
	out[7] = { ...out[7], range: range };
	return out;
}

function sortedList(items: Vec<DrawItem>): PassList {
	const table = materials();
	let drawn: Vec<ProgramKey> = [];
	for (const material of table) { drawn.push(material.program); }
	let list: PassList = PassList.forPhase(Phase.Opaque);
	collect(list, items, table);
	sortByMaterial(list, items, drawn, table);
	return list;
}

function cull(
	items: Vec<DrawItem>, order: Vec<int32>, frustum: Frustum3D,
	ref work: Vec<CullWork>, ref runs: Vec<CullRun>,
): CullBindings {
	viewWorkOf(order, items, work, runs);
	const data = meshes();
	let inputs: MeshInput[] = [];
	for (const item of items) { inputs.push(meshInputOfItem(item, data)); }
	let visible: CullSlot[] = [];
	for (let i = 0; i < work.length; i++) { visible.push({ input: 0 }); }
	let b: CullBindings = {
		inputs, work: [...work], planes: cullPlanesOf(frustum),
		view: [{ itemCount: work.length as uint32 }], runs: [...runs], visible,
	};
	for (let i = 0; i < CULL_WORKGROUP; i++) {
		cullKernel({ id: { x: i as uint32, y: 0, z: 0 } }, b);
	}
	return b;
}

test "the GPU work list keeps what filterFrustum keeps, in the pass list's order" {
	const items = scene();
	const frustum = Frustum3D.fromMatrix(perspective());
	const list = sortedList(items);
	let order: Vec<int32> = [];
	for (let i = 0; i < list.count; i++) { order.push(list.indices[i]); }
	let work: Vec<CullWork> = [];
	let runs: Vec<CullRun> = [];
	const b = cull(items, order, frustum, work, runs);
	let gpu: Vec<int32> = [];
	for (const run of b.runs) {
		for (let n: uint32 = 0; n < run.count.value; n++) {
			const input = b.visible[run.first + n].input as int32;
			assert items[run.mesh as int32].sameBatch(items[input]);
			gpu.push(input);
		}
	}
	let filtered = list;
	const excluded = filterFrustum(filtered, items, meshes(), frustum);
	assert excluded > 0;
	assert gpu.length == filtered.count;
	for (let i = 0; i < filtered.count; i++) { assert gpu[i] == filtered.indices[i]; }
}

test "each run is a batch drawPassList would draw as one, and LOD-culled items are left out" {
	let items = scene();
	items[2] = { ...items[2], lodCulled: true };
	const list = sortedList(items);
	let order: Vec<int32> = [];
	for (let i = 0; i < list.count; i++) { order.push(list.indices[i]); }
	let work: Vec<CullWork> = [];
	let runs: Vec<CullRun> = [];
	viewWorkOf(order, items, work, runs);
	assert work.length == order.length - 1;
	for (const at of work) { assert at.input != 2; }
	for (let r = 0; r < runs.length; r++) {
		const end = r + 1 < runs.length ? runs[r + 1].first : work.length as uint32;
		assert end > runs[r].first;
		for (let w = runs[r].first; w < end; w++) {
			assert work[w].batch == r as uint32;
			assert items[runs[r].mesh as int32].sameBatch(items[work[w].input as int32]);
		}
		if (r > 0) {
			const before = work[runs[r].first - 1].input as int32;
			assert !items[before].sameBatch(items[work[runs[r].first].input as int32]);
		}
	}
}

test "an item's input carries its mesh's index range, or its own range" {
	const items = scene();
	const data = meshes();
	const whole = meshInputOfItem(items[2], data);
	assert whole.firstIndex == 0 && whole.indexCount == 42;
	const ranged = meshInputOfItem(items[7], data);
	assert ranged.firstIndex == 6 && ranged.indexCount == 12;
}

function scatter(
	resident: MeshInput[], updates: Vec<MeshInput>, slots: Vec<InputSlot>,
): MeshInput[] {
	let b: InputScatterBindings = {
		inputs: resident, updates: [...updates], slots: [...slots],
		view: [{ updateCount: updates.length as uint32, inputCount: resident.length as uint32 }],
	};
	for (let i = 0; i < CULL_WORKGROUP; i++) {
		scatterKernel({ id: { x: i as uint32, y: 0, z: 0 } }, b);
	}
	return b.inputs;
}

test "the resident table scatters a few changed inputs and re-uploads past the share" {
	const items = scene();
	const data = meshes();
	let table = MeshInputTable.empty();
	for (let i = 0; i < items.length; i++) { table.setInput(i, meshInputOfItem(items[i], data)); }
	let updates: Vec<MeshInput> = [];
	let slots: Vec<InputSlot> = [];
	assert table.takeUpload(updates, slots);
	assert updates.length == 0 && slots.length == 0;
	let resident: MeshInput[] = [...table.inputs];

	for (const slot of [4, 17, 4]) {
		let moved = items[slot];
		moved.world = translation(0.5, 0.25, -3.0);
		table.setInput(slot, meshInputOfItem(moved, data));
	}
	assert !table.takeUpload(updates, slots);
	assert slots.length == 2 && slots[0].slot == 4 && slots[1].slot == 17;
	resident = scatter(resident, updates, slots);
	for (let i = 0; i < items.length; i++) {
		assert resident[i].axisX.w == table.inputs[i].axisX.w;
		assert resident[i].axisZ.w == table.inputs[i].axisZ.w;
	}
	assert resident[17].axisX.w == 0.5;

	for (let i = 0; i < 5; i++) { table.setInput(i, meshInputOfItem(items[i], data)); }
	assert table.takeUpload(updates, slots);
	assert updates.length == 0;
	assert !table.takeUpload(updates, slots);
}
