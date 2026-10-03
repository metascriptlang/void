// The picking half of h3d.scene.Interactive and h3d.scene.Scene.rayCastEventTargets (its
// non-physics branch): a ray against the visible meshes under pickable nodes, each tested
// against its bounds and then its triangles, the nearest hit kept.

import { Vec3, Mat4 } from "../math/math3d";
import { Bounds3D } from "./bounds";
import { MeshData } from "./meshData";
import { DrawContext } from "./draw";
import { Face } from "../gpu/state";
import { Ray } from "./ray";
import {
	Scene3D,
	NodeId3D,
	NodeKind,
	NodeFlag,
	NO_NODE_3D,
	NO_NODE_ID,
	syncWorld,
} from "./scene";

export struct PickHit {
	owner: NodeId3D;
	mesh: NodeId3D;
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

// PENDING3D: pick-owner-is-a-flag
// PENDING3D: pick-distance-from-ray-origin
export function pickNearest(scene: Scene3D, ray: Ray): Result<PickHit, PickError> {
	scene.requireOpen("pickNearest");
	const _synced: int32 = syncWorld(scene);
	const context: DrawContext = scene.context;
	let best: PickHit = {
		owner: NO_NODE_ID,
		mesh: NO_NODE_ID,
		distance: -1.0,
		point: ray.origin,
	};
	let top: int32 = 0;
	scene.stack[top] = scene.root;
	top = top + 1;
	while (top > 0) {
		top = top - 1;
		const index: int32 = scene.stack[top];
		if (!scene.nodes[index].flags.has(NodeFlag.Visible)) { continue; }
		const owner: int32 = scene.nodes[index].kind == NodeKind.Mesh
			? scene.pickableOwner(index)
			: NO_NODE_3D;
		if (owner != NO_NODE_3D) {
			const mesh: int32 = scene.meshes[scene.nodes[index].payload].mesh.index;
			const material: int32 = scene.meshes[scene.nodes[index].payload].material.index;
			const hit: MeshHit = context.meshData[mesh].meshHit(
				context.materials[material].pass.culling,
				scene.nodes[index].world,
				ray,
			);
			const nearer: boolean = best.distance < 0.0 || hit.distance < best.distance;
			if (hit.distance >= 0.0 && nearer) {
				best = {
					owner: scene.nodeIdAt(owner),
					mesh: scene.nodeIdAt(index),
					distance: hit.distance,
					point: hit.point,
				};
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

function pickableOwner(this scene: Scene3D, index: int32): int32 {
	let at: int32 = index;
	while (at != NO_NODE_3D) {
		if (scene.nodes[at].flags.has(NodeFlag.Pickable)) { return at; }
		at = scene.nodes[at].parent;
	}
	return NO_NODE_3D;
}

// Heaps' ObjectCollider over OptimizedCollider(bounds, polygon), except that a ray starting
// inside the bounds still reaches the triangles: getCollider() never yields the
// OptimizedCollider that rayCastEventTargets would set checkInside on (Scene.hx:331).
// PENDING3D: pick-origin-inside-bounds
function meshHit(this data: MeshData, culling: Face, world: Mat4, ray: Ray): MeshHit {
	const box: Bounds3D = data.bounds;
	if (box.isEmpty()) { return MISS; }
	const local: Ray = ray.transformed(world.inverseAffine());
	if (box.rayIntersection(local) < 0.0 && !box.contains(local.origin)) { return MISS; }
	const along: float32 = data.rayIntersection(local, seenThrough(culling, world));
	if (along < 0.0) { return MISS; }
	const point: Vec3 = local.pointAt(along) * world;
	return { distance: (point - ray.origin).length(), point: point };
}

// A mirroring world matrix turns the local winding over on screen, so the face the pass culls
// is the other local one.
function seenThrough(culling: Face, world: Mat4): Face {
	if (world.determinant3x3() >= 0.0) { return culling; }
	return match (culling) {
		Face.Back => Face.Front,
		Face.Front => Face.Back,
		Face.None => Face.None,
	};
}
