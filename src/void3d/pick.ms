// The picking half of h3d.scene.Interactive and h3d.scene.Scene.rayCastEventTargets (its
// non-physics branch): a ray against the visible meshes under pickable nodes, each tested
// against its bounds and then its triangles, the nearest hit kept.

import { Vec3, Mat4 } from "../math/math3d";
import { Bounds } from "./bounds";
import { MeshData } from "./meshData";
import { Material } from "./material";
import { Face } from "./pass";
import { Ray } from "./ray";
import {
	Scene,
	NodeId,
	NodeKind,
	FLAG_VISIBLE,
	FLAG_PICKABLE,
	NO_NODE,
	syncWorld,
} from "./scene";

export struct PickHit {
	// The pickable node that owns the hit: the mesh node itself or its nearest pickable ancestor.
	node: NodeId;
	mesh: NodeId;
	// World units from the ray's origin, and the world point hit.
	distance: float32;
	point: Vec3;
}

export enum PickError {
	NothingHit,
}

struct MeshHit {
	distance: float32;
	point: Vec3;
}

const MISS: MeshHit = { distance: -1.0, point: { x: 0.0, y: 0.0, z: 0.0 } };

// `meshData` and `materials` are the tables the scene's indices address (DrawContext's), read at
// the node's current mesh, so a baked frame swapped in by an animation is the one tested.
export function pickNearest(
	ref scene: Scene,
	meshData: Span<MeshData>,
	materials: Span<Material>,
	ray: Ray,
): Result<PickHit, PickError> {
	const _synced: int32 = syncWorld(scene);
	let best: PickHit = {
		node: { index: NO_NODE, generation: 0 },
		mesh: { index: NO_NODE, generation: 0 },
		distance: -1.0,
		point: ray.origin,
	};
	let top: int32 = 0;
	scene.stack[top] = scene.root;
	top = top + 1;
	while (top > 0) {
		top = top - 1;
		const index: int32 = scene.stack[top];
		if (!scene.nodes[index].has(FLAG_VISIBLE)) { continue; }
		const owner: int32 = scene.nodes[index].kind == NodeKind.Mesh
			? pickableOwner(scene, index)
			: NO_NODE;
		if (owner != NO_NODE) {
			const mesh: int32 = scene.meshes[scene.nodes[index].payload].mesh;
			const material: int32 = scene.meshes[scene.nodes[index].payload].material;
			if (mesh >= 0 && mesh < (meshData.length as int32) &&
				material >= 0 && material < (materials.length as int32)) {
				const hit: MeshHit = meshHit(
					meshData[mesh],
					materials[material].pass.culling,
					scene.nodes[index].world,
					ray,
				);
				const nearer: boolean = best.distance < 0.0 || hit.distance < best.distance;
				if (hit.distance >= 0.0 && nearer) {
					best = {
						node: { index: owner, generation: scene.generations[owner] },
						mesh: { index: index, generation: scene.generations[index] },
						distance: hit.distance,
						point: hit.point,
					};
				}
			}
		}
		const count: int32 = scene.nodes[index].children.length as int32;
		for (let i = count - 1; i >= 0; i--) {
			scene.stack[top] = scene.nodes[index].children[i];
			top = top + 1;
		}
	}
	if (best.distance < 0.0) { return Result.err(PickError.NothingHit); }
	return Result.ok(best);
}

function pickableOwner(scene: Scene, index: int32): int32 {
	let at: int32 = index;
	while (at != NO_NODE) {
		if (scene.nodes[at].has(FLAG_PICKABLE)) { return at; }
		at = scene.nodes[at].parent;
	}
	return NO_NODE;
}

// Heaps' OptimizedCollider(bounds, polygon) with checkInside, as rayCastEventTargets sets it,
// in the node's own space; the distance is measured back in the world, as ObjectCollider does.
function meshHit(data: MeshData, culling: Face, world: Mat4, ray: Ray): MeshHit {
	const box: Bounds = data.bounds;
	if (box.isEmpty()) { return MISS; }
	const local: Ray = ray.transformed(world.inverseAffine());
	if (local.direction.lengthSquared() == 0.0) { return MISS; }
	if (box.rayIntersection(local) < 0.0 && !box.contains(local.origin)) { return MISS; }
	const along: float32 = data.rayIntersection(local, culling);
	if (along < 0.0) { return MISS; }
	const point: Vec3 = local.pointAt(along) * world;
	return { distance: (point - ray.origin).length(), point: point };
}
