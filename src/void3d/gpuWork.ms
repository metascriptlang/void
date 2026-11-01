// What one view hands the GPU cull: an input per kept item, a work item per item of the view's
// pass list, and one run per batch, where a batch is the neighbours drawPassList would draw as
// one instanced draw (sameBatch). A shadow cascade is a view with its own work list over the same
// inputs.

import { identity } from "../math/math3d";
import { DrawItem } from "./draw";
import { MeshData } from "./meshData";
import { CullRun, CullWork, MeshInput, meshInputOf } from "./gpuCull";

export function meshInputOfItem(
	item: Readonly<DrawItem>,
	meshes: Readonly<Span<MeshData>>,
): MeshInput {
	const data: Readonly<MeshData> = meshes[item.mesh.index];
	if (!data.isIndexed()) {
		console.log(`void3d: mesh ${item.mesh.index} has no indices; an indirect draw is indexed`);
		unreachable;
	}
	const range = item.range;
	const first: int32 = range === null ? 0 : range.base;
	const count: int32 = range === null ? data.indexCount() : range.count;
	const indices = { firstIndex: first as uint32, indexCount: count as uint32, baseVertex: 0 };
	const geometry = item.skinGeometry;
	return geometry === null ? meshInputOf(item.world, data.bounds, indices) :
		meshInputOf(identity(), geometry.bounds, indices);
}

// The pass list's order, LOD-culled items left out, cut into runs of sameBatch neighbours. A
// run's slots in the visible list follow the runs before it.
export function viewWorkOf(
	order: Readonly<Span<int32>>,
	items: Readonly<Span<DrawItem>>,
	ref work: Vec<CullWork>,
	ref runs: Vec<CullRun>,
): void {
	while ((work.length as int32) > 0) { work.pop(); }
	while ((runs.length as int32) > 0) { runs.pop(); }
	let runStart: int32 = -1;
	for (const index of order) {
		if (items[index].lodCulled) { continue; }
		if (runStart < 0 || !items[runStart].sameBatch(items[index])) {
			runs.push({ first: work.length as uint32, mesh: index as uint32, count: { value: 0 } });
			runStart = index;
		}
		work.push({ input: index as uint32, batch: (runs.length - 1) as uint32 });
	}
}
